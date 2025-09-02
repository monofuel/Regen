version     = "0.1.1"
author      = "monofuel"
description = "AI File Indexing and Search"
license     = "MIT"

srcDir = "src"

task benchmark, "Run performance benchmarks":
  exec "nim c -r tests/bench_regen.nim"

requires "nim >= 2.0.0"
requires "flatty >= 0.3.4"
requires "openai_leap >= 7.0.0"
requires "crunchy >= 0.1.11"
requires "benchy >= 0.0.1"
requires "jsony >= 1.1.5"
requires "mummy >= 0.4.7"

requires "https://github.com/monofuel/MCPort >= 1.0.0"
