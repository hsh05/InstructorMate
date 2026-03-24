import hashlib


class FileHashService: #takes file bytes and return hex string 
    @staticmethod
    def compute(data: bytes) -> str:
        return hashlib.sha256(data).hexdigest()
