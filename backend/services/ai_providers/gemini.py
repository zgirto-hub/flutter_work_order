import os
import logging
from typing import List
from .base import AIProvider
from services.ollama_generator import GeneratorModelError

logger = logging.getLogger(__name__)
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

GEMINI_MODELS = [
    {"id": "gemini-2.0-flash", "name": "Gemini 2.0 Flash", "free_quota": "1500/day"},
    {"id": "gemini-2.5-flash", "name": "Gemini 2.5 Flash", "free_quota": "20/day"},
]
DEFAULT_GEMINI_MODEL = "gemini-2.0-flash"


class GeminiProvider(AIProvider):
    def __init__(self):
        self._api_key = GEMINI_API_KEY or os.environ.get("GEMINI_API_KEY")
        if self._api_key:
            import google.generativeai as genai

            genai.configure(api_key=self._api_key)

    async def _get_model_id(self) -> str:
        try:
            from utils.app_settings import get_setting

            model_id = await get_setting("gemini_model")
            if model_id and any(m["id"] == model_id for m in GEMINI_MODELS):
                return model_id
        except Exception:
            pass
        return DEFAULT_GEMINI_MODEL

    @property
    def display_name(self) -> str:
        return "Gemini 2.5 Flash"

    async def generate(self, prompt: str, context_chunks: List[str]) -> str:
        if not self._api_key:
            raise GeneratorModelError("gemini", "missing_credentials")

        try:
            from google.generativeai import GenerativeModel
        except ImportError:
            raise GeneratorModelError("gemini", "google-generativeai not installed")

        try:
            model_id = await self._get_model_id()
            model = GenerativeModel(model_id)
            full_prompt = (
                "You are a technical synthesis expert for civil aviation maintenance.\n"
                "You have received relevant information from technical manuals below.\n\n"
                + "\n\n".join(
                    f"[Context {i + 1}]\n{chunk}"
                    for i, chunk in enumerate(context_chunks)
                )
                + f"\n\nQUESTION: {prompt}\n\n"
                + "Please provide a clear, accurate answer based on the context provided."
            )
            response = await model.generate_content_async(full_prompt)
            answer = response.text.strip()
            if not answer or not answer.strip():
                raise GeneratorModelError("gemini", "empty_response")
            return answer
        except Exception as e:
            error_msg = str(e)
            if self._api_key and self._api_key in error_msg:
                error_msg = error_msg.replace(self._api_key, "[API_KEY_SCRUBBED]")
            if "quota" in error_msg.lower():
                raise GeneratorModelError("gemini", "quota_exceeded")
            logger.error(f"Gemini generation failed: {error_msg}")
            raise GeneratorModelError("gemini", error_msg[:100])

    async def generate_stream(self, prompt: str, context_chunks: List[str]):
        if not self._api_key:
            raise GeneratorModelError("gemini", "missing_credentials")
        from google.generativeai import GenerativeModel
        import asyncio

        model_id = await self._get_model_id()
        model = GenerativeModel(model_id)
        full_prompt = (
            "You are a technical synthesis expert for civil aviation maintenance.\n"
            "You have received relevant information from technical manuals below.\n\n"
            + "\n\n".join(
                f"[Context {i + 1}]\n{chunk}" for i, chunk in enumerate(context_chunks)
            )
            + f"\n\nQUESTION: {prompt}\n\n"
            + "Please provide a clear, accurate answer based on the context provided."
        )

        def _stream():
            return model.generate_content(full_prompt, stream=True)

        response = await asyncio.to_thread(_stream)
        for chunk in response:
            if chunk.text:
                yield chunk.text

    async def health_check(self) -> bool:
        if not self._api_key:
            return False

        try:
            import asyncio
            from google.generativeai import GenerativeModel

            model_id = await self._get_model_id()

            async def _check():
                model = GenerativeModel(model_id)
                response = await model.generate_content_async("ping")
                return response.text

            response = await asyncio.wait_for(_check(), timeout=10.0)
            return bool(response)
        except Exception:
            return False
