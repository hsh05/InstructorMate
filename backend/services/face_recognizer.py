# backend/services/face_recognizer.py

from typing import List, Dict, Any, Optional
import cv2
import numpy as np
import face_recognition

class FaceRecognizer:
    def __init__(self, frame_resizing: float = 0.7, high_confidence: float = 0.45, low_confidence: float = 0.60):
        self.frame_resizing = frame_resizing
        self.high_confidence = high_confidence
        self.low_confidence = low_confidence

        self.known_face_encodings: List[np.ndarray] = []
        self.known_student_ids: List[str] = []
        self.known_student_names: List[str] = []

    def set_known_faces(self, students) -> None:
        """Loads known faces into memory. Expects a list of student dictionary/objects."""
        self.known_face_encodings = []
        self.known_student_ids = []
        self.known_student_names = []

        for s in students:
            enc = getattr(s, 'facial_encoding', None) or (s.get('facial_encoding') if isinstance(s, dict) else None)
            sid = getattr(s, 'student_id', None) or (s.get('student_id') if isinstance(s, dict) else None)
            name = getattr(s, 'student_name', None) or (s.get('student_name') if isinstance(s, dict) else None)
            
            if enc is None or len(enc) == 0:
                continue
                
            self.known_face_encodings.append(np.asarray(enc, dtype=float))
            self.known_student_ids.append(sid)
            self.known_student_names.append(name)

        print(f"[INFO] FaceRecognizer loaded {len(self.known_face_encodings)} known encodings.")

    def generate_encoding_from_image(self, image_bytes: bytes) -> Optional[np.ndarray]:
        """
        Takes raw image bytes, decodes them, and returns face encoding.
        """
        nparr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if img is None:
            print("[WARN] Could not decode image bytes")
            return None

        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        encodings = face_recognition.face_encodings(rgb)

        if not encodings:
            print("[WARN] No face found in image.")
            return None

        return encodings[0]

    def recognize_face(self, face_encoding):
        """
        Matches a single face encoding against known faces.
        Returns:
            (student_id, confidence)
        """

        if not self.known_face_encodings:
            return "Unknown", "Unknown"

        distances = face_recognition.face_distance(
            self.known_face_encodings,
            face_encoding,
        )

        best_match_idx = int(np.argmin(distances))
        best_distance = float(distances[best_match_idx])

        if best_distance <= self.high_confidence:
            return (
                self.known_student_ids[best_match_idx],
                "High confidence",
            )

        elif best_distance <= self.low_confidence:
            return (
                self.known_student_ids[best_match_idx],
                "Low confidence",
            )

        return "Unknown", "Unknown"

    def detect_faces(self, frame) -> List[Dict[str, Any]]:
        frame = cv2.convertScaleAbs(frame, alpha=1.15, beta=10)
        small = cv2.resize(frame, (0, 0), fx=self.frame_resizing, fy=self.frame_resizing)
        rgb_small = cv2.cvtColor(small, cv2.COLOR_BGR2RGB)

        face_locations = face_recognition.face_locations(rgb_small)
        face_encodings = face_recognition.face_encodings(rgb_small, face_locations)

        detections: List[Dict[str, Any]] = []

        for loc, face_encoding in zip(face_locations, face_encodings):
            student_id: Optional[str] = None
            name = "Unknown"
            confidence = "Unknown"
            color = (0, 0, 255)
            best_distance: Optional[float] = None

            if self.known_face_encodings:
                distances = face_recognition.face_distance(self.known_face_encodings, face_encoding)
                best_match_idx = int(np.argmin(distances))
                best_distance = float(distances[best_match_idx])

                if best_distance <= self.high_confidence:
                    student_id = self.known_student_ids[best_match_idx]
                    name = self.known_student_names[best_match_idx]
                    confidence = "High confidence"
                    color = (0, 255, 0)

                elif best_distance <= self.low_confidence:
                    student_id = self.known_student_ids[best_match_idx]
                    name = self.known_student_names[best_match_idx]
                    confidence = "Low confidence"
                    color = (0, 165, 255)

            top, right, bottom, left = loc
            top = int(top / self.frame_resizing)
            right = int(right / self.frame_resizing)
            bottom = int(bottom / self.frame_resizing)
            left = int(left / self.frame_resizing)

            detections.append({
                "box": (top, right, bottom, left),
                "student_id": student_id,
                "name": name,
                "distance": best_distance,
                "confidence": confidence,
                "color": color,
            })

        return detections