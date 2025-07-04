## Notifications Demo - Real-time events and streaming
## Demonstrates context-aware tools that send events via transport

import ../src/nimcp
import json, strformat, times, os

let server = mcpServer("notifications-demo", "1.0.0"):
  # Context-aware tool that can send notifications
  mcpTool:
    proc sendNotification(ctx: McpRequestContext, message: string = "Hello from MCP!", count: int = 3): string =
      ## Send a notification event to connected clients
      ## - message: Message to broadcast
      ## - count: Number of notifications to send
 
      for i in 1..count:
        let eventData = %*{
          "message": fmt"{message} (#{i}/{count})",
          "timestamp": $now(),
          "index": i,
          "total": count
        }
        
        # Send notification to client via ctx
        ctx.sendEvent("notification", eventData)
        sleep(500)
      
      return fmt"Sent {count} notifications: '{message}'"
  
  mcpTool:
    proc progressTask(steps: int): string =
      ## Simulate a long-running task with progress updates
      ## - steps: Number of steps to process (1-10)
      if steps <= 0 or steps > 10:
        return "Error: Steps must be between 1 and 10"
      
      for step in 1..steps:
        sleep(800)
        # Progress event would be sent here in real implementation
        # ctx.sendEvent("progress", %*{"step": step, "total": steps})
      
      return fmt"Task completed with {steps} steps"

when isMainModule:
  let args = commandLineParams()
  let transportType = if args.len > 0: args[0] else: "sse"
  
  case transportType:
  of "websocket", "ws":
    # WebSocket supports bidirectional real-time communication
    let transport = newWebSocketTransport(8080, "127.0.0.1")
    transport.serve(server)
  of "http":
    # HTTP transport with streaming support
    let transport = newMummyTransport(8080, "127.0.0.1")
    transport.serve(server)
  else:
    # SSE transport for server-to-client events (default)
    let transport = newSseTransport(8080, "127.0.0.1")
    transport.serve(server)