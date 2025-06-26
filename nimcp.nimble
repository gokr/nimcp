# Package
version       = "0.3.0"
author        = "Göran Krampe"
description   = "Easy-to-use Model Context Protocol (MCP) server implementation for Nim"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.2.4"
requires "json_serialization"
requires "mummy"
requires "taskpools"

# Tasks
task docs, "Generate documentation":
  exec "nim doc --project --index:on --git.url:https://github.com/gokr/nimcp --git.commit:main --outdir:docs src/nimcp.nim"


task test, "Run all tests":
  exec "nim c -r tests/test_basic.nim"
  exec "nim c -r tests/test_simple_server.nim"
  exec "nim c -r tests/test_calculator_server.nim"
  exec "nim c -r tests/test_concurrent_stdio.nim"
  exec "nim c -r tests/test_http_auth.nim"
  exec "nim c -r tests/test_error_handling.nim"
  exec "nim c -r tests/test_protocol_compliance.nim"
  exec "nim c -r tests/test_edge_cases.nim"