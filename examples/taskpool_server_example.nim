## Example MCP server using modern taskpools for concurrent processing
## This demonstrates the improved performance and energy efficiency
## compared to the deprecated threadpool implementation.

import ../src/nimcp/[taskpool_server, types, protocol], json, options, times

# Create a new taskpool-based MCP server
let server = newTaskpoolMcpServer("taskpool-example", "1.0.0", numThreads = 4)

# Register a simple tool
let echoTool = McpTool(
  name: "echo",
  description: some("Echo back the input message"),
  inputSchema: %*{
    "type": "object",
    "properties": {
      "message": {"type": "string", "description": "Message to echo back"}
    },
    "required": ["message"]
  }
)

proc echoHandler(args: JsonNode): McpToolResult =
  let message = args["message"].getStr()
  return McpToolResult(content: @[createTextContent("Echo: " & message)])

server.registerTool(echoTool, echoHandler)

# Register a time tool
let timeTool = McpTool(
  name: "current_time",
  description: some("Get the current time"),
  inputSchema: %*{
    "type": "object",
    "properties": {},
    "required": []
  }
)

proc timeHandler(args: JsonNode): McpToolResult =
  return McpToolResult(content: @[createTextContent("Current time: " & $now())])

server.registerTool(timeTool, timeHandler)

# Register a resource
let infoResource = McpResource(
  uri: "info://server",
  name: "Server Info", 
  description: some("Information about this taskpool-based server")
)

proc infoHandler(uri: string): McpResourceContents =
  return McpResourceContents(
    uri: uri,
    content: @[createTextContent("This is a modern MCP server using taskpools for efficient concurrent processing!")]
  )

server.registerResource(infoResource, infoHandler)

# Run the server
when isMainModule:
  echo "Starting taskpool-based MCP server with 4 worker threads..."
  server.runStdio()
