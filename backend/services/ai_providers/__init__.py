from .local_ollama import OllamaProvider
from .gemini import GeminiProvider

PROVIDERS = {"local": OllamaProvider, "gemini": GeminiProvider}
