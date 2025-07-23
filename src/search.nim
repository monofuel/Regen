## Search functionality for Fraggy - ripgrep and embedding search

import
  std/[strutils, os, osproc, json, algorithm, math],
  openai_leap,
  ./types

const
  SimilarityEmbeddingModel* = "nomic-embed-text"
  MaxInFlight* = 10

# Solution-nine server
# radeon pro w7500
var localOllamaApi* = newOpenAiApi(
  baseUrl = "http://10.11.2.16:11434/v1", 
  apiKey = "ollama",
  maxInFlight = MaxInFlight
)

proc generateEmbedding*(text: string, model: string = SimilarityEmbeddingModel): seq[float32] =
  ## Generate an embedding for the given text using ollama.
  let embedding = localOllamaApi.generateEmbeddings(
    model = model,
    input = text
  )
  result = embedding.data[0].embedding

proc cosineSimilarity*(a, b: seq[float32]): float32 =
  ## Calculate cosine similarity between two embedding vectors.
  if a.len != b.len:
    raise newException(ValueError, "Vectors must have the same length")
  
  var dotProduct = 0.0'f32
  var normA = 0.0'f32
  var normB = 0.0'f32
  
  for i in 0..<a.len:
    dotProduct += a[i] * b[i]
    normA += a[i] * a[i]
    normB += b[i] * b[i]
  
  let magnitude = sqrt(normA) * sqrt(normB)
  if magnitude == 0.0'f32:
    return 0.0'f32
  
  result = dotProduct / magnitude

proc findSimilarFragments*(index: FraggyIndex, queryText: string, maxResults: int = 10, model: string = SimilarityEmbeddingModel): seq[SimilarityResult] =
  ## Find the most similar fragments to the query text.
  let queryEmbedding = generateEmbedding(queryText, model)
  var results: seq[SimilarityResult] = @[]
  
  # Collect all fragments with their similarity scores
  case index.kind
  of fraggy_git_repo:
    for file in index.repo.files:
      for fragment in file.fragments:
        if fragment.model == model:
          let similarity = cosineSimilarity(queryEmbedding, fragment.embedding)
          results.add(SimilarityResult(
            fragment: fragment,
            file: file,
            similarity: similarity
          ))
  of fraggy_folder:
    for file in index.folder.files:
      for fragment in file.fragments:
        if fragment.model == model:
          let similarity = cosineSimilarity(queryEmbedding, fragment.embedding)
          results.add(SimilarityResult(
            fragment: fragment,
            file: file,
            similarity: similarity
          ))
  
  # Sort by similarity (highest first) and return top results
  results.sort(proc(a, b: SimilarityResult): int =
    if a.similarity > b.similarity: -1
    elif a.similarity < b.similarity: 1
    else: 0
  )
  
  if results.len > maxResults:
    result = results[0..<maxResults]
  else:
    result = results

proc ripgrepSearch*(index: FraggyIndex, pattern: string, caseSensitive: bool = true, maxResults: int = 100): seq[RipgrepResult] =
  ## Search through all files in the index using actual ripgrep (rg) command.
  ## Returns matching lines with file info and line numbers.
  var results: seq[RipgrepResult] = @[]
  
  # Get the search directory based on index type
  let searchPath = case index.kind
    of fraggy_git_repo:
      # Find the common root directory of all files (should be the repo root)
      if index.repo.files.len > 0:
        let firstPath = index.repo.files[0].path
        var commonRoot = firstPath.parentDir()
        # Keep going up until we find a directory that contains .git or is the root
        while not dirExists(commonRoot / ".git") and commonRoot != "/" and commonRoot.len > 1:
          commonRoot = commonRoot.parentDir()
        commonRoot
      else: 
        "."
    of fraggy_folder:
      index.folder.path
  
  # Build ripgrep command (don't limit per file, we'll limit total results)
  var cmd = "rg --json --line-number --column"
  if not caseSensitive:
    cmd.add(" --ignore-case")
  
  # Add the pattern and search path
  cmd.add(" " & pattern.quoteShell() & " " & searchPath.quoteShell())
  
  try:
    let (output, exitCode) = execCmdEx(cmd)
    
    # If rg returns non-zero (no matches or error), return empty results
    if exitCode != 0:
      return @[]
    
    # Parse JSON output from ripgrep
    for line in output.strip().split('\n'):
      if line.strip().len == 0:
        continue
        
      # Stop if we've reached max results
      if results.len >= maxResults:
        break
        
      try:
        let jsonData = parseJson(line)
        
        # Only process "match" type entries
        if jsonData.hasKey("type") and jsonData["type"].getStr() == "match":
          let data = jsonData["data"]
          let filePath = data["path"]["text"].getStr()
          let lineNum = data["line_number"].getInt()
          let lineText = data["lines"]["text"].getStr().strip()  # Strip newlines
          let submatches = data["submatches"]
          
          # Find the corresponding FraggyFile
          var fraggyFile: FraggyFile
          var fileFound = false
          
          case index.kind
          of fraggy_git_repo:
            for file in index.repo.files:
              if file.path == filePath or file.path.endsWith(filePath):
                fraggyFile = file
                fileFound = true
                break
          of fraggy_folder:
            for file in index.folder.files:
              if file.path == filePath or file.path.endsWith(filePath):
                fraggyFile = file
                fileFound = true
                break
          
          # If we found the file in our index, create a result for each submatch
          if fileFound:
            for submatch in submatches:
              if results.len >= maxResults:
                break
              results.add(RipgrepResult(
                file: fraggyFile,
                lineNumber: lineNum,
                lineContent: lineText,
                matchStart: submatch["start"].getInt(),
                matchEnd: submatch["end"].getInt() - 1  # ripgrep uses exclusive end
              ))
            
      except JsonParsingError, KeyError:
        # Skip malformed JSON lines
        continue
        
  except OSError:
    # ripgrep command failed, return empty results
    return @[]
  
  result = results

proc ripgrepSearchInFile*(filePath: string, pattern: string, caseSensitive: bool = true): seq[tuple[lineNumber: int, lineContent: string, matchStart: int, matchEnd: int]] =
  ## Search for pattern in a single file using actual ripgrep.
  var results: seq[tuple[lineNumber: int, lineContent: string, matchStart: int, matchEnd: int]] = @[]
  
  if not fileExists(filePath):
    return @[]
  
  # Build ripgrep command for single file
  var cmd = "rg --json --line-number --column"
  if not caseSensitive:
    cmd.add(" --ignore-case")
  
  cmd.add(" " & pattern.quoteShell() & " " & filePath.quoteShell())
  
  try:
    let (output, exitCode) = execCmdEx(cmd)
    
    # If rg returns non-zero (no matches or error), return empty results
    if exitCode != 0:
      return @[]
    
    # Parse JSON output from ripgrep
    for line in output.strip().split('\n'):
      if line.strip().len == 0:
        continue
        
      try:
        let jsonData = parseJson(line)
        
        # Only process "match" type entries
        if jsonData.hasKey("type") and jsonData["type"].getStr() == "match":
          let data = jsonData["data"]
          let lineNum = data["line_number"].getInt()
          let lineText = data["lines"]["text"].getStr().strip()  # Strip newlines
          let submatches = data["submatches"]
          
          # Add a result for each submatch
          for submatch in submatches:
            results.add((
              lineNumber: lineNum,
              lineContent: lineText,
              matchStart: submatch["start"].getInt(),
              matchEnd: submatch["end"].getInt() - 1  # ripgrep uses exclusive end
            ))
            
      except JsonParsingError, KeyError:
        # Skip malformed JSON lines
        continue
        
  except OSError:
    # ripgrep command failed
    return @[]
  
  result = results 