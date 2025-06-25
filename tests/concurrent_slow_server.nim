# Trivial MCP server to verify concurrent request handling working

import ../src/nimcp, json, options, os

let server = newMcpServer("concurrent-test", "1.0.0")

# Register a slow task tool
proc slowTaskHandler(args: JsonNode): McpToolResult =
  let id = args["id"].getInt()
  let delay = if args.hasKey("delay_ms"): args["delay_ms"].getInt() else: 100
  sleep(delay)
  return McpToolResult(content: @[createTextContent("Task " & $id & " completed")])

let slowTool = McpTool(
  name: "slow_task",
  description: some("A tool that takes time to complete"),
  inputSchema: %*{
    "type": "object",
    "properties": {
      "id": {"type": "integer", "description": "Task ID"},
      "delay_ms": {"type": "integer", "description": "Delay in milliseconds", "default": 100}
    },
    "required": ["id"]
  }
)

server.registerTool(slowTool, slowTaskHandler)
server.runStdio()