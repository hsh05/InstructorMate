class ExtractionService:  # Extracts structured fields from text

    def extract_fields(self, text: str) -> dict:
        # FIX #4: Return all 6 fields that the workspace CSV and repository expect.
        # Previously only returned 3 fields — instructor_email, course_code, and
        # course_name were missing, so they'd never be populated on import.
        # Replace these stubs with your OpenAI / extraction logic.
        return {
            "course_title": "",
            "semester": "",
            "office_hours": "",
            "instructor_email": "",
            "course_code": "",
            "course_name": "",
        }