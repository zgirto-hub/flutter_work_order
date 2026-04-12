from dataclasses import dataclass
from typing import List, Tuple, Optional


@dataclass
class Chunk:
    chunk_index: int
    source_page: Optional[int]
    content: str


def chunk_paragraphs(
    paragraphs: List[Tuple[Optional[int], str]],
    max_words: int = 500,
    overlap_words: int = 50,
) -> List[Chunk]:
    if not paragraphs:
        return []

    chunks: List[Chunk] = []
    chunk_index = 0

    normalized: List[Tuple[Optional[int], List[str]]] = []
    for page, text in paragraphs:
        words = text.split()
        if not words:
            continue
        if len(words) <= max_words:
            normalized.append((page, words))
        else:
            step = max_words - overlap_words
            if step <= 0:
                step = max_words
            for start in range(0, len(words), step):
                window = words[start : start + max_words]
                if window:
                    normalized.append((page, window))

    current_words: List[str] = []
    current_page: Optional[int] = None

    def emit() -> None:
        nonlocal chunks, current_words, current_page, chunk_index
        if not current_words:
            return
        chunks.append(
            Chunk(
                chunk_index=chunk_index,
                source_page=current_page,
                content=" ".join(current_words),
            )
        )
        chunk_index += 1

    for page, words in normalized:
        if current_words and len(current_words) + len(words) > max_words:
            tail = current_words[-overlap_words:] if overlap_words > 0 else []
            emit()
            current_words = list(tail)
            current_page = page
        elif not current_words:
            current_page = page
        current_words.extend(words)

    emit()
    return chunks
