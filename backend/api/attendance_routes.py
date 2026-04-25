# backend/api/attendance_routes.py

import os
import tempfile
import io
import csv
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
from db.models import Student, Workspace 

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
    repo: PgAttendanceRepository = Depends(get_attendance_repo)
):
    if not files:
        raise HTTPException(status_code=400, detail="No images uploaded")
    
    fr = FaceRecognizer()
    # Process the first image in memory
    image_bytes = await files[0].read()
    encoding = fr.generate_encoding_from_image(image_bytes)
    
    if encoding is None:
        raise HTTPException(status_code=400, detail="No face detected in image")
        
    encoding_list = encoding.tolist()
    success = repo.update_student_encoding(student_id, encoding_list)
    
    if not success:
        raise HTTPException(status_code=404, detail="Student not found in database")
        
    return {"ok": True, "message": "Encoding saved successfully"}

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

    # 3. Load Template
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))
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