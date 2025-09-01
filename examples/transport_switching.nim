## Multi-Transport Server Example
##
## This example demonstrates how to create a single MCP server that can work
## with multiple transport types (stdio, HTTP, WebSocket, SSE) without any
## code changes. The transport is selected via command-line argument.
##
## Usage:
##   # Stdio transport (default)
##   nim c -r examples/transport_switching.nim
##
##   # HTTP transport
##   nim c -r examples/transport_switching.nim http

import ../src/nimcp, ../src/nimcp/stdio_transport
import os, strutils

let server = mcpServer("multi-transport-server", "1.0.0"):
  
  mcpTool:
    proc fibonacci(n: int): string =
      ## Calculate the nth Fibonacci number
      ## - n: The position in the Fibonacci sequence (must be >= 0)
      if n < 0:
        return "Error: n must be non-negative"
      elif n <= 1:
        return $n
      
      var a = 0
      var b = 1
      for i in 2..n:
        let temp = a + b
        a = b
        b = temp
      return $b
  
  mcpTool:
    proc factorial(n: int): string =
      ## Calculate the factorial of a number
      ## - n: The number to calculate factorial for (must be >= 0)
      if n < 0:
        return "Error: n must be non-negative"
      elif n <= 1:
        return "1"
      
      var factorial = 1
      for i in 2..n:
        factorial *= i
      return $factorial

when isMainModule:
  # Parse command line arguments to determine transport
  let transportArg = if paramCount() > 0: paramStr(1).toLowerAscii() else: "stdio"
  
  # Start the server
  echo "Starting MCP server with transport: ", transportArg
  echo "Server: multi-transport-server v1.0.0"
  echo "Available tools: fibonacci, factorial"
  
  # For now, just use stdio transport (other transports can be added later)
  let transport = newStdioTransport()
  transport.serve(server)