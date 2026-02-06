# Regen Concurrency and Backend Batching Plan

## Goal

Improve indexing throughput by parallelizing local indexing work and batching embedding API requests so Regen can take advantage of backend batching (for example, llama-server/OpenAI-compatible embedding endpoints).

## Current State Summary

- File indexing is mostly serial in `src/index.nim` (`newRegenFolder`, `newRegenGitRepo`).
- Embeddings are generated per fragment via `generateEmbedding(...)` with single-input requests.
- `MaxInFlight` exists in `src/search.nim`, but this is client request concurrency, not full indexing pipeline concurrency or explicit multi-input batching.
- Result: good simplicity, but underutilized backend throughput when backend supports large batched requests.

## Non-Goals

- Do not change search ranking logic.
- Do not change index file format immediately unless required.
- Do not make indexing nondeterministic in output ordering.

## Proposed Architecture

Use a 3-stage pipeline:

1. **Discover Stage**
- Walk files and decide inclusion (`findProjectFiles`).
- Produce stable ordered file list.

2. **Chunk Stage (parallel workers)**
- Read file content.
- Produce fragment ranges (`chunkFile`).
- Build embedding work items containing:
  - file path
  - fragment range metadata
  - fragment text
  - embedding task (`RetrievalDocument`/`SemanticSimilarity`)

3. **Embedding Stage (batching + bounded concurrency)**
- Accumulate work items into batches by:
  - model
  - task
  - optional max chars/tokens per batch
- Send batched embedding requests (`input: [text1, text2, ...]`) where supported.
- Map embedding vectors back to work items.
- Assemble `RegenFile` with fragment metadata + vectors.

## Data Structures

Add internal (non-exported) types in `src/index.nim`:

- `EmbeddingWorkItem`
  - `filePath`, `filename`
  - `startLine`, `endLine`
  - `chunkAlgorithm`, `fragmentType`
  - `task`
  - `text`
  - `sequenceId` (stable ordering key)

- `EmbeddingBatch`
  - `model`, `task`
  - `items: seq[EmbeddingWorkItem]`

- `EmbeddedItemResult`
  - original metadata + `embedding: seq[float32]`

Keep `sequenceId` monotonic from initial file order to guarantee deterministic output.

## Config Additions

Extend `RegenConfig` (`src/types.nim`, `src/configs.nim`) with conservative defaults:

- `indexWorkers` (default: CPU count or 4)
- `embedBatchSize` (default: 16)
- `embedMaxCharsPerItem` (default tuned to model; e.g., 2048 for gemma embeddings)
- `embedMaxInFlightBatches` (default: 2-4)
- `enableBatchEmbeddings` (default: true)
- `enableParallelChunking` (default: true)

Optional:
- `embedBatchTargetChars` (soft budget to avoid giant batches)

## Embedding API Integration

Add a batched embedding path in `src/search.nim`:

- New proc: `generateEmbeddingsBatch(texts: seq[string], model: string, task: EmbeddingTask): seq[seq[float32]]`
- Behavior:
  - For embeddinggemma-like models, use task-aware batch endpoint if available.
  - For providers that do not support task+batch simultaneously, fallback:
    - per-item calls with bounded concurrency.

Fallback must preserve correctness, only reducing performance.

## Incremental Indexing Behavior

For `updateRegenIndex`:

- Continue detecting changed/new/deleted files as today.
- For changed/new files:
  - run chunk+embed pipeline only for affected files.
- For unchanged files:
  - reuse existing fragments/embeddings unchanged.

This keeps updates cheap and avoids full-reindex cost.

## Error Handling Strategy

Introduce robust item-level error handling:

- If one batch fails:
  - retry with smaller sub-batches (binary split strategy).
- If one item still fails:
  - log file + fragment metadata.
  - skip item and continue indexing others (or optionally fail-fast via config).

Add config flag:
- `indexFailFast` (default: false for resilience).

## Determinism Requirements

- Sort file paths before processing.
- Preserve output fragment order by `(filePath, startLine, endLine, task, sequenceId)`.
- Ensure serialized `.flat` content remains stable across runs given same inputs.

This is important for tests and debugging.

## Performance Instrumentation

Add lightweight timings/counters:

- files indexed
- fragments generated
- embedding requests sent
- average batch size
- fallback count (batch -> single)
- per-stage durations:
  - discover
  - chunk
  - embed
  - assemble/write

Emit summary at end of `indexAll`.

## Rollout Plan

### Phase 1: Internal batching API
- Add `generateEmbeddingsBatch` with fallback.
- Keep existing single-item paths unchanged.

### Phase 2: Parallel chunking + batched embedding for full index
- Implement pipeline for `newRegenFolder` and `newRegenGitRepo`.
- Keep old path behind a feature flag for rollback.

### Phase 3: Incremental indexing integration
- Update `updateRegenIndex` to use new pipeline for changed files.

### Phase 4: Tuning and defaults
- Tune default batch sizes and worker counts for Andrewlytics/gemma embeddings.

## Testing Plan

1. **Unit tests**
- Batch splitting logic
- Stable ordering logic
- Retry/sub-batch fallback behavior

2. **Golden tests**
- Same inputs produce deterministic `.flat` outputs (or deterministic ordering in extracted summaries).

3. **Integration tests**
- Index a medium fixture repo with batching on/off and compare semantic search parity.
- Simulate backend failures and verify partial progress behavior.

4. **Benchmark tests**
- Compare serial vs concurrent+batched indexing:
  - total indexing time
  - embedding requests count
  - average batch size

## Risks and Mitigations

- **Backend rate limits / overload**
  - bounded `embedMaxInFlightBatches`
  - adaptive retry backoff

- **Memory pressure from queued fragments**
  - bounded work queue
  - stream batches instead of collecting all fragments in RAM

- **Provider incompatibilities**
  - provider capability checks
  - graceful fallback to non-batched requests

## Suggested First Implementation Defaults

- `indexWorkers = 4`
- `embedBatchSize = 16`
- `embedMaxInFlightBatches = 2`
- `embedMaxCharsPerItem = 1800` (safe headroom under 2048-char model limits)
- `enableBatchEmbeddings = true`
- `enableParallelChunking = true`
- `indexFailFast = false`

These values are intentionally conservative and should be tuned with benchmark data.
