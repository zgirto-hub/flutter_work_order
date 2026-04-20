import os
import asyncio
import logging
from typing import List
from .base import AIProvider
from services.ollama_generator import GeneratorModelError

logger = logging.getLogger(__name__)
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "")
# Switched from llama-3.3-70b-versatile to llama-4-scout-17b-16e-instruct:
# - Free tier cap is 500K tokens/day (vs 100K/day on 70b) — 5x the daily
#   budget, enough to absorb a full office's real usage without early
#   fallback to local Ollama.
# - 17B params still a meaningful step up from local gemma4:e2b (5.1B).
# - Scout is the smaller/faster half of the Llama 4 family; latency on
#   Groq infrastructure stays in the 1-2s range for generation.
GROQ_MODEL = "meta-llama/llama-4-scout-17b-16e-instruct"


class GroqProvider(AIProvider):
    def __init__(self):
        self._api_key = GROQ_API_KEY or os.environ.get("GROQ_API_KEY")

    @property
    def display_name(self) -> str:
        return "Groq (Llama 4 Scout 17B)"

    def _scrub(self, msg: str) -> str:
        if self._api_key and self._api_key in msg:
            return msg.replace(self._api_key, "[API_KEY_SCRUBBED]")
        return msg

    async def generate(self, prompt: str, context_chunks: List[str]) -> str:
        if not self._api_key:
            raise GeneratorModelError("groq", "missing_credentials")

        try:
            from groq import AsyncGroq
        except ImportError:
            raise GeneratorModelError("groq", "groq SDK not installed")

        full_prompt = (
            "You are a technical synthesis expert for civil aviation maintenance.\n"
            "You have received relevant information from technical manuals below.\n\n"
            + "\n\n".join(
                f"[Context {i + 1}]\n{chunk}" for i, chunk in enumerate(context_chunks)
            )
            + f"\n\nQUESTION: {prompt}\n\n"
            + "Please provide a clear, accurate answer based on the context provided."
        )

        try:
            client = AsyncGroq(api_key=self._api_key)
            response = await client.chat.completions.create(
                model=GROQ_MODEL,
                messages=[{"role": "user", "content": full_prompt}],
            )
            answer = (response.choices[0].message.content or "").strip()
            if not answer:
                raise GeneratorModelError("groq", "empty_response")
            return answer
        except GeneratorModelError:
            raise
        except Exception as e:
            error_msg = self._scrub(str(e))
            lowered = error_msg.lower()
            if "rate" in lowered or "quota" in lowered or "429" in lowered:
                raise GeneratorModelError("groq", "quota_exceeded")
            logger.error(f"Groq generation failed: {error_msg}")
            raise GeneratorModelError("groq", error_msg[:100])

    async def generate_stream(self, prompt: str, context_chunks: List[str]):
        if not self._api_key:
            raise GeneratorModelError("groq", "missing_credentials")

        try:
            from groq import AsyncGroq
        except ImportError:
            raise GeneratorModelError("groq", "groq SDK not installed")

        full_prompt = (
            "You are a technical synthesis expert for civil aviation maintenance.\n"
            "You have received relevant information from technical manuals below.\n\n"
            + "\n\n".join(
                f"[Context {i + 1}]\n{chunk}" for i, chunk in enumerate(context_chunks)
            )
            + f"\n\nQUESTION: {prompt}\n\n"
            + "Please provide a clear, accurate answer based on the context provided."
        )

        try:
            client = AsyncGroq(api_key=self._api_key)
            stream = await client.chat.completions.create(
                model=GROQ_MODEL,
                messages=[{"role": "user", "content": full_prompt}],
                stream=True,
            )
            async for chunk in stream:
                content = chunk.choices[0].delta.content
                if content:
                    yield content
        except GeneratorModelError:
            raise
        except Exception as e:
            error_msg = self._scrub(str(e))
            lowered = error_msg.lower()
            if "rate" in lowered or "quota" in lowered or "429" in lowered:
                raise GeneratorModelError("groq", "quota_exceeded")
            logger.error(f"Groq streaming failed: {error_msg}")
            raise GeneratorModelError("groq", error_msg[:100])

    async def health_check(self) -> bool:
        if not self._api_key:
            return False
        try:
            from groq import AsyncGroq

            async def _check():
                client = AsyncGroq(api_key=self._api_key)
                response = await client.chat.completions.create(
                    model=GROQ_MODEL,
                    messages=[{"role": "user", "content": "ping"}],
                    max_tokens=4,
                )
                return response.choices[0].message.content

            result = await asyncio.wait_for(_check(), timeout=10.0)
            return bool(result)
        except Exception:
            return False
