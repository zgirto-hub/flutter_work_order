from .local_ollama import OllamaProvider
from .gemini import GeminiProvider

PROVIDERS: dict[str, type] = {
    "local": OllamaProvider,
    "gemini": GeminiProvider,
}
