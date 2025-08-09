import
  std/[strutils, os],
  ./types,
  ./fragment/simple,
  ./fragment/markdown

const
  MarkdownExts = @[".md", ".markdown"]

proc chunkFile*(filePath: string, content: string): seq[RegenFragment] =
  ## Produce line-range fragments for a file. For markdown:
  ## - combine simple and markdown-specific chunkers.
  ## For other types (e.g., .nim, .txt) use simple chunking only.
  let (_, _, ext) = splitFile(filePath)
  let lowerExt = ext.toLower

  if lowerExt in MarkdownExts:
    # Combine algorithms; keep both outputs.
    result = @[]
    result.add(chunkSimple(content))
    result.add(chunkMarkdown(content))
    # Note: we intentionally keep overlaps; downstream can de-duplicate if desired.
  else:
    result = chunkSimple(content)


