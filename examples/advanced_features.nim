import ../src/nimcp, ../src/nimcp/stdio_transport
import strformat

let advancedServer = mcpServer("advanced-features", "1.0.0"):
  
  mcpTool:
    proc echoTool(message: string): string =
      ## Echo a message back to the client
      ## - message: The message to echo
      return "Echo: " & message
  
  mcpTool:
    proc longRunningTask(duration: int): string =
      ## Simulate a long-running task with progress notifications
      ## - duration: Duration in seconds
      if duration <= 0:
        return "Duration must be positive"
      
      return fmt"Task completed after {duration} seconds"

when isMainModule:
  echo "Starting advanced features MCP server..."
  echo "Server: ", advancedServer.serverInfo.name, " v", advancedServer.serverInfo.version
  echo "Available tools: echoTool, longRunningTask"
  echo "Use Ctrl+C to stop the server"
  
  let transport = newStdioTransport()
  transport.serve(advancedServer)