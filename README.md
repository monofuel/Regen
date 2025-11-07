# Regen 🗃️

![Library](static/ComfyUI_00126_.png "why wouldn't you want a miqo'te reading all your documents and indexing everything")

📚 **A fast, lightweight document indexing tool that loads files, chunks them, and indexes with embeddings**

✨ **Features:**
- 🚀 Fast parallel processing with Nim
- 🔍 Semantic search using embeddings  
- 💾 No database required - uses flatty for binary serialization
- 📁 Works with git repos and local folders
- 🧠 Uses LM Studio for local embeddings (`text-embedding-embeddinggemma-300m`)


- Warning: file contents will be sent to the embedding api. defaults to LM Studio at 127.0.0.1:1234/v1 using text-embedding-embeddinggemma-300m.
- depending on your files and your environment, you may want to adjust the blacklisted filenames and extensions.

## 📋 TODO

- [x] 🌐 OpenAPI server interface
- [x] 🔌 MCP (Model Context Protocol) server support
- [ ] implement CORS configuration
- [x] support query - document embeddings in addition to similarity search
  - supported via embeddinggemma models only currently
  - [ ] support reduced embedding dimensions (eg: 256, 512)
- [ ] properly support multiple embedding models (currently only supports 1 in config json)

## ⚡ Quick start

- ensure you have `ripgrep` installed locally!

### 1) Configure indexing
- Add paths to track:
  - Folders: `regen --add-folder-index /path/to/folder`
  - Git repos: `regen --add-repo-index /path/to/repo`
- Build indexes: `regen --index-all`

Notes:
- Config lives at `~/.regen/config.json` and is created on first run.
- An API key is generated automatically. View it with: `regen --show-api-key`

### 2) Start a server
- OpenAPI server (HTTP):
  - Start: `regen --server [port] [address]`
  - Defaults: port 8095, address `0.0.0.0`
- MCP server (HTTP):
  - Start: `regen --mcp-server [port] [address]`
  - Defaults: port 8096, address `0.0.0.0`

Authentication:
- Protected endpoints/tools require `Authorization: Bearer <API_KEY>` where `<API_KEY>` is from `regen --show-api-key`.

### 3) Tools (available via both OpenAPI and MCP)
- ripgrep_search: keyword/regex search across all configured indexes
  - Inputs: `pattern` (string), `caseSensitive` (bool, default true), `maxResults` (int, default 100)
- embedding_search: semantic similarity search using embeddings
  - Inputs: `query` (string), `maxResults` (int, default 10), `model` (string, defaults to configured model), `extensions` (optional seq of file extensions)

HTTP endpoints (OpenAPI server):
- Health: `GET /` (no auth)
- OpenAPI spec: `GET /openapi.json` (no auth)
- Ripgrep: `POST /search/ripgrep` (Bearer auth)
- Embedding: `POST /search/embedding` (Bearer auth)

Example (ripgrep over HTTP):
```bash
curl -H "Authorization: Bearer $(regen --show-api-key | sed -n 's/API Key: //p')" \
     -H "Content-Type: application/json" \
     -d '{"pattern":"TODO","caseSensitive":true,"maxResults":50}' \
     http://localhost:8095/search/ripgrep
```
