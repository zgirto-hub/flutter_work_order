from abc import ABC, abstractmethod
from typing import List


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

    async def embed(self, text: str) -> List[float]:
        raise NotImplementedError(
            "embed() is reserved for future providers; not implemented in phase 1"
        )
