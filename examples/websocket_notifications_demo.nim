## WebSocket Notifications Demo - showcases server-initiated events
## Demonstrates the unified transport API - same code works for SSE and WebSocket
## Uses enhanced server architecture with context-based server access

import ../src/nimcp
import ../src/nimcp/server as serverModule  # Explicit import for transport functions
import json, math, strformat, options, times, os

proc addTool(args: JsonNode): McpToolResult {.gcsafe.} =
  let a = args.getOrDefault("a").getFloat()
  let b = args.getOrDefault("b").getFloat()
  return McpToolResult(content: @[createTextContent(fmt"Result: {a + b}")])

proc notifyTool(ctx: McpRequestContext, args: JsonNode): McpToolResult {.gcsafe.} =
  ## Tool that triggers server notifications via WebSocket using server context
  let message = args.getOrDefault("message").getStr("Hello from MCP WebSocket!")
  let count = args.getOrDefault("count").getInt(3)
  
  echo fmt"📡 [WebSocket] Sending {count} notifications with message: '{message}'"
  
  # Access WebSocket transport from server via request context
  let server = ctx.getServer()
  let transport = if server != nil: server.getTransport(WebSocketTransport) else: nil
  
  # Send actual WebSocket notifications using unified API
  for i in 1..count:
    let notificationData = %*{
      "type": "websocket_notification",
      "message": fmt"{message} (#{i}/{count})",
      "timestamp": $now(),
      "index": i,
      "total": count,
      "source": "websocket_api"
    }
    
    if transport != nil:
      transport.broadcastMessage(notificationData)  # Unified API - same as SSE!
      echo fmt"   📨 [WebSocket] Sent notification {i}/{count} via WebSocket"
    else:
      echo fmt"   ⚠️  [WebSocket] WebSocket transport not available - notification {i}/{count} not sent"
    
    # Small delay between notifications for demonstration
    if i < count:
      sleep(500)
  
  return McpToolResult(content: @[createTextContent(fmt"Sent {count} notifications via WebSocket: '{message}'")])

proc progressTool(ctx: McpRequestContext, args: JsonNode): McpToolResult {.gcsafe.} =
  ## Tool that sends progress updates via WebSocket with unified API
  let target = args.getOrDefault("target").getInt(10)
  let delay = args.getOrDefault("delay_ms").getInt(1000)
  
  if target <= 0 or target > 100:
    return McpToolResult(content: @[createTextContent("Error: Target must be between 1 and 100")])
  
  echo fmt"🔄 [WebSocket] Starting count to {target} (delay: {delay}ms per step)"
  echo "   📨 Sending real-time progress updates via WebSocket:"
  
  # Access WebSocket transport from server via request context
  let server = ctx.getServer()
  let transport = if server != nil: server.getTransport(WebSocketTransport) else: nil
  
  # Send start notification using unified event API
  if transport != nil:
    let startData = %*{
      "operation": "websocket_count",
      "target": target,
      "delay_ms": delay,
      "timestamp": $now()
    }
    transport.sendEvent("progress_start", startData)  # Unified API - same as SSE!
    echo "   🚀 [WebSocket] Sent start notification via WebSocket"
  
  for i in 1..target:
    sleep(delay)
    let percentage = (i * 100) div target
    
    # Send real progress updates via WebSocket using unified API
    if transport != nil:
      let progressData = %*{
        "operation": "websocket_count",
        "current": i,
        "total": target,
        "percentage": percentage,
        "timestamp": $now()
      }
      transport.sendEvent("progress_update", progressData)  # Unified API!
      echo fmt"   📊 [WebSocket] Progress via WebSocket: {i}/{target} ({percentage}%)"
    else:
      echo fmt"   📊 [WebSocket] Progress: {i}/{target} ({percentage}%) [WebSocket not available]"
  
  # Send completion notification
  if transport != nil:
    let completeData = %*{
      "operation": "websocket_count",
      "final_count": target,
      "timestamp": $now()
    }
    transport.sendEvent("progress_complete", completeData)  # Unified API!
    echo "   ✅ [WebSocket] Sent completion notification via WebSocket"
  
  return McpToolResult(content: @[createTextContent(fmt"Count completed: reached {target} with real-time WebSocket updates")])

proc serverInfoResource(uri: string): McpResourceContents {.gcsafe.} =
  ## Resource showing WebSocket unified API integration
  let currentTime = now()
  
  return McpResourceContents(
    uri: uri,
    content: @[createTextContent(fmt"""# WebSocket Notifications with Unified API

## Transport-Agnostic Architecture ✨

This example demonstrates **unified transport API** - the same code works for both SSE and WebSocket!

### 🎯 Current Status
- **Time**: {currentTime}
- **Transport**: WebSocket (bidirectional real-time)
- **API**: Unified with SSE transport
- **Architecture**: Enhanced with server-aware context

### 🔄 Unified Transport API

**Same code works for both transports:**

```nim
# This code is IDENTICAL for SSE and WebSocket!
transport.broadcastMessage(jsonData)    # Broadcast JSON messages
transport.sendEvent("event_type", data) # Send custom events
```

### 🚀 WebSocket vs SSE Comparison

**WebSocket Advantages:**
- ✅ **Bidirectional**: Client can send to server without HTTP requests
- ✅ **Lower latency**: No HTTP overhead per message
- ✅ **Persistent**: Single connection for both directions
- ✅ **Real-time**: Perfect for interactive applications

**SSE Advantages:**
- ✅ **Native events**: Built-in event types and IDs
- ✅ **Auto-reconnect**: Browser automatically reconnects
- ✅ **HTTP-friendly**: Works through standard HTTP infrastructure
- ✅ **Simple**: Easier setup and debugging

### 📡 WebSocket Event Examples

**Notifications** (wrapped in JSON envelope):
```javascript
{{
  "event": "websocket_notification",
  "data": {{
    "type": "websocket_notification", 
    "message": "Hello! (#1/3)",
    "timestamp": "{currentTime}",
    "source": "websocket_api"
  }}
}}
```

**Progress Updates** (using sendEvent):
```javascript
{{
  "event": "progress_update",
  "data": {{
    "operation": "websocket_count",
    "current": 3,
    "total": 10,
    "percentage": 30
  }}
}}
```

### 🏗️ Architecture Benefits

**Transport Abstraction:**
- 🎯 **Switch transports** without changing tool code
- 🔄 **Unified API** - broadcastMessage() and sendEvent() work identically
- 🛡️ **Type safety** - Union types prevent transport mix-ups
- 📦 **Clean separation** - Transport-specific logic isolated

**Code Reusability:**
```nim
# Same notification logic works for both:
proc sendNotification(transport: SseTransport, data: JsonNode) =
  transport.broadcastMessage(data)

proc sendNotification(transport: WebSocketTransport, data: JsonNode) =  
  transport.broadcastMessage(data)  # Identical API!
```

### 🎮 Demo Instructions

**1. Start WebSocket Client** (browser console):
```javascript
const ws = new WebSocket('ws://127.0.0.1:8080/');
ws.onmessage = (event) => console.log('Received:', JSON.parse(event.data));
ws.onopen = () => console.log('WebSocket connected!');
```

**2. Initialize MCP Connection**:
```bash
# Send initialization via WebSocket
ws.send(JSON.stringify({{
  "jsonrpc": "2.0",
  "id": "init", 
  "method": "initialize",
  "params": {{
    "protocolVersion": "2024-11-05",
    "capabilities": {{}},
    "clientInfo": {{"name": "websocket-client", "version": "1.0.0"}}
  }}
}}));
```

**3. Test Unified Notifications**:
```bash
# Trigger notifications - watch WebSocket messages!
ws.send(JSON.stringify({{
  "jsonrpc": "2.0",
  "id": "notify",
  "method": "tools/call", 
  "params": {{
    "name": "notify",
    "arguments": {{"message": "WebSocket Demo!", "count": 3}}
  }}
}}));
```

**4. Test Progress Streaming**:
```bash
# Watch real-time progress updates
ws.send(JSON.stringify({{
  "jsonrpc": "2.0", 
  "id": "progress",
  "method": "tools/call",
  "params": {{
    "name": "progress", 
    "arguments": {{"target": 5, "delay_ms": 1000}}
  }}
}}));
```

### 🎉 Key Innovation

**Perfect Transport Abstraction** - Switch from SSE to WebSocket by changing just 2 lines:

```nim
# SSE Version:
let transport = newSseTransport(server, port = 8080)
server.setTransport(transport)  # Clean API!

# WebSocket Version: 
let transport = newWebSocketTransport(server, port = 8080)
server.setTransport(transport)  # Same clean API!

# Everything else stays exactly the same!
```

This unified API makes it trivial to support multiple transport types! 🚀
""")]
  )

when isMainModule:
  let server = newMcpServer("websocket-notifications-demo", "1.0.0")
  
  # Create WebSocket transport and store in server
  let transport = newWebSocketTransport(server, port = 8080, host = "127.0.0.1")
  server.setTransport(transport)
  
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
    description: some("Demonstrate server notifications via WebSocket"),
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
    name: "progress",
    description: some("Count with progress updates via WebSocket"),
    inputSchema: %*{
      "type": "object", 
      "properties": {
        "target": {"type": "integer", "description": "Number to count to (1-100)"},
        "delay_ms": {"type": "integer", "description": "Delay between counts in milliseconds"}
      },
      "required": ["target"]
    }
  ), progressTool)
  
  # Register informational resource
  server.registerResource(McpResource(
    uri: "websocket://demo-info",
    name: "WebSocket Unified API Demo Info",
    description: some("Information about unified transport API with WebSocket"),
    mimeType: some("text/markdown")
  ), serverInfoResource)

  echo "🎯 WEBSOCKET NOTIFICATIONS WITH UNIFIED API"
  echo "==========================================="
  echo ""
  echo "🔥 This demo showcases UNIFIED transport API:"
  echo "   📡 Same code works for SSE and WebSocket!"
  echo "   🔄 transport.broadcastMessage() - identical for both"
  echo "   🎯 transport.sendEvent() - unified event API"
  echo ""
  echo "🌟 WebSocket Features:"
  echo "   ✅ Bidirectional real-time communication"
  echo "   ✅ Lower latency than SSE"
  echo "   ✅ Single persistent connection"
  echo "   ✅ Perfect for interactive applications"
  echo ""
  echo "🚀 Transport Switching:"
  echo "   Just change 2 lines to switch from SSE to WebSocket!"
  echo "   All tool code stays exactly the same!"
  echo ""
  echo "🌐 Demo Endpoints:"
  echo "   📨 WebSocket: ws://127.0.0.1:8080/"
  echo ""
  echo "🧪 Quick WebSocket Test:"
  echo "   1. Open browser console"
  echo "   2. const ws = new WebSocket('ws://127.0.0.1:8080/');"
  echo "   3. ws.onmessage = (e) => console.log('Received:', JSON.parse(e.data));"
  echo "   4. Send MCP initialization and tool calls via ws.send()"
  echo ""
  echo "💡 Key Innovation: Perfect transport abstraction!"
  echo "   Switch between SSE ↔ WebSocket with zero tool changes!"
  echo ""
  echo "🚀 Starting WebSocket server..."
  
  # Start the WebSocket transport
  server.run()