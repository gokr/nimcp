## Getting Started - Basic MCP server with echo and time tools
## Shows both manual API and macro API patterns

import ../src/nimcp,  ../src/nimcp/stdio_transport
import json, times, options


# Option 1: Manual API (explicit control)
let manualServer = newMcpServer("manual-example", "1.0.0")

proc echoHandler(args: JsonNode): McpToolResult =
  let text = args["text"].getStr()
  return McpToolResult(content: @[createTextContent("Echo: " & text)])

manualServer.registerTool(McpTool(
  name: "echo",
  description: some("Echo back the input text"),
  inputSchema: %*{
    "type": "object",
    "properties": {
      "text": {"type": "string", "description": "Text to echo back"}
    },
    "required": ["text"] 
  }
), echoHandler)

# Option 2: Macro API (automatic schema generation)
let macroServer = mcpServer("macro-example", "1.0.0"):
  mcpTool:
    proc echo(text: string): string =
      ## Echo back the input text
      ## - text: Text to echo back
      return "Echo: " & text
  
  mcpTool:
    proc currentTime(): string =
      ## Get the current date and time
      return "Current time: " & $now()

when isMainModule:
  # Use the macro server (preferred approach)
  let transport = newStdioTransport()
  transport.serve(macroServer)