# Regen Directory Watch and Incremental Indexing

## Problem

Regen's current indexing model requires a full directory walk and diff on every startup or refresh. For large directories (e.g. 17k+ files on NFS), this creates two problems:

1. **Startup cost is O(n)** — even when nothing changed, `findProjectFiles` walks the entire tree and compares against the cached index. On NFS this can take 30+ seconds just for the walk, plus O(n^2) for the incremental diff (which uses `notin` on a `seq`).

2. **Re-indexing is sequential and blocking** — when files do need reindexing, `newRegenFile` computes embeddings one fragment at a time via synchronous HTTP calls. For a full rebuild of 17k files with 2 embeddings per chunk, this is 30k+ sequential API calls.

This makes Regen unusable as a startup dependency in latency-sensitive services (e.g. a Discord bot with a 120s watchdog timeout).

## Proposed: Directory Watch Mode

Add a `watchDir` mode where Regen monitors a directory for changes using OS filesystem events (inotify on Linux, FSEvents on macOS) and updates the index incrementally in real-time.

### Architecture

```
[FS events]  ->  [Event Queue]  ->  [Debounce/Batch]  ->  [Index Update]
                                         |
                                    coalesce rapid
                                    changes to same
                                    file into one update
```

### Behavior

- On startup: load existing index from disk. Do NOT walk the full directory.
- Register filesystem watcher on the indexed directory (recursive).
- On file create/modify: debounce (e.g. 500ms), then re-index only the changed file.
- On file delete: remove from index.
- On file rename: treat as delete + create.
- Periodically (e.g. every hour): do a full reconciliation walk to catch any missed events.

### Benefits

- **Near-zero startup cost** — loads cached index, starts watcher, done.
- **Incremental updates** — only changed files are re-embedded.
- **Background operation** — index stays warm without blocking the main application.

### Considerations

- NFS does not support inotify. For NFS-backed directories, fall back to periodic polling (e.g. walk every 5 minutes) rather than relying on filesystem events.
- The debounce window should be configurable.
- The watcher should run on a background thread and not block the caller.
- Index persistence should be crash-safe (write to temp file, then atomic rename).

## Relation to Parallel Indexing

This proposal is complementary to `concurrency_batching_plan.md`. Directory watch mode reduces _how many_ files need reindexing. Parallel/batched embedding (from the batching plan) speeds up _how fast_ those files get indexed. Both are needed:

- Watch mode + sequential embedding: good for small incremental changes (1-10 files)
- Watch mode + parallel embedding: needed for initial cold-start or large batch changes
- Without watch mode, parallel embedding alone still requires a full directory walk on startup

## Immediate Workaround for Racha

Until watch mode is implemented, Racha's `initDmHistory` should:

1. Load the cached index without walking the directory
2. Defer the full refresh to a background thread
3. Let the Discord bot start and respond to messages immediately
4. Update the index in the background, making search results gradually complete

This separates "index available" (instant, from cache) from "index current" (async, background refresh).
