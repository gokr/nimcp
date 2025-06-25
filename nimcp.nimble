# Package
version       = "0.1.0"
author        = "Göran Krampe"
description   = "Easy-to-use Model Context Protocol (MCP) server implementation for Nim"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"
requires "json_serialization"
requires "mummy"

# Tasks
task test, "Run tests":
  exec "nim c -r tests/test_basic.nim"
  exec "nim c -r tests/test_simple_server.nim"
  exec "nim c -r tests/test_calculator_server.nim"
  exec "nim c -r tests/test_concurrent_stdio.nim"
  exec "nim c -r tests/test_http_auth.nim"

task docs, "Generate documentation":
  exec "nim doc --project --index:on --git.url:https://github.com/gokr/nimcp --git.commit:main --outdir:docs src/nimcp.nim"