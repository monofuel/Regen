## Configuration management for Fraggy

import
  std/[strutils, strformat, os],
  jsony,
  ./types, ./search

const
  ConfigVersion* = "0.1.0"

proc getConfigPath*(): string =
  ## Get the path to the fraggy config file.
  let configDir = getHomeDir() / ".fraggy"
  if not dirExists(configDir):
    createDir(configDir)
  result = configDir / "config.json"

proc loadConfig*(): FraggyConfig =
  ## Load configuration from ~/.fraggy/config.json.
  let configPath = getConfigPath()
  
  if not fileExists(configPath):
    # Return default config if file doesn't exist
    result = FraggyConfig(
      version: ConfigVersion,
      folders: @[],
      gitRepos: @[],
      extensions: @[".nim", ".md", ".txt", ".py", ".js", ".ts", ".rs", ".go"],
      embeddingModel: SimilarityEmbeddingModel
    )
    return
  
  try:
    let configData = readFile(configPath)
    result = fromJson(configData, FraggyConfig)
  except:
    echo &"Error loading config from {configPath}: {getCurrentExceptionMsg()}"
    # Return default config on error
    result = FraggyConfig(
      version: ConfigVersion,
      folders: @[],
      gitRepos: @[],
      extensions: @[".nim", ".md", ".txt", ".py", ".js", ".ts", ".rs", ".go"],
      embeddingModel: SimilarityEmbeddingModel
    )

proc saveConfig*(config: FraggyConfig) =
  ## Save configuration to ~/.fraggy/config.json.
  let configPath = getConfigPath()
  try:
    let configData = toJson(config)
    writeFile(configPath, configData)
    echo &"Config saved to {configPath}"
  except:
    echo &"Error saving config to {configPath}: {getCurrentExceptionMsg()}"

proc addFolderToConfig*(folderPath: string) =
  ## Add a folder path to the config.
  var config = loadConfig()
  let absPath = expandFilename(folderPath)
  
  if absPath notin config.folders:
    config.folders.add(absPath)
    saveConfig(config)
    echo &"Added folder to config: {absPath}"
  else:
    echo &"Folder already in config: {absPath}"

proc addGitRepoToConfig*(repoPath: string) =
  ## Add a git repository path to the config.
  var config = loadConfig()
  let absPath = expandFilename(repoPath)
  
  if not dirExists(absPath / ".git"):
    echo &"Error: {absPath} is not a git repository"
    return
  
  if absPath notin config.gitRepos:
    config.gitRepos.add(absPath)
    saveConfig(config)
    echo &"Added git repo to config: {absPath}"
  else:
    echo &"Git repo already in config: {absPath}"

proc showConfig*() =
  ## Display the current configuration.
  let config = loadConfig()
  echo "Fraggy Configuration:"
  echo &"  Version: {config.version}"
  echo &"  Embedding Model: {config.embeddingModel}"
  echo &"  Extensions: {config.extensions.join(\", \")}"
  echo &"  Folders ({config.folders.len}):"
  for folder in config.folders:
    echo &"    - {folder}"
  echo &"  Git Repos ({config.gitRepos.len}):"
  for repo in config.gitRepos:
    echo &"    - {repo}" 