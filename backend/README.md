# Backend

## Manual RAG Assistant

One-time server setup (run on the server before using the feature):

```bash
# Pull the embedding model
ollama pull nomic-embed-text-v2-moe
```

Note: Gemma 4 must already be installed (`ollama pull gemma3:e2b` or similar).

## API Endpoints

- `POST /api/manuals/upload` - Upload a manual
- `GET /api/manuals/` - List all manuals
- `DELETE /api/manuals/{manual_id}` - Delete a manual
- `POST /api/manuals/ask` - Ask a question