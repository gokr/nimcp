# Package
version       = "0.8.0"
author        = "Göran Krampe"
description   = "Easy-to-use Model Context Protocol (MCP) server implementation for Nim"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.2.4"
requires "https://github.com/gokr/mummy"
requires "taskpools"

# Tasks
task docs, "Generate documentation":
  exec "nim doc --project --index:on --git.url:https://github.com/gokr/nimcp --git.commit:main --outdir:docs src/nimcp.nim"

