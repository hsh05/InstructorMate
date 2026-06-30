# backend/services/attendance_service.py

from typing import Dict, Any, List
import cv2

class AttendanceService:
    def __init__(self):
        self.detection_memory: Dict[str, Dict[str, Any]] = {}

    def reset(self) -> None:
        self.detection_memory = {}

    def record_detection(self, student_id: str, name: str, confidence: str) -> None:
        if student_id not in self.detection_memory:
            self.detection_memory[student_id] = {"name": name, "detections": 0, "best_conf": confidence}

        self.detection_memory[student_id]["detections"] += 1

        if self.detection_memory[student_id]["best_conf"] != "High confidence" and confidence == "High confidence":
            self.detection_memory[student_id]["best_conf"] = "High confidence"

    def build_rows(self, lecture_number: str, students, min_detections_for_present: int = 2) -> List[Dict[str, Any]]:
        rows: List[Dict[str, Any]] = []

        for s in students:
            sid = getattr(s, 'student_id', None) or (s.get('student_id') if isinstance(s, dict) else None)
            name = getattr(s, 'name', None) or (s.get('name') if isinstance(s, dict) else None)
            
            det = int(self.detection_memory.get(sid, {}).get("detections", 0))
            best_conf = str(self.detection_memory.get(sid, {}).get("best_conf", "Unknown"))
            status = "Present" if det >= min_detections_for_present else "Absent"

            rows.append({
                "LectureNumber": lecture_number,
                "StudentID": sid,
                "Name": name,
                "Status": status,
                "Confidence": best_conf,
            })

        return rows

    def process_video_preview(self, facerec, video_path: str, lecture_number: str, students, process_fps: int = 3, min_detections_for_present: int = 2):
        self.reset()

        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            raise RuntimeError(f"Cannot open video: {video_path}")

        fps = cap.get(cv2.CAP_PROP_FPS)
        process_interval = 1.0 / max(1, process_fps)
        last_process_time = -1e9

        print(f"[INFO] Processing Video: {video_path} at {process_fps} FPS")

        while True:
            ret, frame = cap.read()
            if not ret:
                break

            current_time = cap.get(cv2.CAP_PROP_POS_MSEC) / 1000.0

            if (current_time - last_process_time) >= process_interval:
                last_process_time = current_time

                # Upscale the whole frame 
                zoomed_frame = cv2.resize(
                    frame, None, fx=2.0, fy=2.0,
                    interpolation=cv2.INTER_CUBIC,
                )

                last_detections = facerec.detect_faces(zoomed_frame)

                for d in last_detections:
                    if d["student_id"] is None:
                        continue
                    self.record_detection(d["student_id"], d["name"], d["confidence"])        

        cap.release()

        return self.build_rows(
            lecture_number=lecture_number,
            students=students,
            min_detections_for_present=min_detections_for_present,
        )