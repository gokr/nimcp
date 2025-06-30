## SSE Notifications Demo - showcases server-initiated events
## Demonstrates the key advantage of SSE: server-to-client notifications
## Uses enhanced server architecture with context-based server access

import ../src/nimcp
import ../src/nimcp/server as serverModule  # Explicit import for transport functions
import json, math, strformat, options, times, os

proc addTool(args: JsonNode): McpToolResult {.gcsafe.} =
  let a = args.getOrDefault("a").getFloat()
  let b = args.getOrDefault("b").getFloat()
  return McpToolResult(content: @[createTextContent(fmt"Result: {a + b}")])

proc notifyTool(ctx: McpRequestContext, args: JsonNode): McpToolResult {.gcsafe.} =
  ## Tool that triggers server notifications via SSE using polymorphic transport access
  let message = args.getOrDefault("message").getStr("Hello from MCP!")
  let count = args.getOrDefault("count").getInt(3)
  
  echo fmt"📡 Sending {count} notifications with message: '{message}'"
  
  # Access transport polymorphically - works with ANY transport type!
  let server = ctx.getServer()
  let transport = if server != nil: server.getTransport() else: nil  # 🎉 No type specification needed!
  
  if transport == nil:
    echo "   ⚠️  No transport available"
    return McpToolResult(content: @[createTextContent("Error: No transport available")])
  
  # Optional: Show which transport is being used
  let transportKind = transport.getTransportKind()
  echo fmt"   📡 Using transport: {transportKind}"
  
  # Send notifications using polymorphic API
  for i in 1..count:
    let notificationData = %*{
      "type": "notification",
      "message": fmt"{message} (#{i}/{count})",
      "timestamp": $now(),
      "index": i,
      "total": count,
      "transport": $transportKind
    }
    
    # This SAME CODE works with SSE, WebSocket, HTTP, or any future transport!
    transport.broadcastMessage(notificationData)  # 🚀 Polymorphic call!
    echo fmt"   📨 Sent notification {i}/{count} via {transportKind}"
    
    # Small delay between notifications for demonstration
    if i < count:
      sleep(500)
  
  return McpToolResult(content: @[createTextContent(fmt"Sent {count} notifications via {transportKind}: '{message}'")])

proc slowCountTool(ctx: McpRequestContext, args: JsonNode): McpToolResult {.gcsafe.} =
  ## Tool that sends real-time progress updates using polymorphic transport access
  let target = args.getOrDefault("target").getInt(10)
  let delay = args.getOrDefault("delay_ms").getInt(1000)
  
  if target <= 0 or target > 100:
    return McpToolResult(content: @[createTextContent("Error: Target must be between 1 and 100")])
  
  echo fmt"🔄 Starting slow count to {target} (delay: {delay}ms per step)"
  
  # Access transport polymorphically - works with ANY transport type!
  let server = ctx.getServer()
  let transport = if server != nil: server.getTransport() else: nil  # 🎉 No type needed!
  
  if transport == nil:
    echo "   ⚠️  No transport available"
    return McpToolResult(content: @[createTextContent("Error: No transport available")])
  
  let transportKind = transport.getTransportKind()
  echo fmt"   📨 Sending real-time progress updates via {transportKind}:"
  
  # Send start notification using polymorphic API
  let startData = %*{
    "type": "progress_start",
    "operation": "slow_count",
    "target": target,
    "delay_ms": delay,
    "transport": $transportKind,
    "timestamp": $now()
  }
  transport.broadcastMessage(startData)  # 🚀 Works with any transport!
  echo fmt"   🚀 Sent start notification via {transportKind}"
  
  for i in 1..target:
    sleep(delay)
    let percentage = (i * 100) div target
    
    # Send real progress updates using polymorphic API
    let progressData = %*{
      "type": "progress",
      "operation": "slow_count",
      "current": i,
      "total": target,
      "percentage": percentage,
      "transport": $transportKind,
      "timestamp": $now()
    }
    transport.broadcastMessage(progressData)  # 🚀 Transport-agnostic!
    echo fmt"   📊 Progress via {transportKind}: {i}/{target} ({percentage}%)"
  
  # Send completion notification using polymorphic API
  let completeData = %*{
    "type": "progress_complete",
    "operation": "slow_count",
    "final_count": target,
    "transport": $transportKind,
    "timestamp": $now()
  }
  transport.broadcastMessage(completeData)  # 🚀 Universal API!
  echo fmt"   ✅ Sent completion notification via {transportKind}"
  
  return McpToolResult(content: @[createTextContent(fmt"Slow count completed: reached {target} with real-time {transportKind} updates")])

proc serverStatsResource(uri: string): McpResourceContents {.gcsafe.} =
  ## Resource showing what SSE notifications would contain
  let currentTime = now()
  
  return McpResourceContents(
    uri: uri,
    content: @[createTextContent(fmt"""# SSE Notifications Demo

## Current Server Status
- **Time**: {currentTime}
- **Transport**: SSE (Server-Sent Events)
- **Notifications**: Enabled
- **Architecture**: Enhanced with server-aware context

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

## Enhanced Architecture

### 🏗️ **Server-Aware Context**
Tools now receive server access through the request context:

```nim
proc notifyTool(ctx: McpRequestContext, args: JsonNode): McpToolResult =
  let server = ctx.getServer()
  let transport = server.getCustomData("sse_transport", SseTransport)
  transport.broadcastMessage(data)
```

### ✅ **Benefits**
- **No global state** - server access through context
- **Clean architecture** - proper dependency injection
- **Type-safe** - compile-time checked server access
- **Composable** - works with multiple server instances

## Demo Tools

1. **notify**: Demonstrates notification broadcasting with server context
2. **slow_count**: Shows progress update streaming via server context
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
  
  # Create SSE transport and store in server using clean type-safe API
  let transport = newSseTransport(server, port = 8080, host = "127.0.0.1")
  server.setTransport(transport)  # Clean API - no casting needed!
  
  # Register demonstration tools using context-aware handlers
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
  
  server.registerToolWithContext(McpTool(
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
  
  server.registerToolWithContext(McpTool(
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
    description: some("Information about SSE capabilities and enhanced architecture"),
    mimeType: some("text/markdown")
  ), serverStatsResource)

  echo "🎯 SSE NOTIFICATIONS DEMO - ENHANCED ARCHITECTURE"
  echo "================================================"
  echo ""
  echo "🔥 This demo showcases the COMPLETE SSE solution:"
  echo "   📡 SERVER-INITIATED EVENTS (not just request-response!)"
  echo "   🏗️  Enhanced server architecture with context-based access"
  echo ""
  echo "🌟 What makes this implementation special:"
  echo "   ✅ Server can PUSH data to clients anytime"
  echo "   ✅ Real-time progress updates during long operations"
  echo "   ✅ Live notifications and status broadcasts"
  echo "   ✅ Clean architecture without global state or closures"
  echo "   ✅ Type-safe server access through request context"
  echo ""
  echo "🏗️  Architecture Highlights:"
  echo "   🔧 Transport stored in server.customData"
  echo "   📋 Tools access server via ctx.getServer()"
  echo "   🛡️  Type-safe data retrieval with server.getCustomData()"
  echo "   🔄 No closures or global variables needed"
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
  
  # Start the SSE transport
  transport.start()