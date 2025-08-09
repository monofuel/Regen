import
  std/[strutils, os],
  ./types,
  ./fragment/simple,
  ./fragment/markdown,
  ./fragment/nimlang

const
  MarkdownExts = @[".md", ".markdown"]
  NimExts = @[".nim", ".nims"]

proc chunkFile*(filePath: string, content: string): seq[RegenFragment] =
  ## Produce line-range fragments for a file. based on extension.
  let (_, _, ext) = splitFile(filePath)
  let lowerExt = ext.toLower

  if lowerExt in MarkdownExts:
    result = @[]
    result.add(chunkSimple(content))
    result.add(chunkMarkdown(content))
  elif lowerExt in NimExts:
    result = chunkNim(content)
  else:
    result = chunkSimple(content)


