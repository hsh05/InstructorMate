# backend/api/attendance_routes.py

import os
import tempfile
import io
import csv
import numpy as np
import cv2
import face_recognition

from typing import Any, Dict, List
from fastapi import APIRouter, UploadFile, File, Form, HTTPException, Depends
from fastapi.responses import Response
from pydantic import BaseModel
from sqlalchemy.orm import Session
from docxtpl import DocxTemplate

from db.database import get_db
from repositories.pg_repository import PgAttendanceRepository
from services.face_recognizer import FaceRecognizer
from services.attendance_service import AttendanceService
from db.models import Student, Workspace, Instructor 

router = APIRouter(tags=["Attendance"])

def get_attendance_repo(db: Session = Depends(get_db)) -> PgAttendanceRepository:
    return PgAttendanceRepository(db)

@router.get("/attendance/last-lecture")
def get_last_lecture(workspace_id: int, section_id: str, repo: PgAttendanceRepository = Depends(get_attendance_repo)):
    last = repo.get_last_lecture_number(workspace_id, section_id)
    return {"ok": True, "last_lecture": last}

class PreviewRequest(BaseModel):
    workspace_id: int
    section_id: str
    lecture_number: int

@router.post("/attendance/process-video")
async def process_video_attendance(
    workspace_id: int = Form(...),
    section_id: str = Form(...),
    lecture_number: int = Form(...),
    video: UploadFile = File(...),
    repo: PgAttendanceRepository = Depends(get_attendance_repo)
):
    # Save video to a temporary file that cleans itself up after
    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as temp_video:
        temp_video.write(await video.read())
        temp_video_path = temp_video.name

    try:
        fr = FaceRecognizer()
        att_service = AttendanceService()

        # Load students and encodings from NeonDB
        db_students = repo.get_students_with_encodings(workspace_id, section_id)
        fr.set_known_faces(db_students)

        raw_rows = att_service.process_video_preview(
            facerec=fr,
            video_path=temp_video_path,
            lecture_number=str(lecture_number),
            students=db_students,
            process_fps=4,
            min_detections_for_present=2
        )

        rows = [
            {
                "student_id": str(r.get("StudentID", "")),
                "name": str(r.get("Name", "")),
                "status": str(r.get("Status", "Absent")),
                "confidence": str(r.get("Confidence", "Unknown")),
            }
            for r in raw_rows
        ]
        
        total_present = sum(1 for r in rows if r["status"].lower() == "present")
        total_absent = sum(1 for r in rows if r["status"].lower() == "absent")

        return {
            "ok": True,
            "lecture_number": lecture_number,
            "total_students": len(rows),
            "total_present": total_present,
            "total_absent": total_absent,
            "rows": rows,
        }
    finally:
        # Always clean up the large video file from the cloud server!
        if os.path.exists(temp_video_path):
            os.remove(temp_video_path)

@router.post("/attendance/preview-images")
async def preview_images_attendance(
    workspace_id: int = Form(...),
    section_id: str = Form(...),
    lecture_number: int = Form(...),
    images: List[UploadFile] = File(...),
    repo: PgAttendanceRepository = Depends(get_attendance_repo)
):
    try:
        fr = FaceRecognizer()

        # Load students and encodings
        db_students = repo.get_students_with_encodings(
            workspace_id,
            section_id,
        )

        fr.set_known_faces(db_students)

        detection_counts = {}

        for student in db_students:
            detection_counts[str(student.student_id)] = {
                "count": 0,
                "confidence": "Unknown",
            }

        # ==========================================
        # Process each uploaded image
        # ==========================================
        for uploaded in images:
            image_bytes = await uploaded.read()

            np_arr = np.frombuffer(image_bytes, np.uint8)

            frame = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

            if frame is None:
                continue

            # =========================
            # Image enhancement only
            # =========================
            # shrink extremely large images first
            MAX_DIM = 1920

            h, w = frame.shape[:2]

            if max(w, h) > MAX_DIM:
                scale = MAX_DIM / max(w, h)

                frame = cv2.resize(
                    frame,
                    None,
                    fx=scale,
                    fy=scale,
                    interpolation=cv2.INTER_AREA,
                                            )
            # upscale small images
            h, w = frame.shape[:2]

            if w < 1280:
                scale = 1280 / w
                frame = cv2.resize(
                    frame,
                    None,
                    fx=scale,
                    fy=scale,
                    interpolation=cv2.INTER_CUBIC,
                )

            # improve contrast
            frame = cv2.convertScaleAbs(
                frame,
                alpha=1.15,
                beta=10,
            )

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

            # ==========================================
            # Scan 1: full image
            # ==========================================
            all_encodings = []

            full_locs = face_recognition.face_locations(rgb, model="hog")
            full_encs = face_recognition.face_encodings(rgb, full_locs)
            all_encodings.extend(full_encs)

            # ==========================================
            # Scan 2-5: 4 tiles (2x2 grid)
            # Helps detect small/distant faces
            # ==========================================
            img_h, img_w = rgb.shape[:2]
            half_h, half_w = img_h // 2, img_w // 2

            tiles = [
                (0,      half_h, 0,      half_w),  # top-left
                (0,      half_h, half_w, img_w),   # top-right
                (half_h, img_h,  0,      half_w),  # bottom-left
                (half_h, img_h,  half_w, img_w),   # bottom-right
            ]

            for (r1, r2, c1, c2) in tiles:
                tile = rgb[r1:r2, c1:c2]
                tile_locs = face_recognition.face_locations(tile, model="hog")
                tile_encs = face_recognition.face_encodings(tile, tile_locs)
                all_encodings.extend(tile_encs)

            if not all_encodings:
                continue

            # ==========================================
            # Recognize every detected face encoding
            # ==========================================
            seen_in_this_image = set()

            for encoding in all_encodings:
                name, confidence = fr.recognize_face(encoding)

                if name == "Unknown":
                    continue

                sid = str(name)

                # Only count each student ONCE per image (tiles may detect same face twice)
                if sid in seen_in_this_image:
                    continue
                seen_in_this_image.add(sid)

                if sid not in detection_counts:
                    detection_counts[sid] = {
                        "count": 0,
                        "confidence": confidence,
                    }

                detection_counts[sid]["count"] += 1
                # Keep the best confidence seen so far
                if detection_counts[sid]["confidence"] != "High confidence":
                    detection_counts[sid]["confidence"] = confidence

        # ==========================================
        # Build attendance rows
        # ==========================================
        rows = []

        for student in db_students:
            sid = str(student.student_id)

            count = detection_counts.get(sid, {}).get("count", 0)

            confidence = detection_counts.get(
                sid,
                {},
            ).get("confidence", "Unknown")

            status = (
                "Present"
                if count >= 1
                else "Absent"
            )

            rows.append({
                "student_id": sid,
                "name": student.student_name,
                "status": status,
                "confidence": confidence,
            })

        total_present = sum(
            1 for r in rows
            if r["status"] == "Present"
        )

        total_absent = sum(
            1 for r in rows
            if r["status"] == "Absent"
        )

        return {
            "ok": True,
            "lecture_number": lecture_number,
            "total_students": len(rows),
            "total_present": total_present,
            "total_absent": total_absent,
            "rows": rows,
        }

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=str(e),
        )
        
class ConfirmRow(BaseModel):
    student_id: str
    status: str
    confidence: str = "Unknown"

class ConfirmRequest(BaseModel):
    workspace_id: int
    section_id: str
    lecture_number: int
    rows: List[ConfirmRow]

@router.post("/attendance/confirm")
def attendance_confirm(req: ConfirmRequest, repo: PgAttendanceRepository = Depends(get_attendance_repo)) -> Dict[str, Any]:
    mapped_rows = [
        {"StudentID": r.student_id, "Status": r.status, "Confidence": r.confidence}
        for r in req.rows
    ]

    repo.save_attendance_for_lecture(req.workspace_id, req.section_id, req.lecture_number, mapped_rows)

    return {
        "ok": True,
        "message": "Attendance saved successfully",
        "lecture_number": req.lecture_number,
        "saved_rows": len(mapped_rows)
    }

@router.get("/attendance/lecture")
def get_lecture_attendance(
    workspace_id: int, 
    section_id: str, 
    lecture_number: int, 
    repo: PgAttendanceRepository = Depends(get_attendance_repo)
):
    """Fetches the attendance records for a specific lecture."""
    rows = repo.fetch_attendance_rows(workspace_id, section_id, lecture_number)
    return {"ok": True, "rows": rows}

@router.get("/attendance/available-lectures")
def get_available_lectures(
    workspace_id: int, 
    section_id: str, 
    repo: PgAttendanceRepository = Depends(get_attendance_repo)
):
    """Finds all the unique lecture numbers that have recorded attendance."""
    all_rows = repo.fetch_attendance_rows(workspace_id, section_id)
    # Extract just the unique lecture numbers and sort them
    unique_lectures = sorted(list(set(row["lecture_number"] for row in all_rows)))
    
    return {"ok": True, "lectures": unique_lectures}

@router.get("/export-attendance")
def export_attendance(workspace_id: int, section_id: str, lecture_number: int | None = None, repo: PgAttendanceRepository = Depends(get_attendance_repo)):
    rows = repo.fetch_attendance_rows(workspace_id, section_id, lecture_number)
    students = repo.get_students_with_encodings(workspace_id, section_id)
    name_map = {s.student_id: s.student_name for s in students}

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["lecture_number", "student_id", "name", "status", "confidence"])

    for r in rows:
        writer.writerow([
            r["lecture_number"], r["student_id"], name_map.get(r["student_id"], ""),
            r["status"], r["confidence"]
        ])

    filename = "attendance_all_lectures.csv" if lecture_number is None else f"attendance_lecture_{lecture_number}.csv"

    return Response(
        content=output.getvalue().encode("utf-8"),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'}
    )

@router.post("/encoding/upload")
async def upload_encoding(
    student_id: str = Form(...),
    override: bool = Form(False),
    files: List[UploadFile] = File(...),
    repo: PgAttendanceRepository = Depends(get_attendance_repo),
    db: Session = Depends(get_db)
):
    if not files:
        raise HTTPException(status_code=400, detail="No images uploaded")
    
    student = db.query(Student).filter(Student.student_id == student_id).first()
    if not student:
        raise HTTPException(status_code=404, detail="Student not found in database")
        
    if student.facial_encoding and len(student.facial_encoding) > 0 and not override:
        return {
            "ok": False,
            "needs_override": True,
            "message": "Student already has encoding. Override?"
        }
    
    fr = FaceRecognizer()
    encodings = []

    for f in files:
        image_bytes = await f.read()
        enc = fr.generate_encoding_from_image(image_bytes)
        if enc is not None:
            encodings.append(enc)

    if not encodings:
        raise HTTPException(status_code=400, detail="No face detected in any image")

    avg_encoding = np.mean(encodings, axis=0)

    encoding_list = avg_encoding.tolist()
    success = repo.update_student_encoding(student_id, encoding_list)

    return {
        "ok": True,
        "message": "Encoding saved successfully"
    }

@router.get("/encoding/students")
def get_encoding_students(db: Session = Depends(get_db)):
    """Fetches all students and flags whether they have a saved facial encoding."""
    students = db.query(Student).all()
    
    return [
        {
            "student_id": s.student_id,
            "name": s.student_name,
            # Checks if the encoding column is NOT empty
            "has_encoding": s.facial_encoding is not None and len(s.facial_encoding) > 0 
        }
        for s in students
    ]

# ==========================================
# Generate Warning Report Route
# ==========================================
class WarningReportRequest(BaseModel):
    workspace_id: int
    section_id: str
    student_id: str
    absences: int

@router.post("/attendance/generate-warning-report")
def generate_warning_report(data: WarningReportRequest, db: Session = Depends(get_db)):
    # 1. Get student using SQLAlchemy
    student = db.query(Student).filter(Student.student_id == data.student_id).first()
    if not student:
        raise HTTPException(status_code=404, detail="Student not found")

    # 2. Get course info using SQLAlchemy
    workspace = db.query(Workspace).filter(Workspace.workspace_id == data.workspace_id).first()
    if not workspace:
        raise HTTPException(status_code=404, detail="Workspace not found")

        # Get instructor
    instructor = db.query(Instructor).filter(Instructor.instructor_id == workspace.instructor_id).first()

    instructor_name = instructor.full_name if instructor else "Unknown"

    # 3. Load Template
    BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    template_path = os.path.join(BASE_DIR, "templates", "warning_template.docx")
    
    if not os.path.exists(template_path):
        raise HTTPException(status_code=500, detail=f"Warning template file missing at {template_path}")

    doc = DocxTemplate(template_path)

    # 4. Warning logic
    first = 4 <= data.absences < 8
    second = 8 <= data.absences < 10
    third = data.absences >= 10

    context = {
        "course_title": workspace.course_title,
        "course_code": workspace.course_code,
        "section": data.section_id,
        "semester": workspace.semester,
        "student_name": student.student_name, 
        "student_id": student.student_id,
        "absences": data.absences,
        "first_warning": "☑" if first else "☐",
        "second_warning": "☑" if second else "☐",
        "third_warning": "☑" if third else "☐",
        "instructor_name": instructor_name,
    }

    doc.render(context)

    # 5. Save directly to RAM
    file_stream = io.BytesIO()
    doc.save(file_stream)
    file_stream.seek(0)

    filename = f"Warning_{data.student_id}_{workspace.course_code}.docx"

    return Response(
        content=file_stream.read(),
        media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"'
        },
    )