import json
import os
import shutil
import PyPDF2
import io
from fastapi import FastAPI, Depends, UploadFile, File, Form, HTTPException
from sqlalchemy.orm import Session
import models
from models import Material, Course
import schemas
from database import engine, get_db
from schemas import QuizGenerateRequest
from openai import OpenAI
from dotenv import load_dotenv
import docx
from pptx import Presentation

# Load the .env file
load_dotenv()

# Get the key from the hidden file
api_key = os.getenv("OPENAI_API_KEY")

if not api_key:
    raise ValueError("No OpenAI API Key found. Check your .env file!")

# Initialize the client using the environment variable
client = OpenAI(api_key=api_key)

# Create tables
models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="InstructorMate API")

# Ensure a local directory exists for file uploads (temporary until we add S3)
UPLOAD_DIR = "uploaded_materials"
os.makedirs(UPLOAD_DIR, exist_ok=True)

@app.post("/courses/", response_model=schemas.CourseResponse)
def create_course(course: schemas.CourseCreate, db: Session = Depends(get_db)):
    db_course = models.Course(**course.dict())
    db.add(db_course)
    db.commit()
    db.refresh(db_course)
    return db_course

@app.post("/courses/{course_id}/materials/", response_model=schemas.MaterialResponse)
async def upload_material(
    course_id: int, 
    material_type: str = Form(...), # Flutter will send 'syllabus' or 'slides'
    file: UploadFile = File(...),   # Flutter will send the actual PDF here
    db: Session = Depends(get_db)
):
    # 1. Verify the course exists
    course = db.query(models.Course).filter(models.Course.id == course_id).first()
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")

    # 2. Save the file locally
    file_location = f"{UPLOAD_DIR}/{file.filename}"
    with open(file_location, "wb+") as file_object:
        shutil.copyfileobj(file.file, file_object)

    # 3. Save the metadata to PostgreSQL
    db_material = models.Material(
        course_id=course_id,
        file_name=file.filename,
        file_path=file_location,
        material_type=material_type
    )
    db.add(db_material)
    db.commit()
    db.refresh(db_material)
    
    return db_material

@app.get("/courses/", response_model=list[schemas.CourseResponse])
def get_courses_with_materials(db: Session = Depends(get_db)):
    # This single line fetches all courses AND their nested materials automatically!
    courses = db.query(models.Course).all()
    return courses

@app.post("/courses/{course_id}/generate-quiz/")
async def generate_quiz(course_id: int, request: schemas.QuizGenerateRequest, db: Session = Depends(get_db)):
    selected_ids = request.selected_material_ids
    configs = request.configs
    
    # 1. Filter by the specific IDs
    materials = db.query(Material).filter(
        Material.course_id == course_id,
        Material.id.in_(selected_ids)
    ).all()
    
    if not materials:
        raise HTTPException(status_code=404, detail="No materials selected or found.")

    # 2. Extract Text
    combined_text = ""
    for m in materials:
        if os.path.exists(m.file_path):
            try:
                with open(m.file_path, "rb") as f:
                    reader = PyPDF2.PdfReader(f)
                    for page in reader.pages:
                        combined_text += page.extract_text() or ""
            except Exception as e:
                print(f"Error reading file {m.file_name}: {e}")

    if not combined_text.strip():
        raise HTTPException(status_code=400, detail="The selected files contain no readable text.")

    # 3. Call OpenAI with a STRICTOR prompt for your Flutter Model
    configs_as_dicts = [c.dict() for c in configs]
    
    prompt = f"""
    You are an educational assistant. Generate a quiz based ONLY on the text provided below.
    
    TEXT CONTENT:
    {combined_text[:10000]} 

    CONFIGURATIONS:
    {json.dumps(configs_as_dicts)} 

    OUTPUT FORMAT:
    Return a JSON object with a single key "questions". 
    Each question object MUST have:
    - "type": (e.g., "MCQ", "Essay", or "True/False")
    - "question": The text of the question.
    - "options": A list of 4 strings (null for Essay).
    - "answer": The string text of the correct answer.
    - "explanation": A brief explanation.
    - "general_feedback": A detailed model answer or explanation to be shown to the student after submission.
    """

    try:
        response = client.chat.completions.create(
            model="gpt-4o",
            messages=[{"role": "system", "content": "You are a quiz generator that outputs strictly valid JSON."},
                      {"role": "user", "content": prompt}],
            response_format={ "type": "json_object" }
        )
        
        quiz_data = json.loads(response.choices[0].message.content)
        
        # Safety check for Flutter
        if "questions" not in quiz_data:
            return {"questions": []}
            
        return quiz_data
        
    except Exception as e:
        print(f"OpenAI Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/edit-question/")
async def edit_question(request: dict):
    old_q = request.get("question_data")
    instruction = request.get("instruction")

    prompt = f"""
    Modify this quiz question based on this instruction: {instruction}
    Original Question: {json.dumps(old_q)}
    
    Return ONLY the updated JSON object for the question.
    """

    try:
        response = client.chat.completions.create(
            model="gpt-4o",
            messages=[{"role": "user", "content": prompt}],
            response_format={ "type": "json_object" }
        )
        return {"updated_question": json.loads(response.choices[0].message.content)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/generate-direct")
async def generate_direct(
    file: UploadFile = File(...),
    configs: str = Form(...)
):
    try:
        config_data = json.loads(configs)
        contents = await file.read()
        extracted_text = ""
        
        # Make it lowercase just to be safe
        filename = file.filename.lower()
        
        # 1. Handle PDFs
        if filename.endswith(".pdf"):
            pdf_reader = PyPDF2.PdfReader(io.BytesIO(contents))
            for page in pdf_reader.pages:
                text = page.extract_text()
                if text:
                    extracted_text += text + "\n"
                    
        # 2. Handle Word Documents (.docx)
        elif filename.endswith(".docx"):
            doc = docx.Document(io.BytesIO(contents))
            for para in doc.paragraphs:
                extracted_text += para.text + "\n"
                
        # 3. Handle PowerPoint (.pptx)
        elif filename.endswith(".pptx"):
            ppt = Presentation(io.BytesIO(contents))
            for slide in ppt.slides:
                for shape in slide.shapes:
                    if hasattr(shape, "text"):
                        extracted_text += shape.text + "\n"
                        
        # 4. Handle plain text
        elif filename.endswith(".txt"):
            extracted_text = contents.decode("utf-8")
            
        else:
            raise HTTPException(status_code=400, detail="Unsupported file. Please upload PDF, DOCX, PPTX, or TXT.")

        if not extracted_text.strip():
            raise HTTPException(status_code=400, detail="Could not extract text from the file.")

        # Pass to OpenAI
        questions = await generate_questions_with_ai(extracted_text, config_data)
        
        return {"questions": questions}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))