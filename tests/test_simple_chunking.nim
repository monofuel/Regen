import
  std/[strutils, unittest],
  fragment/simple

suite "Simple chunking guards":
  test "chunkSimple isolates long lines into single-line fragments":
    let content = "alpha\n" & repeat('x', 900) & "\nomega"
    let chunks = chunkSimple(content)

    var hasLongSingleLine = false
    for ch in chunks:
      if ch.startLine == 2 and ch.endLine == 2:
        hasLongSingleLine = true
    check hasLongSingleLine

  test "chunkSimple isolates blob-like certificate lines":
    let blob = "client-key-data: " & repeat('A', 600)
    let content = "kube\n" & blob & "\ndone"
    let chunks = chunkSimple(content)

    var hasBlobSingleLine = false
    for ch in chunks:
      if ch.startLine == 2 and ch.endLine == 2:
        hasBlobSingleLine = true
    check hasBlobSingleLine
