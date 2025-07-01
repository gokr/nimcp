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

import strformat

# Tasks
task docs, "Generate documentation":
  exec "nim doc --project --index:on --git.url:https://github.com/gokr/nimcp --git.commit:main --outdir:docs src/nimcp.nim"

task test, "Run all tests":
  exec "nimble install -d"
  exec "testament --colors:off --verbose pattern 'tests/test_*.nim'"

task coverage, "Run tests with coverage analysis":
  echo "🧪 Running tests with coverage analysis..."
  # Compile all tests with profiling and coverage flags
  exec "nimble install -d"
  
  # Run tests with line tracing for basic coverage information
  withDir "tests":
    for test in listFiles("."):
      if test.endsWith(".nim") and test.startsWith("test_"):
        echo fmt"📊 Testing {test} with coverage..."
        exec fmt"nim c --lineTrace:on --stackTrace:on -r {test}"
  
  echo "✅ Coverage analysis complete"
  echo "📈 For detailed coverage, check console output during test execution"

task testcov, "Run specific test with detailed coverage":
  if paramCount() == 0:
    echo "Usage: nimble testcov <test_file>"
    echo "Example: nimble testcov test_polymorphic_transport"
  else:
    let testFile = paramStr(1)
    echo fmt"🔍 Running detailed coverage for {testFile}..."
    withDir "tests":
      exec fmt"nim c --lineTrace:on --stackTrace:on --debugger:native --profiler:on -r {testFile}.nim"

