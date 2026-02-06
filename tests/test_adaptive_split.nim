import
  std/unittest,
  regen

suite "Adaptive chunk splitting":
  test "splitChunkForRetry splits multiline chunks by line midpoint":
    let content = "line1\nline2\nline3\nline4"
    let chunks = splitChunkForRetry(content, 10, 13)

    check chunks.len == 2
    check chunks[0].startLine == 10
    check chunks[0].endLine == 11
    check chunks[1].startLine == 12
    check chunks[1].endLine == 13
    check chunks[0].content == "line1\nline2"
    check chunks[1].content == "line3\nline4"

  test "splitChunkForRetry splits single-line chunks by character midpoint":
    let content = "abcdefghijklmnopqrstuvwxyz"
    let chunks = splitChunkForRetry(content, 42, 42)

    check chunks.len == 2
    check chunks[0].startLine == 42
    check chunks[0].endLine == 42
    check chunks[1].startLine == 42
    check chunks[1].endLine == 42
    check chunks[0].content.len + chunks[1].content.len == content.len
    check chunks[0].content.len > 0
    check chunks[1].content.len > 0

  test "splitChunkForRetry rejects unsplittable single-char content":
    expect ValueError:
      discard splitChunkForRetry("x", 1, 1)
