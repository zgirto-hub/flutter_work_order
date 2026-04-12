import logging
from pathlib import Path
from uuid import UUID


class StorageError(Exception):
    pass


# Match files.py convention: paths are relative to the backend working directory.
BASE_DIR = Path("uploaded_files") / "manuals"


def _ensure_base_dir() -> None:
    BASE_DIR.mkdir(parents=True, exist_ok=True)


def path_for(manual_id: UUID, file_extension: str) -> Path:
    return BASE_DIR / f"{manual_id}.{file_extension}"


def save(manual_id: UUID, file_bytes: bytes, file_extension: str) -> Path:
    _ensure_base_dir()
    file_path = path_for(manual_id, file_extension)
    try:
        with open(file_path, "wb") as f:
            f.write(file_bytes)
        return file_path
    except Exception as e:
        raise StorageError(f"Failed to save file {file_path}: {e}") from e


def delete(manual_id: UUID, file_extension: str) -> None:
    file_path = path_for(manual_id, file_extension)
    if not file_path.exists():
        return
    try:
        file_path.unlink()
    except Exception as e:
        logging.warning(f"Failed to delete file {file_path}: {e}")
