# Atomic Index Writes

## Bug

`writeIndexToFile` in `src/index.nim:19-27` writes directly to the target file:

```nim
writeFile(filepath, versionData & dataBytes)
```

If the process is killed during this write (OOM, watchdog, SIGKILL, power loss), the file is left truncated or partially written. On the next startup, `readIndexFromFile` fails to deserialize the corrupt file, throws an exception, and the caller falls back to a full rebuild from scratch.

This defeats the incremental checkpoint system. `rebuildHistoryIndex` and `updateHistoryIndexIncremental` flush every 50 files via `persistHistoryIndex`, but a single unlucky kill corrupts the file and discards all progress.

## Observed Impact

In Racha's production Discord bot:

1. DM history index rebuild starts (17k+ files, sequential embedding calls)
2. Incremental checkpoints save progress every 50 files
3. Watchdog kills the process after 120s (no Discord heartbeat during blocking init)
4. Next startup: index file is corrupt → exception → full rebuild from scratch
5. Crash loop: never converges because full rebuild always exceeds 120s

## Fix

Use atomic write: write to a temporary file, then rename. Rename is atomic on all POSIX filesystems (including NFS with close-to-open consistency).

In `writeIndexToFile`:

```nim
proc writeIndexToFile*(index: RegenIndex, filepath: string) =
  let data = toFlatty(index)
  var versionBytes: array[4, byte]
  var versionInt = RegenFileIndexVersion
  littleEndian32(versionBytes.addr, versionInt.addr)
  let versionData = @versionBytes
  let dataBytes = cast[seq[byte]](data)
  let tmpPath = filepath & ".tmp"
  writeFile(tmpPath, versionData & dataBytes)
  moveFile(tmpPath, filepath)
```

If the process dies during `writeFile`, only the `.tmp` file is corrupt — the previous valid index at `filepath` is untouched. If the process dies after `writeFile` but before `moveFile`, the `.tmp` is complete and the old index is still valid. Either way, the next startup reads a valid index.

## Scope

This affects every caller of `writeIndexToFile`, including:

- `persistHistoryIndex` in Racha's `dm_history.nim`
- `newRegenFolder` and `newRegenGitRepo` in Regen's `index.nim`
- Any future index persistence

The fix is a one-line change in a single proc.
