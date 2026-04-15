from .local_ollama import OllamaProvider
from .gemini import GeminiProvider
from .groq import GroqProvider
from .mistral import MistralProvider

PROVIDERS = {
    "local": OllamaProvider,
    "gemini": GeminiProvider,
    "groq": GroqProvider,
    "mistral": MistralProvider,
}
