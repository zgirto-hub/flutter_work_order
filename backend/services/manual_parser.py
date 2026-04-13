import fitz
from docx import Document
from io import BytesIO
from typing import List, Tuple


class NoExtractableTextError(Exception):
    pass


def parse(file_bytes: bytes, file_extension: str) -> List[Tuple[int | None, str]]:
    if file_extension == "pdf":
        return parse_pdf(file_bytes)
    elif file_extension == "docx":
        return parse_docx(file_bytes)
    elif file_extension in ("txt", "md"):
        return parse_txt(file_bytes)
    else:
        raise ValueError(f"Unsupported file extension: {file_extension}")


def parse_pdf(file_bytes: bytes) -> List[Tuple[int | None, str]]:
    paragraphs: List[Tuple[int | None, str]] = []

    with fitz.open(stream=file_bytes, filetype="pdf") as doc:
        total_chars = 0
        for page_num, page in enumerate(doc, start=1):
            text = page.get_text("text")
            text = text.strip()
            if text:
                total_chars += len(text)
                paragraphs.append((page_num, text))

    if total_chars < 20:
        raise NoExtractableTextError("The PDF contains no extractable text.")

    return paragraphs


def parse_docx(file_bytes: bytes) -> List[Tuple[int | None, str]]:
    paragraphs: List[Tuple[int | None, str]] = []

    doc = Document(BytesIO(file_bytes))

    for para in doc.paragraphs:
        text = para.text.strip()
        if text:
            paragraphs.append((None, text))

    if not paragraphs:
        raise NoExtractableTextError("The DOCX contains no extractable text.")

    return paragraphs


def parse_txt(file_bytes: bytes) -> List[Tuple[int | None, str]]:
    import re

    try:
        text = file_bytes.decode("utf-8")
    except UnicodeDecodeError:
        text = file_bytes.decode("latin-1")

    text = text.strip()
    if not text:
        raise NoExtractableTextError("The file contains no extractable text.")

    # Split on section-style delimiters (===, ---, ***) or double newlines.
    # This ensures structured manuals get section-level splits, not just
    # paragraph splits, producing cleaner chunks for vector search.
    section_pattern = re.compile(
        r"\n\s*[=\-\*]{3,}\s*\n"  # lines of ===, ---, or ***
        r"|\n{2,}"                 # or double+ newlines
    )

    paragraphs = []
    for para in section_pattern.split(text):
        para = para.strip()
        if para:
            paragraphs.append((None, para))

    if not paragraphs:
        raise NoExtractableTextError("The file contains no extractable text.")

    return paragraphs
