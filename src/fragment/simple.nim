import std/[strutils]
import ../types

const
  SoftMaxLines = 120
  MinLines = 40

proc chunkSimple*(content: string): seq[RegenFragment] =
  ## Simple line-count-based chunker producing RegenFragments with line ranges only.
  ## Text is not stored here; embeddings will be created upstream using these ranges.
  result = @[]
  let lines = content.split('\n')
  if lines.len == 0:
    return

  var startLine = 1
  var currentCount = 0
  for i in 0 ..< lines.len:
    currentCount.inc
    let isBoundary = currentCount >= SoftMaxLines or (currentCount >= MinLines and lines[i].strip().len == 0)
    let isLast = i == lines.len - 1
    if isBoundary or isLast:
      let endLine = i + 1
      result.add(RegenFragment(
        startLine: startLine,
        endLine: endLine,
        embedding: @[],
        fragmentType: "document",
        model: "",
        chunkAlgorithm: "simple",
        private: false,
        contentScore: 0,
        hash: ""
      ))
      startLine = endLine + 1
      currentCount = 0


