## Streaming Example - Advanced HTTP streaming with progress updates
## Demonstrates context-aware tools for real-time streaming applications

import ../src/nimcp
import json, strformat, times, os

let server = mcpServer("streaming-example", "1.0.0"):
  mcpTool:
    proc fibonacci(n: int): string =
      ## Calculate Fibonacci sequence up to n terms
      ## - n: Number of terms to calculate (1-20)
      if n <= 0 or n > 20:
        return "Error: n must be between 1 and 20"
      
      var a = 0
      var b = 1
      var sequence = @[a]
      
      for i in 1..<n:
        sequence.add(b)
        let temp = a + b
        a = b
        b = temp
      
      return fmt"Fibonacci({n}): {sequence}"
  
  mcpTool:
    proc longTask(ctx: McpRequestContext, duration: int = 5): string =
      ## Simulate a long-running task with progress (context-aware)
      ## - duration: Task duration in seconds (1-10)

      if duration <= 0 or duration > 10:
        return "Error: Duration must be between 1 and 10 seconds"
      
      # Simulate work with status updates using proper MCP progress notifications
      for i in 1..duration:
        sleep(1000)
        # Send progress notification using proper MCP format
        let progressData = %*{
          "step": i,
          "total": duration,
          "message": fmt"Completed step {i} of {duration}"
        }
        ctx.sendNotification("progress", progressData)
      
      return fmt"Long task completed in {duration} seconds"

when isMainModule:
  # HTTP transport with streaming capabilities - supports both JSON and SSE responses
  # based on client Accept headers
  let transport = newMummyTransport(8080, "127.0.0.1")
  transport.serve(server)