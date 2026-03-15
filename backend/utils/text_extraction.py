import unicodedata
from PyPDF2 import PdfReader
from docx import Document
import pytesseract
from pdf2image import convert_from_path


def normalize_arabic(text):
    text = unicodedata.normalize("NFKC", text)
    return text


def extract_text(file_path, extension):
    text = ""

    if extension == "pdf":
        try:
            reader = PdfReader(file_path)
            for page in reader.pages:
                extracted = page.extract_text()
                if extracted:
                    text += extracted
            if not text.strip():
                images = convert_from_path(file_path)
                for img in images:
                    text += pytesseract.image_to_string(img, lang="ara+eng")
        except Exception:
            images = convert_from_path(file_path)
            for img in images:
                text += pytesseract.image_to_string(img, lang="ara+eng")

    elif extension == "docx":
        doc = Document(file_path)
        for para in doc.paragraphs:
            text += para.text + "\n"

    elif extension == "txt":
        with open(file_path, "r", encoding="utf-8") as f:
            text = f.read()

    elif extension in ["jpg", "jpeg", "png"]:
        try:
            text = pytesseract.image_to_string(file_path, lang="ara+eng")
        except Exception:
            text = ""

    return normalize_arabic(text)
