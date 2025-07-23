import std/[strformat, strutils, times, terminal, locks]

var logLock: Lock
initLock(logLock)

type
  LogLevel = enum
    Debug = "DEBUG"
    Info = "INFO"
    Warn = "WARN"
    Error = "ERR"

proc log(level: LogLevel, str: string) =
  # echo &"[{level}][{cpuTime()}] " & str

  # if level == Debug:
  #   return

  var logLevelColor = case level:
    of Debug:
      fgBlue
    of Info:
      fgGreen
    of Warn:
      fgYellow
    of Error:
      fgRed

  withLock logLock:
    let time = cpuTime()
    let cpuTimeStr = formatFloat(time, ffDecimal, 10)
    stdout.styledWrite(logLevelColor, &"[{level}]\t")
    stdout.styledWrite(fgCyan, &"[{cpuTimeStr}]\t")
    stdout.styledWriteLine(fgWhite, &": {str}")


proc debug*(str: string) =
  log(Debug, str)

proc info*(str: string) =
  log(Info, str)

proc warn*(str: string) =
  log(Warn, str)

proc error*(str: string) =
  log(Error, str)
