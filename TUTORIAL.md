# The NimCP Tutorial: From Zero to MCP Hero 🚀

*Or: How I Learned to Stop Worrying and Love the Model Context Protocol*

Welcome, brave developer! You're about to embark on a journey through the mystical realm of Model Context Protocol (MCP) servers using NimCP. Think of this as your field guide to building AI-friendly APIs that don't make you want to throw your keyboard out the window.

## Table of Contents

1. [Prerequisites: The "You Must Be This Tall to Ride" Section](#prerequisites)
2. [Chapter 1: Hello, MCP World! (The Obligatory Echo Server)](#chapter-1-hello-mcp-world)
3. [Chapter 2: Adding Some Personality (Resources and Multiple Tools)](#chapter-2-adding-some-personality)
4. [Chapter 3: The Macro Magic Show (Automatic Schema Generation)](#chapter-3-the-macro-magic-show)
5. [Chapter 4: Prompt Engineering for Fun and Profit](#chapter-4-prompt-engineering)
6. [Chapter 5: Breaking Free from Stdio Prison (HTTP Transport)](#chapter-5-breaking-free-from-stdio-prison)
7. [Chapter 6: WebSocket Wizardry (Real-time Communication)](#chapter-6-websocket-wizardry)
8. [Chapter 7: Fort Knox Mode (Authentication & Security)](#chapter-7-fort-knox-mode)
9. [Chapter 8: The Advanced Stuff (Middleware, Context, and Concurrency)](#chapter-8-the-advanced-stuff)
10. [Troubleshooting: When Things Go Sideways](#troubleshooting)

---

## Prerequisites

Before we dive into the deep end, make sure you have:

- **Nim 2.2.4+** (because we're not savages using ancient compilers)
- **Basic Nim knowledge** (you know what `proc` means and don't panic at the sight of `{.async.}`)
- **A sense of humor** (optional but highly recommended for surviving this tutorial)
- **Coffee/Tea/Energy Drink** (mandatory for any serious programming session)

### Installation

```bash
# The moment of truth
nimble install nimcp

# Or if you're feeling adventurous and want the bleeding edge:
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

*"In the beginning was the Echo, and the Echo was with the Server, and the Echo was good."*

Let's start with the programming equivalent of "Hello, World!" - an echo server that proves your setup works and doesn't immediately crash and burn.

### The Simplest Possible MCP Server

Create a file called `my_first_server.nim`:

```nim
import nimcp
import json

# The manual way - like assembling IKEA furniture with the instructions
let server = newMcpServer("my-first-server", "1.0.0")

# Define our echo tool (because parrots are the best programmers)
let echoTool = McpTool(
  name: "echo",
  description: some("Echoes back whatever you throw at it, like a very polite parrot"),
  inputSchema: %*{
    "type": "object",
    "properties": {
      "text": {
        "type": "string", 
        "description": "The text to echo back (we promise not to judge)"
      }
    },
    "required": ["text"]
  }
)

# The handler - where the magic happens (spoiler: it's not very magical)
proc echoHandler(args: JsonNode): McpToolResult =
  let text = args["text"].getStr()
  return McpToolResult(content: @[createTextContent("Echo: " & text)])

# Register our tool (like signing up for a gym membership, but actually useful)
server.registerTool(echoTool, echoHandler)

# Run the server (the moment of truth)
when isMainModule:
  echo "🚀 Starting the world's most sophisticated echo chamber..."
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

🎉 **Congratulations!** You've just created your first MCP server. It's not going to win any awards, but it works, and that's what matters.

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

### Try This! 🧪

1. **Modify the echo**: Make it SHOUT EVERYTHING BACK IN CAPS
2. **Add validation**: Reject empty strings with a snarky message
3. **Count characters**: Return both the echo and character count

---

## Chapter 2: Adding Some Personality

*"One tool is a hobby, two tools is a collection, three tools is an addiction."*

Let's expand our server with multiple tools and a resource. Think of this as upgrading from a Swiss Army knife with just a blade to one with all the gadgets you'll never use but feel good having.

Create `personality_server.nim`:

```nim
import nimcp
import json, times, strutils, random

let server = newMcpServer("personality-server", "1.0.0")

# Tool 1: The Improved Echo (now with 50% more personality!)
let echoTool = McpTool(
  name: "echo",
  description: some("Echoes text with optional attitude adjustment"),
  inputSchema: %*{
    "type": "object",
    "properties": {
      "text": {"type": "string", "description": "Text to echo"},
      "attitude": {
        "type": "string", 
        "enum": ["normal", "excited", "sarcastic", "confused"],
        "description": "How to deliver the echo"
      }
    },
    "required": ["text"]
  }
)

proc echoHandler(args: JsonNode): McpToolResult =
  let text = args["text"].getStr()
  let attitude = args.getOrDefault("attitude", %"normal").getStr()
  
  let response = case attitude:
    of "excited": "OMG! " & text.toUpperAscii() & "!!!"
    of "sarcastic": "Oh wow, \"" & text & "\". How original."
    of "confused": "Um... " & text & "? I think?"
    else: "Echo: " & text
  
  return McpToolResult(content: @[createTextContent(response)])

server.registerTool(echoTool, echoHandler)

# Tool 2: Current Time (because someone always asks "what time is it?")
let timeTool = McpTool(
  name: "current_time",
  description: some("Tells you what time it is (shocking, I know)"),
  inputSchema: %*{
    "type": "object",
    "properties": {
      "format": {
        "type": "string",
        "enum": ["iso", "human", "unix"],
        "description": "Time format preference"
      }
    }
  }
)

proc timeHandler(args: JsonNode): McpToolResult =
  let format = args.getOrDefault("format", %"human").getStr()
  let now = now()
  
  let timeStr = case format:
    of "iso": $now
    of "unix": $now.toTime().toUnix()
    else: now.format("yyyy-MM-dd HH:mm:ss")
  
  return McpToolResult(content: @[createTextContent("Current time: " & timeStr)])

server.registerTool(timeTool, timeHandler)

# Tool 3: Random Wisdom Generator (because why not?)
let wisdomTool = McpTool(
  name: "random_wisdom",
  description: some("Dispenses questionable wisdom from the depths of the internet"),
  inputSchema: %*{"type": "object", "properties": {}}
)

proc wisdomHandler(args: JsonNode): McpToolResult =
  let wisdoms = [
    "The best code is no code at all.",
    "There are only two hard things in Computer Science: cache invalidation and naming things.",
    "It works on my machine ¯\\_(ツ)_/¯",
    "99 little bugs in the code, 99 little bugs. Take one down, patch it around, 117 little bugs in the code.",
    "Programming is like writing a book... except if you miss out a single comma on page 126, the whole thing makes no sense."
  ]
  
  randomize()
  let wisdom = wisdoms[rand(wisdoms.len - 1)]
  return McpToolResult(content: @[createTextContent("💡 " & wisdom)])

server.registerTool(wisdomTool, wisdomHandler)

# Resource: Server Stats (because everyone loves metrics)
let statsResource = McpResource(
  uri: "stats://server",
  name: "Server Statistics",
  description: some("Riveting statistics about this server")
)

proc statsHandler(uri: string): McpResourceContents =
  let stats = %*{
    "server_name": "personality-server",
    "version": "1.0.0",
    "uptime_seconds": 42,  # TODO: implement actual uptime tracking
    "tools_registered": 3,
    "coffee_consumed": "insufficient",
    "bugs_fixed": "more than created (hopefully)",
    "developer_sanity": "questionable"
  }
  
  return McpResourceContents(
    uri: uri,
    content: @[createTextContent($stats)]
  )

server.registerResource(statsResource, statsHandler)

when isMainModule:
  echo "🎭 Starting the Personality Server..."
  echo "Now with 100% more attitude and 73% more random numbers!"
  server.runStdio()
```

### Testing the Personality

```bash
nim c -r personality_server.nim

# Test the sarcastic echo
echo '{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"echo","arguments":{"text":"Hello world","attitude":"sarcastic"}}}' | ./personality_server

# Get some wisdom
echo '{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"random_wisdom","arguments":{}}}' | ./personality_server

# Check server stats
echo '{"jsonrpc":"2.0","id":"3","method":"resources/read","params":{"uri":"stats://server"}}' | ./personality_server
```

### Try This! 🧪

1. **Add a joke tool**: Return random programming jokes
2. **Create a calculator**: Basic math operations with witty error messages
3. **Build a compliment generator**: Because everyone needs encouragement

---

## Chapter 4: Prompt Engineering for Fun and Profit

*"Give a developer a prompt, and they'll build for a day. Teach a developer to prompt, and they'll automate everything."*

Prompts in MCP are like templates for AI interactions - they're reusable conversation starters that help LLMs understand what you want them to do. Think of them as the "mad libs" of the AI world.

Create `prompt_master.nim`:

```nim
import nimcp
import json, tables, strformat

mcpServer("prompt-master", "1.0.0"):

  # Simple prompt without arguments
  mcpPrompt("greeting", "A friendly greeting prompt", @[]):
    proc generateGreeting(name: string, args: Table[string, JsonNode]): seq[McpPromptMessage] =
      let systemMsg = McpPromptMessage(
        role: System,
        content: createTextContent("You are a friendly assistant who greets users warmly.")
      )

      let userMsg = McpPromptMessage(
        role: User,
        content: createTextContent("Please greet the user in a friendly manner.")
      )

      return @[systemMsg, userMsg]

  # Prompt with arguments for customization
  mcpPrompt("code_reviewer", "Code review prompt with customizable focus", @[
    McpPromptArgument(name: "language", description: some("Programming language"), required: some(true)),
    McpPromptArgument(name: "focus", description: some("Review focus area"), required: some(false)),
    McpPromptArgument(name: "strictness", description: some("Review strictness level"), required: some(false))
  ]):
    proc generateCodeReview(name: string, args: Table[string, JsonNode]): seq[McpPromptMessage] =
      let language = args.getOrDefault("language", %"Python").getStr()
      let focus = args.getOrDefault("focus", %"general").getStr()
      let strictness = args.getOrDefault("strictness", %"moderate").getStr()

      let systemPrompt = fmt"""You are an expert {language} code reviewer.
Focus on: {focus}
Review strictness: {strictness}

Provide constructive feedback that helps developers improve their code quality."""

      let systemMsg = McpPromptMessage(
        role: System,
        content: createTextContent(systemPrompt)
      )

      let userMsg = McpPromptMessage(
        role: User,
        content: createTextContent("Please review the following code and provide feedback.")
      )

      return @[systemMsg, userMsg]

  # Advanced prompt with context awareness
  mcpPromptWithContext("debug_helper", "Debugging assistant with context", @[
    McpPromptArgument(name: "error_type", description: some("Type of error encountered"), required: some(true)),
    McpPromptArgument(name: "urgency", description: some("How urgent is this bug?"), required: some(false))
  ]):
    proc generateDebugPrompt(ctx: McpRequestContext, name: string, args: Table[string, JsonNode]): seq[McpPromptMessage] =
      let errorType = args.getOrDefault("error_type", %"runtime").getStr()
      let urgency = args.getOrDefault("urgency", %"medium").getStr()

      ctx.logMessage("info", fmt"Generating debug prompt for {errorType} error with {urgency} urgency")

      let systemPrompt = fmt"""You are a debugging expert specializing in {errorType} errors.
Urgency level: {urgency}

Help the developer identify the root cause and provide step-by-step solutions."""

      let systemMsg = McpPromptMessage(
        role: System,
        content: createTextContent(systemPrompt)
      )

      let userMsg = McpPromptMessage(
        role: User,
        content: createTextContent("I'm encountering an issue. Please help me debug it systematically.")
      )

      return @[systemMsg, userMsg]

when isMainModule:
  echo "🎯 Starting the Prompt Master Server..."
  echo "Crafting conversation starters since 2024!"
  runServer()
```

### Understanding Prompt Flow

```mermaid
sequenceDiagram
    participant Client as LLM Client
    participant Server as MCP Server
    participant Prompt as Prompt Handler

    Client->>Server: prompts/list
    Server->>Client: [available prompts]

    Client->>Server: prompts/get "code_reviewer" {language: "Nim"}
    Server->>Prompt: generate(args)
    Prompt->>Server: [system_msg, user_msg]
    Server->>Client: prompt messages

    Note over Client: Uses messages to start conversation
```

### Try This! 🧪

1. **Create a documentation prompt**: Help generate API documentation
2. **Build a testing prompt**: Generate test cases for code
3. **Make a refactoring prompt**: Suggest code improvements

---

## Chapter 5: Breaking Free from Stdio Prison

*"Stdio is like training wheels - great for learning, but eventually you want to ride without them."*

Time to graduate from the command-line world to the web! HTTP transport lets your MCP server play nice with web applications, REST clients, and anything that speaks HTTP.

Create `web_server.nim`:

```nim
import nimcp
import math, strformat

mcpServer("web-calculator", "1.0.0"):

  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers via HTTP (because the web makes everything better)
      return fmt"Web result: {a} + {b} = {a + b}"

  mcpTool:
    proc power(base: float, exponent: float): string =
      ## Calculate power (base^exponent)
      let result = pow(base, exponent)
      return fmt"Power calculation: {base}^{exponent} = {result}"

  mcpTool:
    proc fibonacci(n: int): string =
      ## Calculate the nth Fibonacci number
      if n < 0:
        return "Error: Fibonacci is not defined for negative numbers"
      elif n <= 1:
        return fmt"Fibonacci({n}) = {n}"

      var a, b = 0
      b = 1
      for i in 2..n:
        let temp = a + b
        a = b
        b = temp

      return fmt"Fibonacci({n}) = {b}"

  # Resource for mathematical constants
  mcpResource("math://constants", "Mathematical Constants", "Important mathematical constants"):
    proc getConstants(uri: string): string =
      let constants = %*{
        "pi": PI,
        "e": E,
        "golden_ratio": (1.0 + sqrt(5.0)) / 2.0,
        "sqrt_2": sqrt(2.0)
      }
      return $constants

when isMainModule:
  echo "🌐 Starting Web Calculator Server..."
  echo "Now serving math over HTTP!"
  echo ""
  echo "Endpoints:"
  echo "- GET  http://127.0.0.1:8080/         # Server info"
  echo "- POST http://127.0.0.1:8080/mcp      # MCP JSON-RPC"
  echo ""
  echo "Test with curl:"
  echo """curl -X POST http://127.0.0.1:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{}}'"""
  echo ""

  # The magic line that switches from stdio to HTTP
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

### HTTP vs Stdio: The Showdown

| Feature | Stdio | HTTP |
|---------|-------|------|
| **Complexity** | Simple | Moderate |
| **Web Integration** | Nope | Yes! |
| **Debugging** | Terminal logs | Browser dev tools |
| **Scalability** | One client | Many clients |
| **Cool Factor** | Meh | 😎 |

### Try This! 🧪

1. **Add CORS headers**: Make it work with web frontends
2. **Create a health check endpoint**: Monitor server status
3. **Add request logging**: See what's hitting your server

---

## Chapter 6: WebSocket Wizardry

*"WebSockets: Because sometimes you need to talk to your server in real-time, like a very technical phone call."*

WebSockets are like having a persistent phone line to your server - no more hanging up and calling back for every request. Perfect for real-time applications, live updates, and impressing your friends with "real-time bidirectional communication."

Create `realtime_server.nim`:

```nim
import nimcp
import math, times, strformat

mcpServer("realtime-calculator", "1.0.0"):

  mcpTool:
    proc liveAdd(a: float, b: float): string =
      ## Real-time addition (it's still just addition, but FASTER!)
      let timestamp = now().format("HH:mm:ss")
      return fmt"[{timestamp}] Live result: {a} + {b} = {a + b}"

  mcpTool:
    proc streamingFactorial(n: int): string =
      ## Calculate factorial with "streaming" updates
      if n < 0:
        return "Error: Factorial not defined for negative numbers"
      elif n > 20:
        return "Error: That's too big! My calculator might explode."

      var result = 1
      var steps = ""

      for i in 1..n:
        result *= i
        steps.add(fmt"{i}! = {result}\n")

      return fmt"Factorial calculation steps:\n{steps}Final: {n}! = {result}"

  mcpTool:
    proc serverTime(): string =
      ## Get current server time (because time waits for no one)
      let now = now()
      return fmt"Server time: {now.format('yyyy-MM-dd HH:mm:ss')} (timezone: probably wrong)"

  # Resource that changes over time
  mcpResource("live://stats", "Live Server Stats", "Real-time server statistics"):
    proc getLiveStats(uri: string): string =
      let stats = %*{
        "current_time": $now(),
        "uptime": "probably a few seconds",
        "active_connections": "at least one (you!)",
        "coffee_level": "dangerously low",
        "websocket_magic": "fully operational"
      }
      return $stats

when isMainModule:
  echo "⚡ Starting Real-time Calculator Server..."
  echo "Now with 100% more WebSocket magic!"
  echo ""
  echo "WebSocket endpoint: ws://127.0.0.1:8080/"
  echo "HTTP fallback: http://127.0.0.1:8080/"
  echo ""
  echo "Features:"
  echo "- Persistent connections (no more dial-up vibes)"
  echo "- Real-time communication (as real as it gets)"
  echo "- Lower latency (zoom zoom)"
  echo "- Bidirectional messaging (we can talk back!)"
  echo ""
  echo "Test with a WebSocket client or browser console:"
  echo """
const ws = new WebSocket('ws://127.0.0.1:8080/');
ws.onopen = () => {
  ws.send('{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{}}');
};
ws.onmessage = (event) => {
  console.log('Response:', JSON.parse(event.data));
};
"""

  # WebSocket transport for real-time communication
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

### Try This! 🧪

1. **Add a chat tool**: Let users send messages that get broadcast
2. **Create a live counter**: Increment/decrement a shared counter
3. **Build a notification system**: Send alerts to connected clients

---

## Chapter 7: Fort Knox Mode

*"Security is like wearing pants - you might not always want to, but it's generally a good idea in public."*

Time to add some security to your server! Because letting random people on the internet run arbitrary code on your server is like leaving your front door open with a sign that says "Free Stuff Inside."

Create `secure_server.nim`:

```nim
import nimcp
import math, strformat, base64, strutils

mcpServer("secure-calculator", "1.0.0"):

  mcpTool:
    proc secureAdd(a: float, b: float): string =
      ## Secure addition (now with 256-bit encryption! Just kidding, it's still just addition)
      return fmt"🔒 Secure result: {a} + {b} = {a + b}"

  mcpTool:
    proc adminOnly(secret: string): string =
      ## Admin-only function (super secret, don't tell anyone)
      if secret != "please":
        return "❌ Access denied! (Hint: try saying the magic word)"
      return "🎉 Welcome, admin! You've unlocked the secret of... absolutely nothing special."

  mcpTool:
    proc encodeMessage(message: string): string =
      ## Base64 encode a message (because obfuscation is totally security, right?)
      let encoded = encode(message)
      return fmt"🔐 Encoded message: {encoded}"

  mcpTool:
    proc decodeMessage(encoded: string): string =
      ## Base64 decode a message
      try:
        let decoded = decode(encoded)
        return fmt"🔓 Decoded message: {decoded}"
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

## Chapter 8: The Advanced Stuff

*"With great power comes great responsibility... and great complexity."*

Ready for the advanced features? This is where we separate the junior developers from the senior developers (and the senior developers from the architects who've forgotten how to code).

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

## Troubleshooting: When Things Go Sideways

*"Debugging is like being the detective in a crime movie where you are also the murderer."*

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

## Chapter 3: The Macro Magic Show

*"Any sufficiently advanced macro is indistinguishable from magic."* - Arthur C. Clarke (probably)

Writing JSON schemas by hand is like doing your taxes with an abacus - technically possible, but why would you want to? Enter NimCP's macro system, which automatically generates schemas from your procedure signatures. It's like having a very smart intern who never complains and always gets the types right.

Create `macro_magic.nim`:

```nim
import nimcp
import math, strformat

# The macro way - like having a personal assistant for your API
mcpServer("macro-magic-server", "1.0.0"):
  
  # Tool 1: Simple addition (the schema writes itself!)
  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers together because math is hard
      ## - a: First number (the lonely one)
      ## - b: Second number (the friend)
      return fmt"The sum of {a} and {b} is {a + b}"
  
  # Tool 2: String manipulation with multiple parameters
  mcpTool:
    proc formatText(text: string, uppercase: bool = false, repeat: int = 1): string =
      ## Format text with various options
      ## - text: The text to format
      ## - uppercase: Whether to SHOUT THE TEXT
      ## - repeat: How many times to repeat it (because once is never enough)
      var result = text
      if uppercase:
        result = result.toUpperAscii()
      
      var finalResult = ""
      for i in 1..repeat:
        finalResult.add(result)
        if i < repeat:
          finalResult.add(" ")
      
      return finalResult
  
  # Tool 3: Mathematical wizardry
  mcpTool:
    proc calculateCircle(radius: float): string =
      ## Calculate circle properties because geometry is everywhere
      ## - radius: The radius of the circle (must be positive, we're not dealing with imaginary circles here)
      if radius <= 0:
        return "Error: Radius must be positive. We don't do imaginary geometry here."
      
      let area = PI * radius * radius
      let circumference = 2 * PI * radius
      
      return fmt"Circle with radius {radius}: Area = {area:.2f}, Circumference = {circumference:.2f}"
  
  # Tool 4: Boolean logic (because true/false is all we really need in life)
  mcpTool:
    proc checkPassword(password: string, requireSpecial: bool = true): string =
      ## Check if a password meets basic requirements
      ## - password: The password to check
      ## - requireSpecial: Whether special characters are required
      let hasUpper = password.anyIt(it.isUpperAscii())
      let hasLower = password.anyIt(it.isLowerAscii())
      let hasDigit = password.anyIt(it.isDigit())
      let hasSpecial = password.anyIt(not (it.isAlphaNumeric()))
      
      var issues: seq[string] = @[]
      
      if password.len < 8:
        issues.add("too short (minimum 8 characters)")
      if not hasUpper:
        issues.add("needs uppercase letters")
      if not hasLower:
        issues.add("needs lowercase letters")
      if not hasDigit:
        issues.add("needs numbers")
      if requireSpecial and not hasSpecial:
        issues.add("needs special characters")
      
      if issues.len == 0:
        return "✅ Password looks good! (But please don't use 'Password123!')"
      else:
        return "❌ Password issues: " & issues.join(", ")
  
  # Tool 5: Array/sequence handling (because lists are life)
  mcpTool:
    proc findMax(numbers: seq[float]): string =
      ## Find the maximum number in a list
      ## - numbers: List of numbers to search through
      if numbers.len == 0:
        return "Error: Can't find max of empty list. That's like asking for the loudest silence."
      
      let maxNum = max(numbers)
      let maxIndex = numbers.find(maxNum)
      
      return fmt"Maximum value is {maxNum} at position {maxIndex}"

# The magic happens here - no manual schema writing required!
when isMainModule:
  echo "🎩 Starting the Macro Magic Server..."
  echo "Where schemas write themselves and developers stay sane!"
  echo ""
  echo "Available tools:"
  echo "- add: Because 2+2 is still 4 (usually)"
  echo "- formatText: Text manipulation with style"
  echo "- calculateCircle: Geometry for the masses"
  echo "- checkPassword: Password validation (with judgment)"
  echo "- findMax: Find the biggest number in the room"
  echo ""
  
  runServer()  # Uses stdio by default
```

### The Magic Revealed

What just happened? The `mcpTool` macro looked at your procedure signature and automatically:

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
nim c -r macro_magic.nim

# Test the addition
echo '{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"add","arguments":{"a":3.14,"b":2.86}}}' | ./macro_magic

# Test text formatting
echo '{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"formatText","arguments":{"text":"hello world","uppercase":true,"repeat":3}}}' | ./macro_magic

# Test password checking
echo '{"jsonrpc":"2.0","id":"3","method":"tools/call","params":{"name":"checkPassword","arguments":{"password":"MySecureP@ss123","requireSpecial":true}}}' | ./macro_magic
```

### Try This! 🧪

1. **Add a factorial function**: `proc factorial(n: int): string`
2. **Create a word counter**: `proc countWords(text: string, caseSensitive: bool = false): string`
3. **Build a temperature converter**: `proc convertTemp(temp: float, fromUnit: string, toUnit: string): string`

---
