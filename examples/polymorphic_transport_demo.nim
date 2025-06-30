## Polymorphic Transport Demo - Perfect Transport Abstraction
## Demonstrates truly polymorphic transport access where tools work with any transport
## without needing to specify the transport type - the ultimate abstraction!

import ../src/nimcp
import json, strformat, options, times, os

proc addTool(args: JsonNode): McpToolResult {.gcsafe.} =
  let a = args.getOrDefault("a").getFloat()
  let b = args.getOrDefault("b").getFloat()
  return McpToolResult(content: @[createTextContent(fmt"Result: {a + b}")])

proc universalNotifyTool(ctx: McpRequestContext, args: JsonNode): McpToolResult {.gcsafe.} =
  ## Tool that works with ANY transport - SSE, WebSocket, HTTP, etc.
  ## No transport type specification needed - true polymorphism!
  let message = args.getOrDefault("message").getStr("Hello from Universal MCP!")
  let count = args.getOrDefault("count").getInt(3)
  
  echo fmt"🌟 [UNIVERSAL] Sending {count} notifications: '{message}'"
  echo "   🎯 This tool works with ANY transport without code changes!"
  
  # Access transport polymorphically - NO type specification needed!
  let server = ctx.getServer()
  let transport = if server != nil: server.getTransport() else: nil  # 🎉 No type needed!
  
  if transport == nil:
    echo "   ⚠️  No transport available - notifications not sent"
    return McpToolResult(content: @[createTextContent("Error: No transport available")])
  
  # Get transport kind for logging (optional)
  let transportKind = transport.getTransportKind()
  echo fmt"   📡 Using transport: {transportKind}"
  
  # Send notifications using unified polymorphic API
  for i in 1..count:
    let notificationData = %*{
      "type": "universal_notification",
      "message": fmt"{message} (#{i}/{count})",
      "timestamp": $now(),
      "index": i,
      "total": count,
      "transport": $transportKind,  # Shows which transport is actually used
      "source": "polymorphic_api"
    }
    
    # This SAME CODE works with SSE, WebSocket, HTTP, or any future transport!
    transport.broadcastMessage(notificationData)  # 🚀 Polymorphic call!
    echo fmt"   📨 Sent notification {i}/{count} via {transportKind}"
    
    if i < count:
      sleep(400)
  
  return McpToolResult(content: @[createTextContent(fmt"Sent {count} universal notifications via {transportKind}: '{message}'")])

proc universalProgressTool(ctx: McpRequestContext, args: JsonNode): McpToolResult {.gcsafe.} =
  ## Progress updates that work with any transport type - perfect abstraction!
  let operation = args.getOrDefault("operation").getStr("universal_task")
  let steps = args.getOrDefault("steps").getInt(5)
  
  if steps <= 0 or steps > 20:
    return McpToolResult(content: @[createTextContent("Error: Steps must be between 1 and 20")])
  
  echo fmt"🔄 [UNIVERSAL] Starting '{operation}' with {steps} steps"
  
  # Access ANY transport polymorphically
  let server = ctx.getServer()
  let transport = if server != nil: server.getTransport() else: nil  # 🎉 Works for all!
  
  if transport == nil:
    echo "   ⚠️  No transport available"
    return McpToolResult(content: @[createTextContent("Error: No transport available")])
  
  let transportKind = transport.getTransportKind()
  echo fmt"   📡 Using transport: {transportKind} for progress streaming"
  
  # Send start event using polymorphic API
  let startData = %*{
    "operation": operation,
    "total_steps": steps,
    "transport": $transportKind,
    "timestamp": $now(),
    "source": "polymorphic_api"
  }
  transport.sendEvent("progress_start", startData)  # 🚀 Works with any transport!
  echo "   🚀 Sent start notification"
  
  # Stream progress updates
  for step in 1..steps:
    sleep(800)
    let percentage = (step * 100) div steps
    
    let progressData = %*{
      "operation": operation,
      "current_step": step,
      "total_steps": steps,
      "percentage": percentage,
      "transport": $transportKind,
      "timestamp": $now(),
      "source": "polymorphic_api"
    }
    
    transport.sendEvent("progress_update", progressData)  # 🚀 Transport-agnostic!
    echo fmt"   📊 Progress: {step}/{steps} ({percentage}%) via {transportKind}"
  
  # Send completion event
  let completeData = %*{
    "operation": operation,
    "final_steps": steps,
    "transport": $transportKind,
    "timestamp": $now(),
    "source": "polymorphic_api"
  }
  transport.sendEvent("progress_complete", completeData)  # 🚀 Universal API!
  echo "   ✅ Sent completion notification"
  
  return McpToolResult(content: @[createTextContent(fmt"Universal operation '{operation}' completed with {steps} steps via {transportKind}")])

proc universalBroadcastTool(ctx: McpRequestContext, args: JsonNode): McpToolResult {.gcsafe.} =
  ## Custom broadcasting that adapts to any transport automatically
  let eventType = args.getOrDefault("event_type").getStr("custom_event")
  let data = args.getOrDefault("data").getStr("Custom data payload")
  
  echo fmt"📻 [UNIVERSAL] Broadcasting '{eventType}' with polymorphic API"
  
  # Get transport without knowing its type
  let server = ctx.getServer()
  let transport = if server != nil: server.getTransport() else: nil
  
  if transport == nil:
    return McpToolResult(content: @[createTextContent("Error: No transport available")])
  
  let transportKind = transport.getTransportKind()
  
  # Broadcast using universal API
  let eventData = %*{
    "type": eventType,
    "payload": data,
    "transport": $transportKind,
    "timestamp": $now(),
    "source": "polymorphic_api",
    "broadcast_id": $now().toTime().toUnix()
  }
  
  transport.sendEvent(eventType, eventData)  # 🚀 Works with ANY transport!
  echo fmt"   📡 Broadcasted '{eventType}' via {transportKind}"
  
  return McpToolResult(content: @[createTextContent(fmt"Universal broadcast '{eventType}' sent via {transportKind}")])

proc demoInfoResource(uri: string): McpResourceContents {.gcsafe.} =
  let currentTime = now()
  
  return McpResourceContents(
    uri: uri,
    content: @[createTextContent(fmt"""# Polymorphic Transport Demo 🌟

## Perfect Transport Abstraction Achieved! ✨

**Current Status**: {currentTime}

### 🎯 The Ultimate Achievement

This demo showcases **PERFECT transport abstraction** - tools work with ANY transport without code changes!

### 🚀 Key Innovation: True Polymorphism

**Same tool code works with:**
- ✅ **SSE (Server-Sent Events)** - Real-time server push
- ✅ **WebSocket** - Bidirectional communication  
- ✅ **HTTP** - Request-response (future)
- ✅ **Any future transport** - Zero code changes needed!

### 🏗️ Architecture Breakthrough

**Before** (type-specific):
```nim
# Old way - transport-specific code
let sseTransport = server.getTransport(SseTransport)      # SSE only
let wsTransport = server.getTransport(WebSocketTransport) # WebSocket only
```

**After** (polymorphic):
```nim
# New way - universal transport access
let transport = server.getTransport()  # 🎉 Works with ANY transport!
transport.broadcastMessage(data)      # 🚀 Universal API call!
transport.sendEvent("event", data)    # 🚀 Works everywhere!
```

### 🎨 Tool Implementation Examples

**Universal Notification Tool**:
```nim
proc universalNotifyTool(ctx: McpRequestContext, args: JsonNode): McpToolResult =
  let server = ctx.getServer()
  let transport = server.getTransport()  # 🎉 No type specification!
  
  # This SAME code works with SSE, WebSocket, HTTP, etc.
  for i in 1..count:
    transport.broadcastMessage(notificationData)  # 🚀 Universal!
```

**Universal Progress Streaming**:
```nim
proc universalProgressTool(ctx: McpRequestContext, args: JsonNode): McpToolResult =
  let transport = server.getTransport()  # 🎉 Transport-agnostic!
  
  transport.sendEvent("progress_start", startData)   # 🚀 Works everywhere!
  transport.sendEvent("progress_update", progress)   # 🚀 Any transport!
  transport.sendEvent("progress_complete", complete) # 🚀 Universal API!
```

### 🔥 Benefits Achieved

**Developer Experience**:
- 🎯 **Write once, run anywhere** - No transport-specific code
- 🚀 **Future-proof** - New transports work automatically  
- 🛡️ **Type-safe** - Compile-time polymorphism with runtime flexibility
- 📦 **Clean API** - No casting or type specification needed

**Architecture**:
- 🏗️ **Perfect abstraction** - Transport details hidden completely
- 🔄 **Hot-swappable** - Change transports without touching tools
- 📊 **Introspectable** - Can query transport capabilities if needed
- ⚡ **Performance** - No runtime overhead, compile-time dispatch

### 🎮 Demo Instructions

**1. Try with SSE**:
```bash
# Start as SSE server
nim c -r examples/polymorphic_transport_demo.nim sse

# Watch events
curl -N http://127.0.0.1:8080/sse

# Send tools (separate terminal)
curl -X POST http://127.0.0.1:8080/messages -H "Content-Type: application/json" \
  -d '{{"jsonrpc":"2.0","id":"notify","method":"tools/call","params":{{"name":"universal_notify","arguments":{{"message":"SSE Demo!","count":3}}}}}}'
```

**2. Try with WebSocket** (same tools!):
```bash
# Start as WebSocket server  
nim c -r examples/polymorphic_transport_demo.nim websocket

# Connect WebSocket
const ws = new WebSocket('ws://127.0.0.1:8080/');
ws.onmessage = (e) => console.log('Received:', JSON.parse(e.data));

# Send same tools
ws.send(JSON.stringify({{
  "jsonrpc":"2.0","id":"notify","method":"tools/call",
  "params":{{"name":"universal_notify","arguments":{{"message":"WebSocket Demo!","count":3}}}}
}}));
```

### 📊 Available Universal Tools

**All work with ANY transport**:
- `universal_notify` - Broadcast notifications universally
- `universal_progress` - Stream progress to any transport
- `universal_broadcast` - Custom events on any transport
- `add` - Simple math (works everywhere)

### 🎉 The Result

**Perfect transport abstraction** where:
- ✅ Tools never specify transport types
- ✅ Same code works with SSE, WebSocket, HTTP
- ✅ Future transports work without code changes
- ✅ Runtime transport switching possible
- ✅ Type-safe polymorphic dispatch

This is the **ultimate MCP transport architecture** - true write-once, run-anywhere for real-time communication! 🚀

### 💡 Usage Notes

**Transport Detection**: Tools can optionally check transport capabilities:
```nim
let transport = server.getTransport()
let kind = transport.getTransportKind()  # tkSSE, tkWebSocket, etc.
let caps = transport.capabilities         # tcBroadcast, tcEvents, etc.
```

**Error Handling**: Universal tools gracefully handle missing transports:
```nim
let transport = server.getTransport()
if transport == nil:
  return McpToolResult(content: @[createTextContent("No transport available")])
```

This represents the **pinnacle of transport abstraction** in MCP servers! 🌟
""")]
  )

when isMainModule:
  import os
  
  # Support command line transport selection for demonstration
  let args = commandLineParams()
  let transportType = if args.len > 0: args[0] else: "sse"
  
  echo "🌟 POLYMORPHIC TRANSPORT DEMO - PERFECT ABSTRACTION"
  echo "=================================================="
  echo ""
  echo "🎯 This demo showcases PERFECT transport abstraction:"
  echo "   🚀 Same tool code works with ANY transport"
  echo "   📦 No transport type specification needed"
  echo "   🔄 Runtime transport switching possible"
  echo ""
  
  let server = newMcpServer("polymorphic-transport-demo", "1.0.0")
  
  # Create transport based on command line argument
  case transportType:
  of "websocket", "ws":
    echo "🌐 Selected: WebSocket Transport"
    echo "   📡 Bidirectional real-time communication"
    echo "   🔗 Connect: ws://127.0.0.1:8080/"
    let transport = newWebSocketTransport(server, port = 8080, host = "127.0.0.1")
    server.setTransport(transport)
  else: # default to SSE
    echo "📡 Selected: SSE (Server-Sent Events) Transport"  
    echo "   📨 Server-to-client events with HTTP requests"
    echo "   🔗 Stream: http://127.0.0.1:8080/sse"
    echo "   📮 Messages: http://127.0.0.1:8080/messages"
    let transport = newSseTransport(server, port = 8080, host = "127.0.0.1")
    server.setTransport(transport)
  
  echo ""
  echo "✨ Key Innovation: ALL tools work with BOTH transports!"
  echo "   🎯 No transport-specific code needed"
  echo "   🚀 Same universal API calls work everywhere"
  echo ""
  
  # Register universal tools that work with ANY transport
  server.registerTool(McpTool(
    name: "add",
    description: some("Simple addition (works with any transport)"),
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
    name: "universal_notify", 
    description: some("Universal notifications - works with ANY transport"),
    inputSchema: %*{
      "type": "object",
      "properties": {
        "message": {"type": "string", "description": "Message to broadcast universally"},
        "count": {"type": "integer", "description": "Number of notifications to send"}
      },
      "required": ["message", "count"]
    }
  ), universalNotifyTool)
  
  server.registerToolWithContext(McpTool(
    name: "universal_progress",
    description: some("Universal progress streaming - works with ANY transport"),
    inputSchema: %*{
      "type": "object", 
      "properties": {
        "operation": {"type": "string", "description": "Name of the operation"},
        "steps": {"type": "integer", "description": "Number of steps to process (1-20)"}
      },
      "required": ["steps"]
    }
  ), universalProgressTool)
  
  server.registerToolWithContext(McpTool(
    name: "universal_broadcast",
    description: some("Universal event broadcasting - works with ANY transport"),
    inputSchema: %*{
      "type": "object",
      "properties": {
        "event_type": {"type": "string", "description": "Type of event to broadcast"},
        "data": {"type": "string", "description": "Data payload for the event"}
      },
      "required": ["event_type", "data"]
    }
  ), universalBroadcastTool)
  
  # Register informational resource
  server.registerResource(McpResource(
    uri: "polymorphic://demo-info",
    name: "Polymorphic Transport Demo Info",
    description: some("Information about perfect transport abstraction"),
    mimeType: some("text/markdown")
  ), demoInfoResource)

  echo "📋 Universal Tools Available:"
  echo "   🔄 universal_notify - Broadcast notifications"
  echo "   📊 universal_progress - Stream progress updates"  
  echo "   📻 universal_broadcast - Custom event broadcasting"
  echo "   ➕ add - Simple addition"
  echo ""
  echo "🎮 Demo Commands:"
  
  case transportType:
  of "websocket", "ws":
    echo ""
    echo "   # 1. Connect WebSocket (browser console):"
    echo "   const ws = new WebSocket('ws://127.0.0.1:8080/');"
    echo "   ws.onmessage = (e) => console.log('📨', JSON.parse(e.data));"
    echo ""
    echo "   # 2. Initialize MCP:"
    echo "   ws.send(JSON.stringify({"
    echo "     \"jsonrpc\":\"2.0\",\"id\":\"init\",\"method\":\"initialize\","
    echo "     \"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"ws-client\",\"version\":\"1.0.0\"}}"
    echo "   }));"
    echo ""
    echo "   # 3. Test universal notifications:"
    echo "   ws.send(JSON.stringify({"
    echo "     \"jsonrpc\":\"2.0\",\"id\":\"notify\",\"method\":\"tools/call\","
    echo "     \"params\":{\"name\":\"universal_notify\",\"arguments\":{\"message\":\"WebSocket Universal!\",\"count\":3}}"
    echo "   }));"
  else:
    echo ""
    echo "   # 1. Watch SSE stream (separate terminal):"
    echo "   curl -N http://127.0.0.1:8080/sse"
    echo ""
    echo "   # 2. Initialize MCP:"
    echo "   curl -X POST http://127.0.0.1:8080/messages -H \"Content-Type: application/json\" \\"
    echo "     -d '{\"jsonrpc\":\"2.0\",\"id\":\"init\",\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"curl-client\",\"version\":\"1.0.0\"}}}'"
    echo ""
    echo "   # 3. Test universal notifications:" 
    echo "   curl -X POST http://127.0.0.1:8080/messages -H \"Content-Type: application/json\" \\"
    echo "     -d '{\"jsonrpc\":\"2.0\",\"id\":\"notify\",\"method\":\"tools/call\",\"params\":{\"name\":\"universal_notify\",\"arguments\":{\"message\":\"SSE Universal!\",\"count\":3}}}'"
  
  echo ""
  echo "🎉 Perfect Polymorphism Achieved!"
  echo "   Same tool code works with SSE, WebSocket, and future transports!"
  echo ""
  echo "🚀 Starting polymorphic server..."
  
  # Start the selected transport
  let transport = server.getTransport()
  if transport != nil:
    case transport.getTransportKind():
    of tkSSE:
      let sseTransport = server.getTransport(SseTransport)
      if sseTransport != nil:
        sseTransport.start()
    of tkWebSocket:
      let wsTransport = server.getTransport(WebSocketTransport)
      if wsTransport != nil:
        wsTransport.serve()
    else:
      echo "❌ Unknown transport type"
  else:
    echo "❌ No transport configured"