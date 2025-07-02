## Streamable HTTP Calculator MCP Server Example
## Demonstrates MCP Streamable HTTP transport with SSE streaming and chunked encoding

import ../src/nimcp
import ../src/nimcp/auth  # For newAuthConfig
import json, math, strformat, times, os, options

# Simple calculator tools that work with any transport
proc addTool(args: JsonNode): McpToolResult {.gcsafe.} =
  let a = args.getOrDefault("a").getFloat()
  let b = args.getOrDefault("b").getFloat()
  return McpToolResult(content: @[createTextContent(fmt"Result: {a + b}")])

proc multiplyTool(args: JsonNode): McpToolResult {.gcsafe.} =
  let x = args.getOrDefault("x").getInt()
  let y = args.getOrDefault("y").getInt()
  return McpToolResult(content: @[createTextContent(fmt"Result: {x * y}")])

# Context-aware tool that demonstrates streaming capabilities
proc streamingCalculationTool(ctx: McpRequestContext, args: JsonNode): McpToolResult {.gcsafe.} =
  ## Perform a calculation with streaming progress updates
  let operation = args.getOrDefault("operation").getStr("fibonacci")
  let steps = args.getOrDefault("steps").getInt(10)
  
  if steps <= 0 or steps > 50:
    return McpToolResult(content: @[createTextContent("Error: Steps must be between 1 and 50")])
  
  echo fmt"🔢 [STREAMING] Starting '{operation}' calculation with {steps} steps"
  
  # Access transport polymorphically - works with HTTP, WebSocket, SSE
  let server = ctx.getServer()
  if server == nil:
    echo "   ⚠️  No server available - continuing without streaming"
    return McpToolResult(content: @[createTextContent("Error: No server available")])
  
  if not server.transport.isSome:
    echo "   ⚠️  No transport available - continuing without streaming"
    return McpToolResult(content: @[createTextContent("Error: No transport available")])
  
  var transport = server.transport.get()
  let transportKind = transport.kind
  echo fmt"   📡 Using transport: {transportKind} for streaming calculations"
  
  # Send start event
  let startData = %*{
    "operation": operation,
    "total_steps": steps,
    "transport": $transportKind,
    "timestamp": $now(),
    "source": "streamable_http"
  }
  transport.sendEvent("calculation_start", startData)
  echo "   🚀 Sent calculation start notification"
  
  # Perform calculation with streaming updates
  var results: seq[int] = @[]
  case operation:
  of "fibonacci":
    var a, b = 1
    for step in 1..steps:
      if step <= 2:
        results.add(1)
      else:
        let next = a + b
        results.add(next)
        a = b
        b = next
      
      sleep(200)  # Simulate calculation time
      
      let progressData = %*{
        "operation": operation,
        "current_step": step,
        "total_steps": steps,
        "current_result": results[^1],
        "percentage": (step * 100) div steps,
        "transport": $transportKind,
        "timestamp": $now(),
        "source": "streamable_http"
      }
      
      transport.sendEvent("calculation_progress", progressData)
      echo fmt"   📊 Step {step}/{steps}: fibonacci({step}) = {results[^1]} via {transportKind}"
  
  of "squares":
    for step in 1..steps:
      let square = step * step
      results.add(square)
      
      sleep(150)
      
      let progressData = %*{
        "operation": operation,
        "current_step": step,
        "total_steps": steps,
        "current_result": square,
        "percentage": (step * 100) div steps,
        "transport": $transportKind,
        "timestamp": $now(),
        "source": "streamable_http"
      }
      
      transport.sendEvent("calculation_progress", progressData)
      echo fmt"   📊 Step {step}/{steps}: {step}² = {square} via {transportKind}"
  
  else:
    return McpToolResult(content: @[createTextContent(fmt"Error: Unknown operation '{operation}'")])
  
  # Send completion event
  let completeData = %*{
    "operation": operation,
    "final_steps": steps,
    "results": results,
    "transport": $transportKind,
    "timestamp": $now(),
    "source": "streamable_http"
  }
  transport.sendEvent("calculation_complete", completeData)
  echo "   ✅ Sent calculation completion notification"
  
  return McpToolResult(content: @[createTextContent(fmt"Streaming '{operation}' calculation completed with {steps} steps via {transportKind}. Results: {results}")])

# Universal notification tool that works with any transport
proc universalNotifyTool(ctx: McpRequestContext, args: JsonNode): McpToolResult {.gcsafe.} =
  ## Send notifications that work with any transport type
  let message = args.getOrDefault("message").getStr("Hello from Streamable HTTP!")
  let count = args.getOrDefault("count").getInt(3)
  
  echo fmt"📻 [UNIVERSAL] Broadcasting {count} notifications: '{message}'"
  
  let server = ctx.getServer()
  if server == nil:
    return McpToolResult(content: @[createTextContent("Error: No server available")])
  
  if not server.transport.isSome:
    return McpToolResult(content: @[createTextContent("Error: No transport available")])
  
  var transport = server.transport.get()
  let transportKind = transport.kind
  echo fmt"   📡 Using transport: {transportKind}"
  
  # Send notifications using universal polymorphic API
  for i in 1..count:
    let notificationData = %*{
      "type": "universal_notification",
      "message": fmt"{message} (#{i}/{count})",
      "timestamp": $now(),
      "index": i,
      "total": count,
      "transport": $transportKind,
      "source": "streamable_http"
    }
    
    # This SAME CODE works with HTTP streaming, WebSocket, SSE!
    transport.broadcastMessage(notificationData)
    echo fmt"   📨 Sent notification {i}/{count} via {transportKind}"
    
    if i < count:
      sleep(300)
  
  return McpToolResult(content: @[createTextContent(fmt"Sent {count} universal notifications via {transportKind}: '{message}'")])

# Resource demonstrating streamable HTTP info
proc streamableInfoResource(uri: string): McpResourceContents {.gcsafe.} =
  let currentTime = now()
  
  return McpResourceContents(
    uri: uri,
    content: @[createTextContent(fmt"""# Streamable HTTP Calculator Demo 🚀

## MCP Streamable HTTP Transport Example

**Current Status**: {currentTime}

### 🎯 What This Demo Shows

This example demonstrates the **MCP Streamable HTTP transport** with:

- ✅ **HTTP Chunked Transfer Encoding** - Streaming responses via `Transfer-Encoding: chunked`
- ✅ **Server-Sent Events (SSE)** - Real-time event streaming to clients
- ✅ **Accept Header Detection** - Automatic mode selection based on client capabilities
- ✅ **DNS Rebinding Protection** - Origin header validation for security
- ✅ **Session Management** - Optional `Mcp-Session-Id` header support
- ✅ **Polymorphic Transport API** - Same tools work with HTTP, WebSocket, SSE

### 🏗️ MCP Specification Compliance

This implementation follows the **MCP Streamable HTTP specification** (2025-03-26):

**Client Request Headers**:
```
Accept: application/json, text/event-stream
Mcp-Session-Id: optional-session-id
Origin: https://allowed-origin.com
```

**Server Response Modes**:
- **JSON Mode**: `Content-Type: application/json` for single responses
- **SSE Mode**: `Content-Type: text/event-stream` for streaming responses

### 🔧 Technical Implementation

**Chunked Transfer Encoding**:
- Server sets `Transfer-Encoding: chunked` header
- Data streams in real-time without `Content-Length`
- Client reads chunks as they arrive

**SSE Event Format**:
```
event: calculation_progress
data: {{"step": 5, "result": 55, "timestamp": "..."}}

event: calculation_complete  
data: {{"final_results": [1,1,2,3,5,8,13,21,34,55]}}
```

### 🚀 Usage Examples

**1. JSON Mode (single response)**:
```bash
curl -X POST http://127.0.0.1:8080/ \\
  -H "Content-Type: application/json" \\
  -H "Accept: application/json" \\
  -d '{{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{{"name":"add","arguments":{{"a":10,"b":5}}}}}}'
```

**2. SSE Streaming Mode**:
```bash
# Terminal 1: Watch SSE stream
curl -N -H "Accept: application/json, text/event-stream" \\
  -X POST http://127.0.0.1:8080/ \\
  -d '{{"jsonrpc":"2.0","id":"stream","method":"tools/call","params":{{"name":"streaming_calculation","arguments":{{"operation":"fibonacci","steps":10}}}}}}'

# You'll see:
# event: calculation_start
# data: {{"operation":"fibonacci","total_steps":10}}
#
# event: calculation_progress  
# data: {{"step":1,"result":1,"percentage":10}}
# ...
```

### 📊 Available Tools

**Universal Tools** (work with any transport):
- `add` - Simple addition
- `multiply` - Integer multiplication  
- `universal_notify` - Broadcast notifications
- `streaming_calculation` - Real-time calculation progress

**Streaming Calculations**:
- `fibonacci` - Generate Fibonacci sequence with progress
- `squares` - Calculate squares with progress updates

### 🎨 Polymorphic Transport Magic

The same tool code works seamlessly across all transports:

```nim
# This code works with HTTP, WebSocket, SSE - no changes needed!
let transport = server.getTransport()  # 🎉 Transport-agnostic!
transport.sendEvent("progress", data)  # 🚀 Universal API!
transport.broadcastMessage(message)   # 🌟 Works everywhere!
```

### 🛡️ Security Features

**DNS Rebinding Protection**:
- Origin header validation
- Configurable allowed origins
- Default localhost protection

**Authentication Support**:
- Bearer token authentication
- Custom error responses
- Secure HTTPS enforcement

### 🌐 Client Compatibility

**Browser JavaScript**:
```javascript
// Works with EventSource for SSE
const eventSource = new EventSource('/stream-endpoint');
eventSource.onmessage = (event) => {{
  console.log('Streamed data:', JSON.parse(event.data));
}};

// Works with fetch for JSON
fetch('/json-endpoint', {{
  method: 'POST',
  headers: {{ 'Accept': 'application/json' }}
}});
```

This demonstrates the **pinnacle of MCP transport abstraction** - write once, stream everywhere! 🌟

### 💡 Key Innovation

The breakthrough is **automatic mode detection**:
- Client sends `Accept: application/json` → Single JSON response
- Client sends `Accept: text/event-stream` → SSE streaming  
- Client sends both → Server chooses streaming mode

**Result**: Perfect compatibility with existing tools while enabling real-time streaming! 🎯
""")]
  )

when isMainModule:
  echo "🚀 MCP STREAMABLE HTTP CALCULATOR SERVER"
  echo "========================================"
  echo ""
  echo "🎯 This server demonstrates MCP Streamable HTTP transport with:"
  echo "   📡 HTTP chunked transfer encoding for streaming"
  echo "   📨 Server-Sent Events (SSE) for real-time updates"  
  echo "   🛡️ DNS rebinding protection and authentication"
  echo "   🔄 Polymorphic transport API compatibility"
  echo ""
  echo "🌐 Server Info:"
  echo "   📍 Endpoint: http://127.0.0.1:8080/"
  echo "   🔧 Transport: MCP Streamable HTTP (2025-03-26 spec)"
  echo "   🎭 Modes: JSON response + SSE streaming"
  echo ""
  
  let server = newMcpServer("streamable-http-calculator", "1.0.0")
  
  # Register regular tools that work with any transport
  server.registerTool(McpTool(
    name: "add",
    description: some("Add two numbers together"),
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
    name: "multiply", 
    description: some("Multiply two integers"),
    inputSchema: %*{
      "type": "object",
      "properties": {
        "x": {"type": "integer", "description": "First integer"},
        "y": {"type": "integer", "description": "Second integer"}
      },
      "required": ["x", "y"]
    }
  ), multiplyTool)
  
  # Register context-aware tools that use streaming
  server.registerToolWithContext(McpTool(
    name: "streaming_calculation",
    description: some("Perform calculations with real-time streaming progress"),
    inputSchema: %*{
      "type": "object",
      "properties": {
        "operation": {"type": "string", "enum": ["fibonacci", "squares"], "description": "Type of calculation"},
        "steps": {"type": "integer", "description": "Number of calculation steps (1-50)"}
      },
      "required": ["operation", "steps"]
    }
  ), streamingCalculationTool)
  
  server.registerToolWithContext(McpTool(
    name: "universal_notify",
    description: some("Send universal notifications that work with any transport"),
    inputSchema: %*{
      "type": "object", 
      "properties": {
        "message": {"type": "string", "description": "Message to broadcast universally"},
        "count": {"type": "integer", "description": "Number of notifications to send"}
      },
      "required": ["message", "count"]
    }
  ), universalNotifyTool)
  
  # Register informational resource
  server.registerResource(McpResource(
    uri: "streamable://info",
    name: "Streamable HTTP Info",
    description: some("Information about MCP Streamable HTTP transport"),
    mimeType: some("text/markdown")
  ), streamableInfoResource)

  echo "📋 Available Tools:"
  echo "   ➕ add - Simple addition (works in both JSON and SSE modes)"
  echo "   ✖️  multiply - Integer multiplication"
  echo "   🔢 streaming_calculation - Real-time progress streaming"
  echo "   📻 universal_notify - Universal notifications"
  echo ""
  echo "📖 Available Resources:"
  echo "   📄 streamable://info - Streamable HTTP documentation"
  echo ""
  
  echo "🎮 Testing Commands:"
  echo ""
  echo "   # 1. JSON Mode (single response):"
  echo "   curl -X POST http://127.0.0.1:8080/ \\"
  echo "     -H \"Content-Type: application/json\" \\"
  echo "     -H \"Accept: application/json\" \\"  
  echo "     -d '{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"tools/call\",\"params\":{\"name\":\"add\",\"arguments\":{\"a\":10,\"b\":5}}}'"
  echo ""
  echo "   # 2. SSE Streaming Mode:"
  echo "   curl -N -X POST http://127.0.0.1:8080/ \\"
  echo "     -H \"Content-Type: application/json\" \\"
  echo "     -H \"Accept: application/json, text/event-stream\" \\"
  echo "     -d '{\"jsonrpc\":\"2.0\",\"id\":\"stream\",\"method\":\"tools/call\",\"params\":{\"name\":\"streaming_calculation\",\"arguments\":{\"operation\":\"fibonacci\",\"steps\":10}}}'"
  echo ""
  echo "   # 3. List tools:"
  echo "   curl -X POST http://127.0.0.1:8080/ \\"
  echo "     -H \"Content-Type: application/json\" \\"
  echo "     -d '{\"jsonrpc\":\"2.0\",\"id\":\"2\",\"method\":\"tools/list\",\"params\":{}}'"
  echo ""
  echo "🚀 Starting MCP Streamable HTTP server..."
  echo "   Use Ctrl+C to stop the server"
  echo ""
  
  # Configure DNS rebinding protection for localhost testing
  let allowedOrigins = @["http://localhost", "https://localhost", "http://127.0.0.1", "https://127.0.0.1"]
  
  # Start the streamable HTTP server
  server.runHttp(8080, "127.0.0.1", newAuthConfig(), allowedOrigins)