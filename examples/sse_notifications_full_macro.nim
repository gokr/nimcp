## SSE Notifications with Full Macro API - Pure macro approach
## Demonstrates the enhanced macro system with automatic context detection
## All tools defined using mcpTool macro with automatic registration

import ../src/nimcp
import json, math, strformat, options, times, os

# Create server using enhanced macro API with automatic context detection
mcpServer("sse-notifications-full-macro", "1.0.0"):
  
  # Regular tools (no context parameter) - auto-detected as regular tools
  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers together
      return fmt"Result: {a + b}"
  
  mcpTool:
    proc multiply(x: int, y: int): string =
      ## Multiply two integers
      return fmt"Result: {x * y}"
  
  mcpTool:
    proc factorial(n: int): string =
      ## Calculate factorial of a number
      if n < 0:
        return "Error: Factorial not defined for negative numbers"
      elif n == 0 or n == 1:
        return "Result: 1"
      else:
        var res = 1
        for i in 2..n:
          res *= i
        return fmt"Result: {res}"
  
  # Context-aware tools (with McpRequestContext parameter) - auto-detected as context-aware
  mcpTool:
    proc notify(ctx: McpRequestContext, message: string, count: int): string =
      ## Send server notifications via SSE transport (context-aware)
      echo fmt"📡 Sending {count} notifications with message: '{message}'"
      
      # Access SSE transport from server via request context
      let server = ctx.getServer()
      if server == nil or not server.transport.isSome:
        return "Error: No transport available"
      var transport = server.transport.get()
      
      # Send actual SSE notifications
      for i in 1..count:
        let notificationData = %*{
          "type": "full_macro_notification",
          "message": fmt"{message} (#{i}/{count})",
          "timestamp": $now(),
          "index": i,
          "total": count,
          "source": "full_macro_api"
        }
        
        transport.broadcastMessage(notificationData)
        echo fmt"   📨 Sent notification {i}/{count} via SSE"
        
        # Small delay between notifications for demonstration
        if i < count:
          sleep(300)
      
      return fmt"Sent {count} notifications via SSE: '{message}'"
  
  mcpTool:
    proc progress(ctx: McpRequestContext, operation: string, steps: int): string =
      ## Send progress updates via SSE transport (context-aware)
      if steps <= 0 or steps > 30:
        return "Error: Steps must be between 1 and 30"
      
      echo fmt"🔄 Starting {operation} with {steps} steps"
      
      # Access SSE transport from server via request context
      let server = ctx.getServer()
      if server == nil or not server.transport.isSome:
        return "Error: No transport available"
      var transport = server.transport.get()
      
      # Send start notification
      let startData = %*{
        "type": "full_macro_progress_start",
        "operation": operation,
        "total_steps": steps,
        "timestamp": $now(),
        "source": "full_macro_api"
      }
      transport.broadcastMessage(startData)
      echo "   🚀 Sent start notification via SSE"
      
      for step in 1..steps:
        sleep(600)  # Simulate work
        let percentage = (step * 100) div steps
        
        # Send real progress updates via SSE
        let progressData = %*{
          "type": "full_macro_progress",
          "operation": operation,
          "current_step": step,
          "total_steps": steps,
          "percentage": percentage,
          "timestamp": $now(),
          "source": "full_macro_api"
        }
        transport.broadcastMessage(progressData)
        echo fmt"   📊 Progress via SSE: {step}/{steps} ({percentage}%)"
      
      # Send completion notification
      let completeData = %*{
          "type": "full_macro_progress_complete",
          "operation": operation,
          "final_steps": steps,
          "timestamp": $now(),
          "source": "full_macro_api"
      }
      transport.broadcastMessage(completeData)
      echo "   ✅ Sent completion notification via SSE"
      
      return fmt"Operation '{operation}' completed with {steps} steps and real-time SSE updates"
  
  mcpTool:
    proc broadcast(ctx: McpRequestContext, event_type: string, data: string): string =
      ## Broadcast custom events via SSE (context-aware)
      echo fmt"📻 Broadcasting event type: '{event_type}'"
      
      # Access SSE transport from server via request context
      let server = ctx.getServer()
      if server == nil or not server.transport.isSome:
        return "Error: No transport available"
      var transport = server.transport.get()
      
      let eventData = %*{
        "type": event_type,
        "data": data,
        "timestamp": $now(),
        "source": "full_macro_api",
        "broadcast_id": $now().toTime().toUnix()
      }
      transport.broadcastMessage(eventData)
      echo fmt"   📡 Broadcasted event '{event_type}' via SSE"
      return fmt"Event '{event_type}' broadcasted successfully"

proc serverInfoResource(uri: string): McpResourceContents {.gcsafe.} =
  ## Resource showing full macro API integration
  let currentTime = now()
  
  return McpResourceContents(
    uri: uri,
    content: @[createTextContent(fmt"""# SSE Notifications with Full Macro API

## Pure Macro Architecture ✨

This example demonstrates **100% macro-based SSE integration** with automatic context detection:

### 🎯 Current Status
- **Time**: {currentTime}
- **Transport**: SSE (Server-Sent Events)  
- **API Style**: Pure Macro with Auto-Detection
- **Context Detection**: Automatic based on first parameter

### 🏗️ Architecture Overview

**All tools defined with `mcpTool` macro:**

```nim
# Regular tool (auto-detected - no context parameter)
mcpTool:
  proc add(a: float, b: float): string =
    return fmt"Result: {{a + b}}"

# Context-aware tool (auto-detected - first param is McpRequestContext)
mcpTool:
  proc notify(ctx: McpRequestContext, message: string, count: int): string =
    let server = ctx.getServer()
    let transport = server.getCustomData("sse_transport", SseTransport)
    transport.broadcastMessage(data)
    # ...
```

### 🔍 Automatic Detection Logic

The enhanced macro system automatically detects tool type:

1. **Examines first parameter** of proc definition
2. **If first param is `McpRequestContext`** → Context-aware tool
3. **Otherwise** → Regular tool
4. **Generates appropriate wrapper** and registration call
5. **Adjusts JSON schema** to exclude context parameter

### 📦 Available Tools

**Regular Tools** (auto-generated):
- `add` - Add two numbers (simple macro)
- `multiply` - Multiply integers (simple macro)  
- `factorial` - Calculate factorial (simple macro)

**Context-Aware Tools** (auto-generated with context):
- `notify` - Send SSE notifications
- `progress` - Stream progress updates
- `broadcast` - Custom event broadcasting

### 📡 SSE Event Examples

**Notifications**:
```javascript
{{
  "type": "full_macro_notification",
  "message": "Hello! (#1/3)",
  "timestamp": "{currentTime}",
  "source": "full_macro_api"
}}
```

**Progress Updates**:
```javascript
{{
  "type": "full_macro_progress",
  "operation": "data_processing",
  "current_step": 2,
  "total_steps": 5,
  "percentage": 40,
  "source": "full_macro_api"
}}
```

**Custom Events**:
```javascript
{{
  "type": "user_defined_event",
  "data": "Custom payload",
  "broadcast_id": "1641234567",
  "source": "full_macro_api"
}}
```

### ✅ Key Benefits

**Developer Experience**:
- 🎯 **Zero boilerplate** - No manual registration
- 🔍 **Automatic detection** - Context type inferred from signature
- 📦 **Unified API** - Same `mcpTool` macro for both types
- 🛡️ **Type safety** - Compile-time validation

**Architecture**:
- 🏗️ **Clean separation** - Regular vs context-aware tools
- 🔄 **Incremental** - Add context to existing tools easily
- 📊 **Schema generation** - Automatic JSON schema (context excluded)
- 🚀 **Performance** - No runtime overhead

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

# 4. Test regular macro tool:
curl -X POST http://127.0.0.1:8080/messages \\
  -H "Content-Type: application/json" \\
  -d '{{"jsonrpc":"2.0","id":"4","method":"tools/call","params":{{"name":"add","arguments":{{"a":25.5,"b":14.5}}}}}}'

# 5. Test context-aware macro tool:
curl -X POST http://127.0.0.1:8080/messages \\
  -H "Content-Type: application/json" \\
  -d '{{"jsonrpc":"2.0","id":"5","method":"tools/call","params":{{"name":"notify","arguments":{{"message":"Full Macro SSE!","count":3}}}}}}'

# 6. Test progress streaming:
curl -X POST http://127.0.0.1:8080/messages \\
  -H "Content-Type: application/json" \\
  -d '{{"jsonrpc":"2.0","id":"6","method":"tools/call","params":{{"name":"progress","arguments":{{"operation":"macro_demo","steps":4}}}}}}'

# 7. Test custom broadcasting:
curl -X POST http://127.0.0.1:8080/messages \\
  -H "Content-Type: application/json" \\
  -d '{{"jsonrpc":"2.0","id":"7","method":"tools/call","params":{{"name":"broadcast","arguments":{{"event_type":"custom_alert","data":"System status update"}}}}}}'
```

### 🎉 Result

**Perfect macro-based SSE integration** with zero manual registration!

The macro system automatically:
- ✅ Detects context-aware tools
- ✅ Generates appropriate wrappers  
- ✅ Registers with correct method
- ✅ Creates proper JSON schemas
- ✅ Enables real-time SSE notifications

This is the **ideal developer experience** for MCP servers with SSE!
""")]
  )
  
# Will use SSE transport - no manual setup needed with new system 

# Register informational resource
mcpServerInstance.registerResource(McpResource(
  uri: "sse://full-macro-info",
  name: "Full Macro SSE Demo Info",
  description: some("Information about pure macro API with automatic context detection"),
  mimeType: some("text/markdown")
), serverInfoResource)

echo "🎯 SSE NOTIFICATIONS WITH FULL MACRO API"
echo "========================================"
echo ""
echo "🔥 This demo showcases PURE MACRO architecture:"
echo "   ✨ 100% macro-based tool definitions"
echo "   🔍 Automatic context detection"
echo "   📦 Zero manual registration needed"
echo ""
echo "🌟 Enhanced Macro Features:"
echo "   ✅ Auto-detects McpRequestContext parameter"
echo "   ✅ Generates context-aware vs regular wrappers"
echo "   ✅ Uses registerToolWithContext() automatically"
echo "   ✅ Excludes context from JSON schema"
echo ""
echo "🚀 All Tool Types:"
echo "   📱 Regular: add, multiply, factorial"
echo "   📡 Context-Aware: notify, progress, broadcast"
echo ""
echo "🌐 Demo Endpoints:"
echo "   📨 SSE Stream: http://127.0.0.1:8080/sse"
echo "   📮 Messages: http://127.0.0.1:8080/messages"
echo ""
echo "🎉 Key Innovation:"
echo "   Same 'mcpTool' macro works for both regular and context-aware tools!"
echo "   The macro automatically detects tool type and handles registration."
echo ""
echo "🧪 Test both types:"
echo "   • Call 'add' for simple macro functionality"
echo "   • Call 'notify' for SSE real-time events"
echo "   • Watch SSE stream to see live notifications!"
echo ""
echo "🚀 Starting pure macro SSE server..."

# Start the SSE transport
mcpServerInstance.runSse(8080, "127.0.0.1")