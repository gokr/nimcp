## Notifications Demo - Real-time events and streaming
## Demonstrates context-aware tools that send events via transport

import ../src/nimcp
import json, strformat, times, os, taskpools, options

var taskpool = Taskpool.new()


proc createAlarmWithNotification(alarm: string, seconds: int, sessionId: string) {.gcsafe.} =
  # Background task that would send notifications in a real implementation
  sleep(seconds * 1000)
  
  # For demonstration, just print the alarm with session ID
  # In a real implementation, you would need a message queue or event system
  # to communicate between background tasks and the transport layer
  echo fmt"ALARM for session {sessionId}: {alarm}"

let server = mcpServer("notifications-demo", "1.0.0"):
  # Context-aware tool that can send notifications
  mcpTool:
    proc sendNotification(ctx: McpRequestContext, message: string = "Hello from MCP!", count: int = 3): string =
      ## Send a notification event to the connected client
      ## - message: Message to include in notification
      ## - count: Number of notifications to send
 
      for i in 1..count:
        let eventData = %*{
          "message": fmt"{message} (#{i}/{count})",
          "timestamp": $now(),
          "index": i,
          "total": count
        }
        
        # Send notification to client via ctx as logging message
        ctx.sendNotification("message", eventData)
        sleep(500)
      
      return fmt"Sent {count} notifications: '{message}'"
  
  mcpTool:
    proc progressTask(ctx: McpRequestContext, steps: int): string =
      ## Simulate a long-running task with progress updates (takes 5-40 seconds)
      ## For progress notifications, include progressToken in request _meta field
      ## - steps: Number of steps to process (1-10)
      if steps <= 0 or steps > 10:
        return "Error: Steps must be between 1 and 10"
      
      # Debug: Check if progressToken is available  
      let hasToken = ctx.progressToken != none(JsonNode)
      let tokenStr = if hasToken: $ctx.progressToken.get() else: "none"
      echo fmt"DEBUG: Progress token available: {hasToken}, value: {tokenStr}"
      
      for step in 1..steps:
        sleep(800)
        # Send progress notification using the dedicated sendProgress method
        ctx.sendProgress(step, steps, fmt"Processing step {step} of {steps}")
      
      return fmt"Task completed with {steps} steps"

  mcpTool:
    proc setAlarm(ctx: McpRequestContext, alarm: string, seconds: int): string =
      ## Set an alarm to go off in a specified number of seconds, a notification will be sent
      ## - seconds: Number of seconds before alarm is triggered
      ## - alarm: The message included in the notification that is sent when alarm is triggered

      # Extract session ID from context for background task
      taskpool.spawn createAlarmWithNotification(alarm, seconds, ctx.sessionId)
      
      return fmt"Alarm will trigger in {seconds} seconds"

  mcpTool:
    proc HenrySaysHi(): string =
      ## Talk to Henry and he will say hi      
      return "Hi! I am Henry"

when isMainModule:
  let args = commandLineParams()
  let transportType = if args.len > 0: args[0] else: "stdio"
  
  case transportType:
  of "sse":
    # SSE transport for server-to-client events (default)
    let transport = newSseTransport(8081, "127.0.0.1")
    transport.serve(server)
  of "websocket", "ws":
    # WebSocket supports bidirectional real-time communication
    let transport = newWebSocketTransport(8081, "127.0.0.1")
    transport.serve(server)
  of "http":
    # HTTP transport with streaming support
    let transport = newMummyTransport(8081, "127.0.0.1")
    transport.serve(server)
  of "stdio":
    # Stdio transport
    let transport = newStdioTransport()
    transport.serve(server)