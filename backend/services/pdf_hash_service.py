import hashlib


class PdfHashService:
    @staticmethod
    def compute(data: bytes) -> str:
        return hashlib.sha256(data).hexdigest()
