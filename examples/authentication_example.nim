## Authentication Example - Bearer token auth across multiple transports
## Demonstrates authentication patterns with HTTP, WebSocket, and SSE transports

import ../src/nimcp, ../src/nimcp/auth
import json, strformat

# Example token validator - in production, validate against your auth system
proc validateToken(token: string): bool =
  case token:
  of "valid-token-123", "admin-token-456", "user-token-789":
    return true
  else:
    return false

let server = mcpServer("auth-example", "1.0.0"):
  mcpTool:
    proc secureAdd(a: float, b: float): string =
      ## Add two numbers (requires authentication)
      ## - a: First number
      ## - b: Second number
      return fmt"Secure result: {a + b}"
  
  mcpTool:
    proc getSecrets(): string =
      ## Access privileged information (requires authentication)
      return "Secret data: The answer is 42"

when isMainModule:
  import os
  let args = commandLineParams()
  let transportType = if args.len > 0: args[0] else: "http"
  
  # Create authentication configuration
  let authConfig = newAuthConfig(validateToken, requireHttps = false)
  
  case transportType:
  of "websocket", "ws":
    # WebSocket with authentication
    let transport = newWebSocketTransport(8080, "127.0.0.1", authConfig)
    transport.serve(server)
  of "sse":
    # SSE with authentication  
    let transport = newSseTransport(8080, "127.0.0.1", authConfig)
    transport.serve(server)
  else:
    # HTTP with authentication (default)
    let transport = newMummyTransport(8080, "127.0.0.1", authConfig)
    transport.serve(server)