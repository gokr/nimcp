## SSE Notifications Demo - showcases server-initiated events
## Demonstrates the key advantage of SSE: server-to-client notifications

import ../src/nimcp
import json, math, strformat, options, times, random, os

proc addTool(args: JsonNode): McpToolResult =
  let a = args.getOrDefault("a").getFloat()
  let b = args.getOrDefault("b").getFloat()
  return McpToolResult(content: @[createTextContent(fmt"Result: {a + b}")])

proc notifyTool(args: JsonNode): McpToolResult =
  ## Tool that triggers server notifications via SSE
  let message = args.getOrDefault("message").getStr("Hello from MCP!")
  let count = args.getOrDefault("count").getInt(3)
  
  # This tool demonstrates how an MCP server could send notifications
  # In a real implementation, we'd send these via the SSE transport
  echo fmt"📡 Would send {count} notifications with message: '{message}'"
  echo "   (In a full implementation, these would go via SSE to all connected clients)"
  
  return McpToolResult(content: @[createTextContent(fmt"Notification tool executed: will send {count} messages '{message}'")])

proc slowCountTool(args: JsonNode): McpToolResult =
  ## Tool that simulates progress updates that could be sent via SSE
  let target = args.getOrDefault("target").getInt(10)
  let delay = args.getOrDefault("delay_ms").getInt(1000)
  
  if target <= 0 or target > 100:
    return McpToolResult(content: @[createTextContent("Error: Target must be between 1 and 100")])
  
  echo fmt"🔄 Starting slow count to {target} (delay: {delay}ms per step)"
  echo "   📨 Progress updates would be sent via SSE in real implementation:"
  
  for i in 1..target:
    sleep(delay)
    # In a real SSE implementation, we'd send progress like this:
    echo fmt"   📊 Progress: {i}/{target} ({(i*100) div target}%)"
    # sseTransport.broadcastMessage(%*{
    #   "type": "progress",
    #   "current": i,
    #   "total": target,
    #   "percentage": (i * 100) div target
    # })
  
  echo "   ✅ Count completed - final notification would be sent"
  return McpToolResult(content: @[createTextContent(fmt"Slow count completed: reached {target}")])

proc serverStatsResource(uri: string): McpResourceContents =
  ## Resource showing what SSE notifications would contain
  let currentTime = now()
  
  return McpResourceContents(
    uri: uri,
    content: @[createTextContent(fmt"""# SSE Notifications Demo

## Current Server Status
- **Time**: {currentTime}
- **Transport**: SSE (Server-Sent Events)
- **Notifications**: Enabled

## What SSE Enables

### 🚀 **Server-Initiated Events**
Unlike HTTP request-response, SSE allows the server to push data to clients:

```javascript
// Client receives these without making requests:
{{
  "type": "notification",
  "message": "Task completed!",
  "timestamp": "{currentTime}"
}}
```

### 📊 **Real-time Progress Updates**
During long-running operations:

```javascript
{{
  "type": "progress", 
  "operation": "factorial_calculation",
  "current": 7,
  "total": 10,
  "percentage": 70
}}
```

### 📡 **Live Status Broadcasting**
Server can broadcast status to all connected clients:

```javascript
{{
  "type": "server_status",
  "active_connections": 3,
  "server_load": "low",
  "uptime": "2h 15m"
}}
```

### 🔔 **Event Notifications**
Alert clients about important events:

```javascript
{{
  "type": "alert",
  "level": "info",
  "message": "New tool registered: advanced_calculator"
}}
```

## Demo Tools

1. **notify**: Demonstrates notification broadcasting
2. **slow_count**: Shows progress update streaming  
3. **add**: Regular tool (instant response)

## Real-world SSE Use Cases

- **Build Status**: CI/CD pipeline progress
- **Log Streaming**: Real-time log tail
- **Metrics**: Live system monitoring
- **Collaboration**: Real-time document editing
- **Gaming**: Live score updates
- **Trading**: Real-time price feeds

## Complete Demo Sequence

```bash
# 1. Open SSE stream (separate terminal):
curl -N http://127.0.0.1:8080/sse

# 2. Initialize MCP connection (REQUIRED):
curl -X POST http://127.0.0.1:8080/messages \\
  -H "Content-Type: application/json" \\
  -d '{{"jsonrpc":"2.0","id":"init","method":"initialize","params":{{"protocolVersion":"2024-11-05","capabilities":{{}},"clientInfo":{{"name":"curl-client","version":"1.0.0"}}}}}}'

# 3. Mark as initialized:
curl -X POST http://127.0.0.1:8080/messages \\
  -H "Content-Type: application/json" \\
  -d '{{"jsonrpc":"2.0","method":"notifications/initialized","params":{{}}}}'

# 4. List tools:
curl -X POST http://127.0.0.1:8080/messages \\
  -H "Content-Type: application/json" \\
  -d '{{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{{}}}}'

# 5. Trigger notifications:
curl -X POST http://127.0.0.1:8080/messages \\
  -H "Content-Type: application/json" \\
  -d '{{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{{"name":"notify","arguments":{{"message":"Hello SSE!","count":3}}}}}}'
```

The key difference: **SSE allows the server to PUSH data to clients**, 
not just respond to requests!
""")]
  )

when isMainModule:
  let server = newMcpServer("sse-notifications-demo", "1.0.0")
  
  # Register demonstration tools
  server.registerTool(McpTool(
    name: "add",
    description: some("Simple addition (instant response)"),
    inputSchema: %*{
      "type": "object",
      "properties": {
        "a": {"type": "number", "description": "First number"},
        "b": {"type": "number", "description": "Second number"}
      },
      "required": ["a", "b"]
    }
  ), addTool)
  
  server.registerTool(McpTool(
    name: "notify", 
    description: some("Demonstrate server notifications via SSE"),
    inputSchema: %*{
      "type": "object",
      "properties": {
        "message": {"type": "string", "description": "Message to broadcast"},
        "count": {"type": "integer", "description": "Number of notifications to send"}
      },
      "required": ["message", "count"]
    }
  ), notifyTool)
  
  server.registerTool(McpTool(
    name: "slow_count",
    description: some("Count slowly with progress updates via SSE"),
    inputSchema: %*{
      "type": "object", 
      "properties": {
        "target": {"type": "integer", "description": "Number to count to (1-100)"},
        "delay_ms": {"type": "integer", "description": "Delay between counts in milliseconds"}
      },
      "required": ["target"]
    }
  ), slowCountTool)
  
  # Register informational resource
  server.registerResource(McpResource(
    uri: "sse://demo-info",
    name: "SSE Notifications Demo Info",
    description: some("Information about SSE capabilities and demo"),
    mimeType: some("text/markdown")
  ), serverStatsResource)

  echo "🎯 SSE NOTIFICATIONS DEMO SERVER"
  echo "================================="
  echo ""
  echo "🔥 This demo showcases the KEY ADVANTAGE of SSE:"
  echo "   📡 SERVER-INITIATED EVENTS (not just request-response!)"
  echo ""
  echo "🌟 What makes SSE special:"
  echo "   ✅ Server can PUSH data to clients anytime"
  echo "   ✅ Real-time progress updates during long operations"
  echo "   ✅ Live notifications and status broadcasts"
  echo "   ✅ Streaming results as they're computed"
  echo ""
  echo "🌐 Demo Endpoints:"
  echo "   📨 SSE Stream: http://127.0.0.1:8080/sse"
  echo "   📮 Messages: http://127.0.0.1:8080/messages"
  echo ""
  echo "🧪 Complete Demo Sequence:"
  echo "   1. Open SSE stream: curl -N http://127.0.0.1:8080/sse"
  echo "   2. Initialize MCP connection (required first!)"
  echo "   3. List available tools"
  echo "   4. Trigger notifications and watch SSE stream"
  echo ""
  echo "📋 Complete Example Commands:"
  echo ""
  echo """   # 1. Watch SSE events (run in separate terminal):"""
  echo """   curl -N http://127.0.0.1:8080/sse"""
  echo ""
  echo """   # 2. Initialize MCP connection (REQUIRED FIRST):"""
  echo """   curl -X POST http://127.0.0.1:8080/messages \\"""
  echo """     -H "Content-Type: application/json" \\"""
  echo """     -d '{"jsonrpc":"2.0","id":"init","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"curl-client","version":"1.0.0"}}}'"""
  echo ""
  echo """   # 3. Mark as initialized:"""
  echo """   curl -X POST http://127.0.0.1:8080/messages \\"""
  echo """     -H "Content-Type: application/json" \\"""
  echo """     -d '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}'"""
  echo ""
  echo """   # 4. List available tools:"""
  echo """   curl -X POST http://127.0.0.1:8080/messages \\"""
  echo """     -H "Content-Type: application/json" \\"""
  echo """     -d '{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{}}'"""
  echo ""
  echo """   # 5. Trigger notifications (watch SSE stream!):"""
  echo """   curl -X POST http://127.0.0.1:8080/messages \\"""
  echo """     -H "Content-Type: application/json" \\"""
  echo """     -d '{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"notify","arguments":{"message":"Hello SSE!","count":3}}}'"""
  echo ""
  echo """   # 6. Watch slow progress updates:"""
  echo """   curl -X POST http://127.0.0.1:8080/messages \\"""
  echo """     -H "Content-Type: application/json" \\"""
  echo """     -d '{"jsonrpc":"2.0","id":"3","method":"tools/call","params":{"name":"slow_count","arguments":{"target":5,"delay_ms":2000}}}'"""
  echo ""
  echo "🚀 Starting server..."
  
  # Create and start SSE transport
  let transport = newSseTransport(server, port = 8080, host = "127.0.0.1")
  transport.start()