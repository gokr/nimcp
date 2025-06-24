## Simple MCP Server Example
## Shows basic usage of nimcp

import ../src/nimcp
import json, asyncdispatch, times, options

let server = newMcpServer("example", "1.0.0")

# Register echo tool
let echoTool = McpTool(
  name: "echo",
  description: some("Echo back the input text"),
  inputSchema: %*{
    "type": "object",
    "properties": {
      "text": {"type": "string", "description": "Text to echo back"}
    },
    "required": ["text"] 
  }
)

proc echoHandler(args: JsonNode): Future[McpToolResult] {.async.} =
  let text = args["text"].getStr()
  return McpToolResult(content: @[createTextContent("Echo: " & text)])

server.registerTool(echoTool, echoHandler)

# Register time tool
let timeTool = McpTool(
  name: "current_time",
  description: some("Get the current date and time"),
  inputSchema: %*{
    "type": "object",
    "properties": {}
  }
)

proc timeHandler(args: JsonNode): Future[McpToolResult] {.async.} =
  return McpToolResult(content: @[createTextContent("Current time: " & $now())])

server.registerTool(timeTool, timeHandler)

# Register resource
let infoResource = McpResource(
  uri: "info://server",
  name: "Server Info", 
  description: some("Information about this server")
)

proc infoHandler(uri: string): Future[McpResourceContents] {.async.} =
  return McpResourceContents(
    uri: uri,
    content: @[createTextContent("This is a simple MCP server built with nimcp!")]
  )

server.registerResource(infoResource, infoHandler)

# Run the server
when isMainModule:
  waitFor server.runStdio()