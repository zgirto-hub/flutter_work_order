import os
import asyncio
import logging
from typing import List
from .base import AIProvider
from services.ollama_generator import GeneratorModelError

logger = logging.getLogger(__name__)
MISTRAL_API_KEY = os.environ.get("MISTRAL_API_KEY", "")
MISTRAL_MODEL = "mistral-small-latest"


class MistralProvider(AIProvider):
    def __init__(self):
        self._api_key = MISTRAL_API_KEY or os.environ.get("MISTRAL_API_KEY")

    @property
    def display_name(self) -> str:
        return "Mistral Small"

    def _scrub(self, msg: str) -> str:
        if self._api_key and self._api_key in msg:
            return msg.replace(self._api_key, "[API_KEY_SCRUBBED]")
        return msg

    async def generate(self, prompt: str, context_chunks: List[str]) -> str:
        if not self._api_key:
            raise GeneratorModelError("mistral", "missing_credentials")

        try:
            from mistralai import Mistral
        except ImportError:
            raise GeneratorModelError("mistral", "mistralai SDK not installed")

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

        try:
            client = Mistral(api_key=self._api_key)
            response = await client.chat.complete_async(
                model=MISTRAL_MODEL,
                messages=[{"role": "user", "content": full_prompt}],
            )
            answer = (response.choices[0].message.content or "").strip()
            if not answer:
                raise GeneratorModelError("mistral", "empty_response")
            return answer
        except GeneratorModelError:
            raise
        except Exception as e:
            error_msg = self._scrub(str(e))
            lowered = error_msg.lower()
            if "rate" in lowered or "quota" in lowered or "429" in lowered:
                raise GeneratorModelError("mistral", "quota_exceeded")
            logger.error(f"Mistral generation failed: {error_msg}")
            raise GeneratorModelError("mistral", error_msg[:100])

    async def health_check(self) -> bool:
        if not self._api_key:
            return False
        try:
            from mistralai import Mistral

            async def _check():
                client = Mistral(api_key=self._api_key)
                response = await client.chat.complete_async(
                    model=MISTRAL_MODEL,
                    messages=[{"role": "user", "content": "ping"}],
                    max_tokens=4,
                )
                return response.choices[0].message.content

            result = await asyncio.wait_for(_check(), timeout=10.0)
            return bool(result)
        except Exception:
            return False
