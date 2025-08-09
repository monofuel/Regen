import std/[strutils]
import ../types

const
  NimSoftMaxLines = 120

proc leadingWhitespace(s: string): int =
  ## Count leading whitespace characters (spaces or tabs).
  for i in 0 ..< s.len:
    if not (s[i] in {' ', '\t'}):
      return i
  s.len

proc flushRange(result: var seq[RegenFragment], startLine: int, endLine: int) =
  ## Add a fragment for the provided 1-based inclusive range.
  if startLine <= 0 or endLine < startLine:
    return
  result.add(RegenFragment(
    startLine: startLine,
    endLine: endLine,
    embedding: @[],
    fragmentType: "nim_block",
    model: "",
    chunkAlgorithm: "nim",
    private: false,
    contentScore: 0,
    hash: ""
  ))

proc flushRangeSplitBySoftMax(result: var seq[RegenFragment], startLine: int, endLine: int) =
  ## Split a large range into multiple fragments capped by NimSoftMaxLines.
  if startLine <= 0 or endLine < startLine:
    return
  var s = startLine
  while s + NimSoftMaxLines - 1 < endLine:
    flushRange(result, s, s + NimSoftMaxLines - 1)
    s = s + NimSoftMaxLines
  flushRange(result, s, endLine)

proc isNimTopLevelStart(line: string): bool =
  ## Detects the start of a Nim top-level routine-like block.
  let stripped = line.strip()
  if stripped.len == 0:
    return false
  stripped.startsWith("proc ") or
  stripped.startsWith("method ") or
  stripped.startsWith("func ") or
  stripped.startsWith("iterator ") or
  stripped.startsWith("template ") or
  stripped.startsWith("macro ")

proc chunkNim*(content: string): seq[RegenFragment] =
  ## Nim-aware chunker that emits line ranges around Nim routines.
  ## - Splits at starts of proc/method/func/iterator/template/macro.
  ## - Uses indentation to find routine boundaries.
  ## - Splits long routines into ~NimSoftMaxLines windows.
  result = @[]
  let lines = content.split('\n')
  if lines.len == 0:
    return

  var preludeStart = 1
  var inBlock = false
  var blockIndent = 0
  var blockStart = 0

  for i, line in lines:
    let lineNum = i + 1
    let stripped = line.strip()

    if not inBlock:
      if isNimTopLevelStart(line):
        if preludeStart <= lineNum - 1:
          flushRangeSplitBySoftMax(result, preludeStart, lineNum - 1)
        inBlock = true
        blockIndent = line.leadingWhitespace
        blockStart = lineNum
        continue
    else:
      let indent = line.leadingWhitespace
      let isLast = i == lines.len - 1
      if (indent <= blockIndent and stripped.len != 0) or isLast:
        let blockEnd = if isLast: lineNum else: lineNum - 1
        flushRangeSplitBySoftMax(result, blockStart, blockEnd)
        inBlock = false
        blockIndent = 0
        blockStart = 0
        preludeStart = lineNum
        if isNimTopLevelStart(line):
          if preludeStart <= lineNum - 1:
            flushRangeSplitBySoftMax(result, preludeStart, lineNum - 1)
          inBlock = true
          blockIndent = line.leadingWhitespace
          blockStart = lineNum
          preludeStart = lineNum + 1
        continue

  if inBlock and blockStart > 0:
    flushRangeSplitBySoftMax(result, blockStart, lines.len)
    inBlock = false
    preludeStart = lines.len + 1

  if preludeStart <= lines.len:
    flushRangeSplitBySoftMax(result, preludeStart, lines.len)
