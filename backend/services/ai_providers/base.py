from abc import ABC, abstractmethod
from typing import List, AsyncIterator


class AIProvider(ABC):
    @property
    @abstractmethod
    def display_name(self) -> str:
        pass

    @abstractmethod
    async def generate(self, prompt: str, context_chunks: List[str]) -> str:
        pass

    @abstractmethod
    async def health_check(self) -> bool:
        pass

    async def generate_stream(
        self, prompt: str, context_chunks: List[str]
    ) -> AsyncIterator[str]:
        """Yield answer tokens one chunk at a time. Default falls back to non-streaming."""
        answer = await self.generate(prompt, context_chunks)
        yield answer

    async def embed(self, text: str) -> List[float]:
        raise NotImplementedError(
            "embed() is reserved for future providers; not implemented in phase 1"
        )
