import
  std/[strutils, unittest],
  fragment/markdown

suite "Markdown chunking guards":
  test "chunkMarkdown isolates long lines into single-line fragments":
    let content = "# Title\nshort\n" & repeat('x', 900) & "\nafter"
    let chunks = chunkMarkdown(content)

    var hasLongSingleLine = false
    for ch in chunks:
      if ch.startLine == 3 and ch.endLine == 3:
        hasLongSingleLine = true

    check hasLongSingleLine

  test "chunkMarkdown isolates blob-like certificate lines":
    let blob = "client-key-data: " & repeat('A', 600)
    let content = "# kube config\n" & blob & "\nother: value"
    let chunks = chunkMarkdown(content)

    var hasBlobSingleLine = false
    for ch in chunks:
      if ch.startLine == 2 and ch.endLine == 2:
        hasBlobSingleLine = true

    check hasBlobSingleLine
