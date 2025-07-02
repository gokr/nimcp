## Polymorphic Transport Demo - Server-agnostic architecture
## Demonstrates how the same server works with any transport without modification

import ../src/nimcp
import json, strformat, os
import ../src/nimcp/stdio_transport

let server = mcpServer("polymorphic-demo", "1.0.0"):
  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers (works with any transport)
      ## - a: First number
      ## - b: Second number  
      return fmt"Result: {a + b}"
  
  mcpTool:
    proc fibonacci(n: int): string =
      ## Calculate Fibonacci number (demonstrates algorithm)
      ## - n: Position in sequence (1-30)
      if n <= 0 or n > 30:
        return "Error: n must be between 1 and 30"
      
      var a = 0
      var b = 1
      for i in 1..<n:
        let temp = a + b
        a = b
        b = temp
      
      return fmt"Fibonacci({n}) = {b}"

when isMainModule:
  let args = commandLineParams()
  let transportType = if args.len > 0: args[0] else: "stdio"
  
  # The SAME server works with ANY transport
  case transportType:
  of "http":
    # HTTP transport at http://127.0.0.1:8080
    let transport = newMummyTransport(8080, "127.0.0.1")
    transport.serve(server)
  of "websocket", "ws":
    # WebSocket transport at ws://127.0.0.1:8080/
    let transport = newWebSocketTransport(8080, "127.0.0.1")
    transport.serve(server)
  of "sse":
    # SSE transport at http://127.0.0.1:8080/sse
    let transport = newSseTransport(8080, "127.0.0.1")
    transport.serve(server)
  else:
    # Stdio transport (default) - communicates via stdin/stdout
    let transport = newStdioTransport()
    transport.serve(server)