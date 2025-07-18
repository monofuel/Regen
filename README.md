# Fraggy


- loading files, chunking and indexing them with embeddings

- strictly handles indexing. does not handle storing any data.
- only handles operating on git repos.


## rough notes

New Project Structure Overview

Rebuild as a Nim-based tool without a database. Use flatty for binary serialization to disk. Assume git repos are locally accessible for retrieving original text via line indexes. Keep embeddings in memory for similarity search (e.g., via cosine distance). Use a consistent embedding model (e.g., fixed dimension like 1536 or 4096).
Key Components

    Data Structures (Define in Nim):
    nim

    import flatty  # For serialization

    type
      Document = object
        hostname: string
        path: string
        filename: string
        hash: string  # e.g., SHA of file content
        creationTime: float  # Unix timestamp
        lastModified: float  # Unix timestamp
        # Omit score/fact_score if not implemented yet

      Chunk = object
        startLine: int
        endLine: int
        embedding: seq[float]  # Fixed-size vector (e.g., 1536 elements)
        fragmentType: string  # e.g., "document" or "summary"
        model: string  # Embedding model name
        private: bool
        contentScore: int  # 0 if not calculated
        hash: string  # Hash of chunk content for versioning

      IndexEntry = object
        doc: Document
        chunks: seq[Chunk]

    # In-memory store: seq[IndexEntry] or a hash table keyed by doc hash/path
        Store one .flat file per document (or group by repo). Serialize IndexEntry to disk with flatty: writeToFile("index/" & doc.hash & ".flat", toFlatty(indexEntry)).
        Load all .flat files into memory at startup for search.
    Chunking Logic:
        Read file lines into a seq[string].
        Chunk by fixed size (e.g., 10-20 lines) or semantic (e.g., by sections/paragraphs).
        For each chunk, compute embedding (via external LLM API or local model).
        Store only {startLine, endLine, embedding} in Chunk.
        To retrieve text later: Re-read file lines, slice lines[startLine..endLine].
    Indexing Process:
        Traverse git repo files.
        For each file: Compute hash, metadata; read lines; chunk; embed chunks.
        Create IndexEntry, serialize to disk with flatty.
        Skip re-indexing if hash matches existing serialized file.
    Search Process:
        Load all serialized indexes into memory (assume <1GB total).
        Embed query.
        Compute cosine similarity across all chunks' embeddings (implement manually or use a Nim lib like neo for vectors).
        Sort by distance, filter by thresholds/min_scores.
        For top results: Load original file, extract text by line range, return with metadata.
    Additional Features:
        Updates: On file change, recompute hash, re-chunk/embed, overwrite serialized file.
        Memory Optimization: If embeddings grow large, use memory-mapped files instead of full load.
        No Text Storage: Ensures lightweight; relies on git for source truth.

This avoids DB overhead while keeping operations in-memory for speed. Test with small repos first.