# Package
version       = "0.2.0"
author        = "Göran Krampe"
description   = "Easy-to-use Model Context Protocol (MCP) server implementation for Nim"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.2.4"
requires "json_serialization"
requires "mummy"

# Tasks
task docs, "Generate documentation":
  exec "nim doc --project --index:on --git.url:https://github.com/gokr/nimcp --git.commit:main --outdir:docs src/nimcp.nim"