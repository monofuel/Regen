# Fraggy 🗃️

![why wouldn't you want a miqo'te reading all your documents and indexing everything](static/ComfyUI_00126_.png)

📚 **A fast, lightweight document indexing tool that loads files, chunks them, and indexes with embeddings**

✨ **Features:**
- 🚀 Fast parallel processing with Nim
- 🔍 Semantic search using embeddings  
- 💾 No database required - uses flatty for binary serialization
- 📁 Works with git repos and local folders
- 🧠 Uses Ollama for local embeddings (`nomic-embed-text`)

## 🛠️ Usage

### Running Tests
```bash
nimble test
```

### Running Benchmarks
```bash
nimble benchmark
```

Benchmarks cover file discovery, SHA-256 hashing, fragment creation, embedding generation, and full repository indexing.

## 📖 Key Functions

### `newFraggyIndex(indexType, path, extensions)`
Creates a new index for a git repo or folder:
```nim
let index = newFraggyIndex(fraggy_git_repo, "/path/to/repo", @[".nim", ".md"])
```

### `findSimilarFragments(index, queryText, maxResults)`
Searches for similar content using cosine similarity:
```nim
let results = findSimilarFragments(index, "authentication code", 5)
```

### `generateEmbedding(text, model)`
Generates embeddings for text using Ollama:
```nim
let embedding = generateEmbedding("some text", "nomic-embed-text")
```

## 📋 TODO

- [ ] support query - document embeddings in addition to similarity search
- [ ] 🌐 OpenAPI server interface
- [ ] 🔌 MCP (Model Context Protocol) server support