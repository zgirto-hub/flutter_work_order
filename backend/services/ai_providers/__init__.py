from .local_ollama import OllamaProvider
from .gemini import GeminiProvider
from .groq import GroqProvider

PROVIDERS = {"local": OllamaProvider, "gemini": GeminiProvider, "groq": GroqProvider}
