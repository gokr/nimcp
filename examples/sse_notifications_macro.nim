## SSE Notifications with Macro API - Mixed approach
## Demonstrates combining macro API with manual context-aware tool registration
## This shows both regular macro tools and context-aware tools in one server

import ../src/nimcp
import json, math, strformat, options, times, os

# Context-aware tool handlers (need manual registration)
proc notifyTool(ctx: McpRequestContext, args: JsonNode): McpToolResult {.gcsafe.} =
  ## Tool that triggers server notifications via SSE using server context
  let message = args.getOrDefault("message").getStr("Hello from Macro MCP!")
  let count = args.getOrDefault("count").getInt(3)
  
  echo fmt"📡 [MACRO] Sending {count} notifications with message: '{message}'"
  
  # Access SSE transport from server via request context
  let server = ctx.getServer()
  let transport = if server != nil: server.getTransport(SseTransport) else: nil
  
  # Send actual SSE notifications
  for i in 1..count:
    let notificationData = %*{
      "type": "macro_notification",
      "message": fmt"{message} (#{i}/{count})",
      "timestamp": $now(),
      "index": i,
      "total": count,
      "source": "macro_api"
    }
    
    if transport != nil:
      transport.broadcastMessage(notificationData)
      echo fmt"   📨 [MACRO] Sent notification {i}/{count} via SSE"
    else:
      echo fmt"   ⚠️  [MACRO] SSE transport not available - notification {i}/{count} not sent"
    
    # Small delay between notifications for demonstration
    if i < count:
      sleep(400)
  
  return McpToolResult(content: @[createTextContent(fmt"[MACRO] Sent {count} notifications via SSE: '{message}'")])

proc progressTool(ctx: McpRequestContext, args: JsonNode): McpToolResult {.gcsafe.} =
  ## Tool that sends progress updates via SSE with macro-style naming
  let steps = args.getOrDefault("steps").getInt(5)
  let operation = args.getOrDefault("operation").getStr("macro_process")
  
  if steps <= 0 or steps > 50:
    return McpToolResult(content: @[createTextContent("Error: Steps must be between 1 and 50")])
  
  echo fmt"🔄 [MACRO] Starting {operation} with {steps} steps"
  
  # Access SSE transport from server via request context
  let server = ctx.getServer()
  let transport = if server != nil: server.getTransport(SseTransport) else: nil
  
  # Send start notification
  if transport != nil:
    let startData = %*{
      "type": "macro_progress_start",
      "operation": operation,
      "total_steps": steps,
      "timestamp": $now(),
      "source": "macro_api"
    }
    transport.broadcastMessage(startData)
    echo "   🚀 [MACRO] Sent start notification via SSE"
  
  for step in 1..steps:
    sleep(800)  # Simulate work
    let percentage = (step * 100) div steps
    
    # Send real progress updates via SSE
    if transport != nil:
      let progressData = %*{
        "type": "macro_progress",
        "operation": operation,
        "current_step": step,
        "total_steps": steps,
        "percentage": percentage,
        "timestamp": $now(),
        "source": "macro_api"
      }
      transport.broadcastMessage(progressData)
      echo fmt"   📊 [MACRO] Progress via SSE: {step}/{steps} ({percentage}%)"
    else:
      echo fmt"   📊 [MACRO] Progress: {step}/{steps} ({percentage}%) [SSE not available]"
  
  # Send completion notification
  if transport != nil:
    let completeData = %*{
      "type": "macro_progress_complete",
      "operation": operation,
      "final_steps": steps,
      "timestamp": $now(),
      "source": "macro_api"
    }
    transport.broadcastMessage(completeData)
    echo "   ✅ [MACRO] Sent completion notification via SSE"
  
  return McpToolResult(content: @[createTextContent(fmt"[MACRO] Operation '{operation}' completed with {steps} steps and real-time SSE updates")])

# Create server using macro API
mcpServer("sse-notifications-macro", "1.0.0"):
  
  # Regular tools using macro API (no context needed)
  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers together (macro-generated)
      return fmt"[MACRO] Result: {a + b}"
  
  mcpTool:
    proc multiply(x: int, y: int): string =
      ## Multiply two integers (macro-generated)
      return fmt"[MACRO] Result: {x * y}"
  
  mcpTool:
    proc factorial(n: int): string =
      ## Calculate factorial of a number (macro-generated)
      if n < 0:
        return "[MACRO] Error: Factorial not defined for negative numbers"
      elif n == 0 or n == 1:
        return "[MACRO] Result: 1"
      else:
        var res = 1
        for i in 2..n:
          res *= i
        return fmt"[MACRO] Result: {res}"
  
  mcpTool:
    proc echo_message(text: string): string =
      ## Echo back a message with macro prefix
      return fmt"[MACRO] Echo: {text}"

proc serverInfoResource(uri: string): McpResourceContents {.gcsafe.} =
  ## Resource showing macro API integration with SSE
  let currentTime = now()
  
  return McpResourceContents(
    uri: uri,
    content: @[createTextContent(fmt"""# SSE Notifications with Macro API

## Mixed Architecture Demo

This example demonstrates **combining macro API with context-aware tools**:

### 🏗️ Architecture Overview

**Macro Tools** (auto-generated, no context):
- `add` - Simple addition
- `multiply` - Integer multiplication  
- `factorial` - Factorial calculation
- `echo_message` - Text echo

**Context-Aware Tools** (manual registration):
- `notify` - Server notifications via SSE
- `progress` - Progress updates via SSE

### 📡 SSE Integration

**Current Status**:
- **Time**: {currentTime}
- **Transport**: SSE (Server-Sent Events)  
- **API Style**: Mixed (Macro + Manual)
- **Notifications**: Enabled with macro prefix

### 🔧 Implementation Details

**Macro Tools** use standard `mcpTool` macro:
```nim
mcpTool:
  proc add(a: float, b: float): string =
    ## Add two numbers together (macro-generated)
    return fmt"[MACRO] Result: {{a + b}}"
```

**Context-Aware Tools** require manual registration:
```nim
proc notifyTool(ctx: McpRequestContext, args: JsonNode): McpToolResult =
  let server = ctx.getServer()
  let transport = server.getCustomData("sse_transport", SseTransport)
  transport.broadcastMessage(notificationData)
  # ...

server.registerToolWithContext(tool, notifyTool)
```

### 📊 Real-time Features

**Notification Broadcasting**:
```javascript
{{
  "type": "macro_notification",
  "message": "Hello from Macro MCP! (#1/3)",
  "timestamp": "{currentTime}",
  "source": "macro_api"
}}
```

**Progress Streaming**:
```javascript
{{
  "type": "macro_progress",
  "operation": "macro_process",
  "current_step": 3,
  "total_steps": 5,
  "percentage": 60,
  "source": "macro_api"
}}
```

### 🎯 Key Benefits

✅ **Best of Both Worlds**: Simple macro API + powerful context features
✅ **Incremental Upgrade**: Add context features to existing macro servers
✅ **Clean Separation**: Regular tools vs. context-aware tools
✅ **Type Safety**: Compile-time checking for both approaches

### 🚀 Demo Commands

```bash
# 1. Watch SSE events (separate terminal):
curl -N http://127.0.0.1:8080/sse

# 2. Initialize MCP connection:
curl -X POST http://127.0.0.1:8080/messages \\
  -H "Content-Type: application/json" \\
  -d '{{"jsonrpc":"2.0","id":"init","method":"initialize","params":{{"protocolVersion":"2024-11-05","capabilities":{{}},"clientInfo":{{"name":"curl-client","version":"1.0.0"}}}}}}'

# 3. Mark as initialized:
curl -X POST http://127.0.0.1:8080/messages \\
  -H "Content-Type: application/json" \\
  -d '{{"jsonrpc":"2.0","method":"notifications/initialized","params":{{}}}}'

# 4. Test macro tools:
curl -X POST http://127.0.0.1:8080/messages \\
  -H "Content-Type: application/json" \\
  -d '{{"jsonrpc":"2.0","id":"4","method":"tools/call","params":{{"name":"add","arguments":{{"a":15.5,"b":24.3}}}}}}'

# 5. Test context-aware notifications:
curl -X POST http://127.0.0.1:8080/messages \\
  -H "Content-Type: application/json" \\
  -d '{{"jsonrpc":"2.0","id":"5","method":"tools/call","params":{{"name":"notify","arguments":{{"message":"Macro SSE Demo!","count":3}}}}}}'

# 6. Test progress updates:
curl -X POST http://127.0.0.1:8080/messages \\
  -H "Content-Type: application/json" \\
  -d '{{"jsonrpc":"2.0","id":"6","method":"tools/call","params":{{"name":"progress","arguments":{{"operation":"demo_task","steps":4}}}}}}'
```

This demonstrates how to **gradually enhance** macro-based servers with context-aware features!
""")]
  )

when isMainModule:
  # Use server instance created by macro
  
  # Register context-aware tools manually (macro system doesn't support context yet)
  mcpServerInstance.registerToolWithContext(McpTool(
    name: "notify", 
    description: some("Send server notifications via SSE (context-aware)"),
    inputSchema: %*{
      "type": "object",
      "properties": {
        "message": {"type": "string", "description": "Message to broadcast"},
        "count": {"type": "integer", "description": "Number of notifications to send"}
      },
      "required": ["message", "count"]
    }
  ), notifyTool)
  
  mcpServerInstance.registerToolWithContext(McpTool(
    name: "progress",
    description: some("Demonstrate progress updates via SSE (context-aware)"),
    inputSchema: %*{
      "type": "object", 
      "properties": {
        "operation": {"type": "string", "description": "Name of the operation"},
        "steps": {"type": "integer", "description": "Number of steps to process (1-50)"}
      },
      "required": ["steps"]
    }
  ), progressTool)
  
  # Register informational resource
  mcpServerInstance.registerResource(McpResource(
    uri: "sse://macro-info",
    name: "SSE Macro API Demo Info",
    description: some("Information about mixing macro API with context-aware tools"),
    mimeType: some("text/markdown")
  ), serverInfoResource)

  echo "🎯 SSE NOTIFICATIONS WITH MACRO API"
  echo "==================================="
  echo ""
  echo "🔥 This demo showcases MIXED architecture:"
  echo "   📦 Macro API tools (add, multiply, factorial, echo_message)"
  echo "   🏗️  Context-aware tools (notify, progress) manually registered"
  echo ""
  echo "🌟 Key Features:"
  echo "   ✅ Simple macro API for basic tools"
  echo "   ✅ Context-aware tools for SSE notifications"
  echo "   ✅ Best of both worlds approach"
  echo "   ✅ Incremental enhancement capability"
  echo ""
  echo "🚀 Tool Categories:"
  echo "   📱 Macro Tools: add, multiply, factorial, echo_message"
  echo "   📡 Context Tools: notify, progress"
  echo ""
  echo "🌐 Demo Endpoints:"
  echo "   📨 SSE Stream: http://127.0.0.1:8080/sse"
  echo "   📮 Messages: http://127.0.0.1:8080/messages"
  echo ""
  echo "🧪 Quick Test Sequence:"
  echo "   1. Open SSE stream: curl -N http://127.0.0.1:8080/sse"
  echo "   2. Initialize MCP connection (required!)"
  echo "   3. Test macro tool: call 'add' with numbers"
  echo "   4. Test context tool: call 'notify' for SSE events"
  echo "   5. Watch SSE stream for real-time notifications!"
  echo ""
  echo "💡 This demonstrates how to enhance existing macro-based"
  echo "   servers with context-aware features incrementally!"
  echo ""  
  echo "🚀 Starting mixed macro + context server..."
  
  # Start the SSE transport
  mcpServerInstance.runSse(8080, "127.0.0.1")