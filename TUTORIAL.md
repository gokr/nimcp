# The NimCP Tutorial: From Zero to MCP Hero 🚀

Welcome, developer! You're about to learn how to build Model Context Protocol (MCP) servers using NimCP. This tutorial will guide you through creating AI-friendly APIs efficiently.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Chapter 1: Hello, MCP World!](#chapter-1-hello-mcp-world)
3. [Chapter 2: The Macro Magic (Automatic Schema Generation)](#chapter-2-the-macro-magic)
4. [Chapter 3: Adding Personality (Resources and Multiple Tools)](#chapter-3-adding-personality)
5. [Chapter 4: Prompt Engineering](#chapter-4-prompt-engineering)
6. [Chapter 5: HTTP Transport](#chapter-5-http-transport)
7. [Chapter 6: WebSocket Communication](#chapter-6-websocket-communication)
8. [Chapter 7: Authentication & Security](#chapter-7-authentication--security)
9. [Chapter 8: Advanced Features](#chapter-8-advanced-features)
10. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before we start, make sure you have:

- **Nim 2.2.4+**
- **Basic Nim knowledge** (you know what `proc` means and understand `{.async.}`)
- **Development environment** set up for Nim

### Installation

```bash
nimble install nimcp

# Or from source:
git clone https://github.com/gokr/nimcp.git
cd nimcp
nimble install
```

### What is MCP Anyway?

Model Context Protocol is like HTTP for AI agents. It's a standardized way for Large Language Models to interact with external tools, resources, and data sources. Think of it as the universal translator between "I want to do X" (from the AI) and "Here's how you do X" (from your server).

```mermaid
graph LR
    A[LLM Client] -->|JSON-RPC 2.0| B[MCP Server]
    B --> C[Your Tools]
    B --> D[Your Resources]
    B --> E[Your Prompts]
    C --> F[Real World Magic]
    D --> F
    E --> F
```

---

## Chapter 1: Hello, MCP World!

Let's start with a simple echo server to verify your setup works.

### The Manual Way (For Understanding)

Create a file called `my_first_server.nim`:

```nim
import nimcp
import json

# The manual approach - explicit schema definition
let server = newMcpServer("my-first-server", "1.0.0")

# Define our echo tool
let echoTool = McpTool(
  name: "echo",
  description: some("Echoes back whatever you send it"),
  inputSchema: %*{
    "type": "object",
    "properties": {
      "text": {
        "type": "string",
        "description": "The text to echo back"
      }
    },
    "required": ["text"]
  }
)

# The handler function
proc echoHandler(args: JsonNode): McpToolResult =
  let text = args["text"].getStr()
  return McpToolResult(content: @[createTextContent("Echo: " & text)])

# Register our tool
server.registerTool(echoTool, echoHandler)

# Run the server
when isMainModule:
  echo "🚀 Starting echo server..."
  server.runStdio()
```

### Testing Your Creation

```bash
# Compile and run
nim c -r my_first_server.nim

# In another terminal, test it with some JSON-RPC
echo '{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{}}' | ./my_first_server
```

You should see something like:
```json
{"jsonrpc":"2.0","id":"1","result":{"tools":[{"name":"echo","description":"Echoes back whatever you throw at it, like a very polite parrot"}]}}
```

🎉 **Congratulations!** You've created your first MCP server.

### Understanding the Architecture

```mermaid
sequenceDiagram
    participant Client as LLM Client
    participant Server as MCP Server
    participant Handler as Echo Handler

    Client->>Server: tools/list
    Server->>Client: [echo tool info]

    Client->>Server: tools/call "echo" {"text": "Hello"}
    Server->>Handler: process("Hello")
    Handler->>Server: "Echo: Hello"
    Server->>Client: {"content": [{"type": "text", "text": "Echo: Hello"}]}
```

As you can see, writing schemas manually is verbose. Let's learn a better way!

---

## Chapter 2: The Macro Magic

Writing JSON schemas by hand is tedious and error-prone. NimCP's macro system automatically generates schemas from your procedure signatures, making development much faster and more maintainable.

### The Better Way

Create `macro_server.nim`:

```nim
import nimcp
import math, strformat

# The macro way - schemas write themselves!
mcpServer("macro-server", "1.0.0"):

  # Simple addition - no manual schema needed
  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers together
      ## - a: First number
      ## - b: Second number
      return fmt"The sum of {a} and {b} is {a + b}"

  # String manipulation with optional parameters
  mcpTool:
    proc formatText(text: string, uppercase: bool = false, repeat: int = 1): string =
      ## Format text with various options
      ## - text: The text to format
      ## - uppercase: Whether to convert to uppercase
      ## - repeat: How many times to repeat it
      var result = text
      if uppercase:
        result = result.toUpperAscii()

      var finalResult = ""
      for i in 1..repeat:
        finalResult.add(result)
        if i < repeat:
          finalResult.add(" ")

      return finalResult

  # Mathematical calculations
  mcpTool:
    proc calculateCircle(radius: float): string =
      ## Calculate circle properties
      ## - radius: The radius of the circle (must be positive)
      if radius <= 0:
        return "Error: Radius must be positive"

      let area = PI * radius * radius
      let circumference = 2 * PI * radius

      return fmt"Circle with radius {radius}: Area = {area:.2f}, Circumference = {circumference:.2f}"

  # Array/sequence handling
  mcpTool:
    proc findMax(numbers: seq[float]): string =
      ## Find the maximum number in a list
      ## - numbers: List of numbers to search through
      if numbers.len == 0:
        return "Error: Can't find max of empty list"

      let maxNum = max(numbers)
      let maxIndex = numbers.find(maxNum)

      return fmt"Maximum value is {maxNum} at position {maxIndex}"

when isMainModule:
  echo "🎩 Starting the Macro Server..."
  echo "Schemas write themselves!"
  runServer()  # Uses stdio by default
```

### The Magic Revealed

What just happened? The `mcpTool` macro automatically:

1. **Generated the tool name** from the procedure name
2. **Created JSON schema** from parameter types (`float`, `string`, `bool`, `seq[float]`)
3. **Extracted descriptions** from your doc comments
4. **Handled parameter documentation** from the `## - param: description` format
5. **Created type-safe wrappers** that convert JSON to Nim types

```mermaid
graph TD
    A[Your Nim Proc] --> B[mcpTool Macro]
    B --> C[JSON Schema Generation]
    B --> D[Type Conversion Wrapper]
    B --> E[Error Handling]
    C --> F[MCP Tool Registration]
    D --> F
    E --> F
```

### Testing the Magic

```bash
nim c -r macro_server.nim

# Test the addition
echo '{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"add","arguments":{"a":3.14,"b":2.86}}}' | ./macro_server

# Test text formatting
echo '{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"formatText","arguments":{"text":"hello world","uppercase":true,"repeat":3}}}' | ./macro_server
```

From now on, we'll use the macro syntax for all examples - it's much cleaner!

---

## Chapter 3: Adding Personality

Now let's expand our server with multiple tools and resources using the clean macro syntax.

Create `personality_server.nim`:

```nim
import nimcp
import times, strutils, random

mcpServer("personality-server", "1.0.0"):

  # Echo with attitude
  mcpTool:
    proc echo(text: string, attitude: string = "normal"): string =
      ## Echo text with optional attitude adjustment
      ## - text: Text to echo
      ## - attitude: How to deliver the echo (normal, excited, sarcastic)
      let response = case attitude:
        of "excited": "OMG! " & text.toUpperAscii() & "!!!"
        of "sarcastic": "Oh wow, \"" & text & "\". How original."
        else: "Echo: " & text
      return response

  # Current time with formatting options
  mcpTool:
    proc currentTime(format: string = "human"): string =
      ## Get current time in various formats
      ## - format: Time format (iso, human, unix)
      let now = now()
      let timeStr = case format:
        of "iso": $now
        of "unix": $now.toTime().toUnix()
        else: now.format("yyyy-MM-dd HH:mm:ss")
      return "Current time: " & timeStr

  # Random wisdom generator
  mcpTool:
    proc randomWisdom(): string =
      ## Get random programming wisdom
      let wisdoms = [
        "The best code is no code at all.",
        "There are only two hard things in Computer Science: cache invalidation and naming things.",
        "Programming is like writing a book... except if you miss a comma, nothing makes sense."
      ]
      randomize()
      let wisdom = wisdoms[rand(wisdoms.len - 1)]
      return "💡 " & wisdom

  # Resource for server statistics
  mcpResource("stats://server", "Server Statistics", "Server metrics and information"):
    proc getStats(uri: string): string =
      let stats = %*{
        "server_name": "personality-server",
        "version": "1.0.0",
        "tools_registered": 3,
        "uptime": "a few seconds"
      }
      return $stats

when isMainModule:
  echo "🎭 Starting the Personality Server..."
  runServer()
```

---

## Chapter 4: Prompt Engineering

Prompts in MCP are reusable conversation starters that help LLMs understand what you want them to do.

Create `prompt_server.nim`:

```nim
import nimcp
import json, tables, strformat

mcpServer("prompt-server", "1.0.0"):

  # Simple greeting prompt
  mcpPrompt("greeting", "A friendly greeting prompt", @[]):
    proc generateGreeting(name: string, args: Table[string, JsonNode]): seq[McpPromptMessage] =
      let systemMsg = McpPromptMessage(
        role: System,
        content: createTextContent("You are a friendly assistant.")
      )
      let userMsg = McpPromptMessage(
        role: User,
        content: createTextContent("Please greet the user.")
      )
      return @[systemMsg, userMsg]

  # Code review prompt with parameters
  mcpPrompt("code_reviewer", "Code review prompt", @[
    McpPromptArgument(name: "language", description: some("Programming language"), required: some(true))
  ]):
    proc generateCodeReview(name: string, args: Table[string, JsonNode]): seq[McpPromptMessage] =
      let language = args.getOrDefault("language", %"Python").getStr()
      let systemPrompt = fmt"You are an expert {language} code reviewer."

      let systemMsg = McpPromptMessage(
        role: System,
        content: createTextContent(systemPrompt)
      )
      let userMsg = McpPromptMessage(
        role: User,
        content: createTextContent("Please review the following code.")
      )
      return @[systemMsg, userMsg]

when isMainModule:
  echo "🎯 Starting Prompt Server..."
  runServer()
```

---

## Chapter 5: HTTP Transport

HTTP transport lets your MCP server work with web applications and REST clients.

Create `web_server.nim`:

```nim
import nimcp
import math, strformat

mcpServer("web-calculator", "1.0.0"):

  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers via HTTP
      return fmt"Web result: {a} + {b} = {a + b}"

  mcpTool:
    proc power(base: float, exponent: float): string =
      ## Calculate power (base^exponent)
      let result = pow(base, exponent)
      return fmt"Power calculation: {base}^{exponent} = {result}"

  # Resource for mathematical constants
  mcpResource("math://constants", "Mathematical Constants", "Important mathematical constants"):
    proc getConstants(uri: string): string =
      let constants = %*{
        "pi": PI,
        "e": E,
        "golden_ratio": (1.0 + sqrt(5.0)) / 2.0
      }
      return $constants

when isMainModule:
  echo "🌐 Starting Web Calculator Server..."
  echo "Endpoints:"
  echo "- GET  http://127.0.0.1:8080/         # Server info"
  echo "- POST http://127.0.0.1:8080/mcp      # MCP JSON-RPC"

  # Switch from stdio to HTTP
  runServer(HttpTransport(8080, "127.0.0.1"))
```

### Testing Your Web Server

```bash
# Compile and run
nim c -r web_server.nim

# In another terminal, test with curl
curl -X GET http://127.0.0.1:8080/

# List available tools
curl -X POST http://127.0.0.1:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{}}'

# Call the add tool
curl -X POST http://127.0.0.1:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"add","arguments":{"a":42,"b":13}}}'
```

### HTTP vs Stdio

| Feature | Stdio | HTTP |
|---------|-------|------|
| **Complexity** | Simple | Moderate |
| **Web Integration** | No | Yes |
| **Debugging** | Terminal logs | Browser dev tools |
| **Scalability** | One client | Many clients |

---

## Chapter 6: WebSocket Communication

WebSockets enable bidirectional, real-time communication. Perfect for applications that need instant updates or live data feeds.

Create `websocket_server.nim`:

```nim
import nimcp
import math, times, strformat

mcpServer("websocket-server", "1.0.0"):

  mcpTool:
    proc liveAdd(a: float, b: float): string =
      ## Real-time addition
      let timestamp = now().format("HH:mm:ss")
      return fmt"[{timestamp}] Live result: {a} + {b} = {a + b}"

  mcpTool:
    proc serverTime(): string =
      ## Get current server time
      let now = now()
      return fmt"Server time: {now.format('yyyy-MM-dd HH:mm:ss')}"

  # Resource that changes over time
  mcpResource("live://stats", "Live Server Stats", "Real-time server statistics"):
    proc getLiveStats(uri: string): string =
      let stats = %*{
        "current_time": $now(),
        "active_connections": 1,
        "websocket_magic": "operational"
      }
      return $stats

when isMainModule:
  echo "⚡ Starting WebSocket Server..."
  echo "WebSocket endpoint: ws://127.0.0.1:8080/"
  echo ""
  echo "Test with browser console:"
  echo """
const ws = new WebSocket('ws://127.0.0.1:8080/');
ws.onopen = () => {
  ws.send('{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{}}');
};
ws.onmessage = (event) => {
  console.log('Response:', JSON.parse(event.data));
};
"""

  # WebSocket transport
  runServer(WebSocketTransport(8080, "127.0.0.1"))
```

### WebSocket Communication Flow

```mermaid
sequenceDiagram
    participant Client as WebSocket Client
    participant Server as MCP Server
    participant Tool as Calculator Tool

    Client->>Server: WebSocket Connection
    Server->>Client: Connection Established

    Client->>Server: {"method": "tools/list"}
    Server->>Client: {"result": {"tools": [...]}}

    Client->>Server: {"method": "tools/call", "params": {"name": "liveAdd", "arguments": {"a": 5, "b": 3}}}
    Server->>Tool: calculate(5, 3)
    Tool->>Server: "[12:34:56] Live result: 5 + 3 = 8"
    Server->>Client: {"result": {"content": [...]}}

    Note over Client,Server: Connection stays open for more requests
```

### Testing WebSocket Magic

You can test WebSockets using a browser console:

```javascript
// Open browser console and run this
const ws = new WebSocket('ws://127.0.0.1:8080/');

ws.onopen = function() {
    console.log('Connected to WebSocket server!');

    // List available tools
    ws.send(JSON.stringify({
        "jsonrpc": "2.0",
        "id": "1",
        "method": "tools/list",
        "params": {}
    }));
};

ws.onmessage = function(event) {
    const response = JSON.parse(event.data);
    console.log('Server response:', response);
};

ws.onerror = function(error) {
    console.error('WebSocket error:', error);
};

// Call a tool
function callTool(name, args) {
    ws.send(JSON.stringify({
        "jsonrpc": "2.0",
        "id": Math.random().toString(),
        "method": "tools/call",
        "params": {
            "name": name,
            "arguments": args
        }
    }));
}

// Try it out!
callTool("liveAdd", {"a": 42, "b": 13});
```

---

## Chapter 7: Authentication & Security

Time to add security to your server. Authentication ensures only authorized clients can access your tools.

Create `secure_server.nim`:

```nim
import nimcp
import math, strformat, base64, strutils

mcpServer("secure-server", "1.0.0"):

  mcpTool:
    proc secureAdd(a: float, b: float): string =
      ## Secure addition with authentication
      return fmt"🔒 Secure result: {a} + {b} = {a + b}"

  mcpTool:
    proc adminOnly(secret: string): string =
      ## Admin-only function
      if secret != "admin123":
        return "❌ Access denied!"
      return "🎉 Welcome, admin!"

  mcpTool:
    proc encodeMessage(message: string): string =
      ## Base64 encode a message
      let encoded = encode(message)
      return fmt"🔐 Encoded: {encoded}"

  mcpTool:
    proc decodeMessage(encoded: string): string =
      ## Base64 decode a message
      try:
        let decoded = decode(encoded)
        return fmt"🔓 Decoded: {decoded}"
      except:
        return "❌ Invalid encoded message (or you broke the decoder, either way...)"

when isMainModule:
  echo "🔐 Starting Secure Calculator Server..."
  echo "Now with 37% more security theater!"
  echo ""
  echo "Authentication required!"
  echo "Use Bearer token: 'super-secret-token-123'"
  echo ""
  echo "Test with curl:"
  echo """curl -X POST http://127.0.0.1:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer super-secret-token-123" \
  -d '{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{}}'"""
  echo ""

  # Create HTTP transport with authentication
  let transport = HttpTransport(8080, "127.0.0.1")

  # Add authentication middleware
  transport.addAuthenticator(proc(token: string): bool =
    # In real life, you'd check this against a database or JWT
    # But for now, we'll just check for our super secure token
    return token == "super-secret-token-123"
  )

  runServer(transport)
```

### Authentication Flow

```mermaid
sequenceDiagram
    participant Client
    participant Auth as Auth Middleware
    participant Server as MCP Server

    Client->>Auth: Request with Bearer token
    Auth->>Auth: Validate token

    alt Token valid
        Auth->>Server: Forward request
        Server->>Auth: Response
        Auth->>Client: Response
    else Token invalid
        Auth->>Client: 401 Unauthorized
    end
```

### Advanced Security Example

For production use, here's a more robust authentication setup:

```nim
import nimcp, jwt, times, json

mcpServer("production-server", "1.0.0"):

  mcpTool:
    proc sensitiveOperation(data: string): string =
      ## This tool requires authentication
      return fmt"Processing sensitive data: {data.len} characters"

when isMainModule:
  let transport = HttpTransport(8080, "127.0.0.1")

  # JWT-based authentication
  transport.addAuthenticator(proc(token: string): bool =
    try:
      let jwt = token.parseJWT()
      let now = getTime().toUnix()

      # Check if token is expired
      if jwt.claims.hasKey("exp") and jwt.claims["exp"].getInt() < now:
        return false

      # Check issuer
      if jwt.claims.getOrDefault("iss", %"").getStr() != "your-auth-server":
        return false

      # Verify signature (you'd use your actual secret here)
      return jwt.verify("your-secret-key")
    except:
      return false
  )

  runServer(transport)
```

### Try This! 🧪

1. **Add rate limiting**: Prevent abuse with request throttling
2. **Implement API keys**: Different keys for different access levels
3. **Add request logging**: Track who's doing what

---

## Chapter 8: Advanced Features

Ready for advanced features? Let's explore middleware, context, and concurrency.

### Middleware Magic

Create `advanced_server.nim`:

```nim
import nimcp
import times, json, strformat, asyncdispatch

mcpServer("advanced-server", "1.0.0"):

  # Context-aware tool that tracks request information
  mcpToolWithContext:
    proc contextualAdd(ctx: McpRequestContext, a: float, b: float): string =
      ## Addition with full context awareness
      ctx.logMessage("info", fmt"Processing addition: {a} + {b}")
      ctx.reportProgress("Calculating...", 0.5)

      # Simulate some work
      sleep(100)

      let result = a + b
      ctx.reportProgress("Complete!", 1.0)
      ctx.logMessage("info", fmt"Result calculated: {result}")

      return fmt"Context-aware result: {a} + {b} = {result}"

  # Async tool for concurrent operations
  mcpTool:
    proc asyncCalculation(n: int): string =
      ## Perform calculation asynchronously
      proc heavyCalculation(): Future[int] {.async.} =
        # Simulate heavy computation
        await sleepAsync(1000)
        return n * n

      let future = heavyCalculation()
      let result = waitFor future
      return fmt"Async result: {n}² = {result}"

  # Resource with progress tracking
  mcpResourceWithContext("data://processing", "Data Processing", "Process data with progress updates"):
    proc processData(ctx: McpRequestContext, uri: string): string =
      ctx.reportProgress("Starting data processing...", 0.0)
      sleep(200)

      ctx.reportProgress("Processing chunk 1/3...", 0.33)
      sleep(200)

      ctx.reportProgress("Processing chunk 2/3...", 0.66)
      sleep(200)

      ctx.reportProgress("Finalizing...", 0.9)
      sleep(100)

      ctx.reportProgress("Complete!", 1.0)

      let result = %*{
        "status": "completed",
        "processed_items": 42,
        "processing_time": "0.7 seconds",
        "efficiency": "maximum"
      }

      return $result

when isMainModule:
  echo "🚀 Starting Advanced Server..."
  echo "Now with context awareness, progress tracking, and async operations!"
  echo ""
  echo "Features:"
  echo "- Request context tracking"
  echo "- Progress reporting"
  echo "- Async operations"
  echo "- Detailed logging"
  echo "- Middleware support"
  echo ""

  # Add custom middleware
  let server = mcpServerInstance

  # Request timing middleware
  server.addMiddleware(proc(req: McpRequest, next: proc(): McpResponse): McpResponse =
    let startTime = cpuTime()
    let response = next()
    let duration = cpuTime() - startTime

    echo fmt"Request {req.id} took {duration:.3f}s"
    return response
  )

  # Request logging middleware
  server.addMiddleware(proc(req: McpRequest, next: proc(): McpResponse): McpResponse =
    echo fmt"📝 {req.`method`} request from client"
    let response = next()
    echo fmt"✅ Response sent with status: {response.error.isNone}"
    return response
  )

  runServer()
```

### Concurrent Processing

For handling multiple requests efficiently:

```nim
import nimcp, taskpools

mcpServer("concurrent-server", "1.0.0"):

  mcpTool:
    proc parallelSum(numbers: seq[float]): string =
      ## Calculate sum using parallel processing
      if numbers.len == 0:
        return "Error: Empty list"

      # Split work across multiple threads
      let tp = Taskpool.new(num_threads = 4)
      defer: tp.shutdown()

      let chunkSize = max(1, numbers.len div 4)
      var futures: seq[FlowVar[float]] = @[]

      for i in countup(0, numbers.len - 1, chunkSize):
        let chunk = numbers[i..<min(i + chunkSize, numbers.len)]
        futures.add(tp.spawn(proc(): float =
          var sum = 0.0
          for num in chunk:
            sum += num
          return sum
        ))

      var totalSum = 0.0
      for future in futures:
        totalSum += ^future

      return fmt"Parallel sum of {numbers.len} numbers: {totalSum}"

when isMainModule:
  runServer()
```

### Error Handling and Resilience

```nim
import nimcp

mcpServer("resilient-server", "1.0.0"):

  mcpTool:
    proc robustDivision(a: float, b: float): string =
      ## Division with comprehensive error handling
      try:
        if b == 0.0:
          raise newException(DivByZeroError, "Cannot divide by zero (math still works)")

        if a.isNaN or b.isNaN:
          raise newException(ValueError, "NaN values not supported (we're not that advanced)")

        if a.isInf or b.isInf:
          raise newException(ValueError, "Infinity is too big for our calculator")

        let result = a / b
        return fmt"Robust division: {a} ÷ {b} = {result}"

      except DivByZeroError as e:
        return fmt"❌ Division Error: {e.msg}"
      except ValueError as e:
        return fmt"❌ Value Error: {e.msg}"
      except Exception as e:
        return fmt"❌ Unexpected Error: {e.msg} (this shouldn't happen, but here we are)"

when isMainModule:
  runServer()
```

### Try This! 🧪

1. **Add caching middleware**: Cache expensive calculations
2. **Implement circuit breakers**: Fail fast when external services are down
3. **Create health checks**: Monitor server health and dependencies

---

## Troubleshooting

### Common Issues and Solutions

#### 1. "My server won't start!"

**Symptoms**: Server crashes immediately or won't bind to port

**Solutions**:
```bash
# Check if port is already in use
lsof -i :8080

# Try a different port
runServer(HttpTransport(8081, "127.0.0.1"))

# Check for compilation errors
nim c --verbosity:2 your_server.nim
```

#### 2. "Tools aren't being registered!"

**Symptoms**: `tools/list` returns empty array

**Common causes**:
- Forgot to call `runServer()` in `when isMainModule`
- Macro syntax errors
- Missing imports

**Debug with**:
```nim
# Add debug output
echo "Registering tool: ", toolName
server.registerTool(tool, handler)
echo "Tools registered: ", server.listTools().len
```

#### 3. "JSON schema validation fails!"

**Symptoms**: Tools reject valid-looking arguments

**Solutions**:
```nim
# Check your schema matches your expectations
echo "Generated schema: ", tool.inputSchema

# Validate manually
import json
let testArgs = %*{"a": 5.0, "b": 3.0}
echo "Test args: ", testArgs
```

#### 4. "WebSocket connections drop!"

**Symptoms**: Clients disconnect unexpectedly

**Common causes**:
- Firewall blocking WebSocket upgrades
- Proxy servers not configured for WebSockets
- Client-side timeout issues

**Solutions**:
```nim
# Add connection logging
transport.onConnect = proc(client: WebSocketClient) =
  echo "Client connected: ", client.id

transport.onDisconnect = proc(client: WebSocketClient) =
  echo "Client disconnected: ", client.id
```

### Debugging Tools

#### Enable Verbose Logging

```nim
import nimcp/logging

# Set log level
setLogLevel(LogLevel.Debug)

# Add custom logging
mcpTool:
  proc debugTool(input: string): string =
    logDebug("Processing input: " & input)
    let result = "Processed: " & input
    logDebug("Generated result: " & result)
    return result
```

#### Test with curl

```bash
# Test tool listing
curl -X POST http://127.0.0.1:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"test","method":"tools/list","params":{}}'

# Test tool calling with verbose output
curl -v -X POST http://127.0.0.1:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"test","method":"tools/call","params":{"name":"add","arguments":{"a":1,"b":2}}}'
```

#### Validate JSON-RPC

Use online JSON-RPC validators or:

```nim
import json

proc validateJsonRpc(request: string): bool =
  try:
    let parsed = parseJson(request)
    return parsed.hasKey("jsonrpc") and
           parsed.hasKey("method") and
           parsed.hasKey("id")
  except:
    return false
```

### Performance Tips

1. **Use async for I/O operations**
2. **Cache expensive calculations**
3. **Limit concurrent connections**
4. **Profile with `--profiler:on`**
5. **Monitor memory usage**

### Getting Help

- **Check the examples**: `examples/` directory has working code
- **Read CLAUDE.md**: Coding guidelines and patterns
- **Run tests**: `nimble test` to verify your setup
- **Enable debug logging**: See what's happening under the hood

---

## Conclusion: You're Now an MCP Wizard! 🧙‍♂️

Congratulations! You've journeyed from a simple echo server to building production-ready MCP servers with authentication, real-time communication, and advanced features. You're now equipped to:

- ✅ Build MCP servers using both manual and macro APIs
- ✅ Handle stdio, HTTP, and WebSocket transports
- ✅ Implement authentication and security
- ✅ Use context-aware tools and progress tracking
- ✅ Debug issues and optimize performance
- ✅ Write tests and maintain code quality

### What's Next?

1. **Build something cool**: Create an MCP server for your favorite API
2. **Contribute to NimCP**: Found a bug? Have an idea? PRs welcome!
3. **Share your creation**: Show off your MCP server to the community
4. **Keep learning**: The MCP specification is evolving - stay updated!

### Final Words

Remember: the best MCP server is the one that actually gets used. Don't over-engineer, don't under-test, and always remember that somewhere, an AI is trying to use your API to help a human solve a problem.

Now go forth and build amazing things! 🚀

---

*"Any sufficiently advanced MCP server is indistinguishable from magic."* - Arthur C. Clarke (if he were a Nim programmer)

### Resources

- **NimCP Repository**: [github.com/gokr/nimcp](https://github.com/gokr/nimcp)
- **MCP Specification**: [modelcontextprotocol.io](https://modelcontextprotocol.io)
- **Nim Documentation**: [nim-lang.org](https://nim-lang.org)
- **Examples Directory**: Check out all the working examples in `examples/`
- **CLAUDE.md**: Coding guidelines and best practices

Happy coding! 🎉


