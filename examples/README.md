# NimCP Examples

This directory contains comprehensive examples demonstrating NimCP's full feature set. Each example showcases different API styles, transport methods, and architectural patterns.

## API Styles Comparison

### Manual API
- **Pros**: Full control over tool definitions, explicit schema specification, fine-grained customization
- **Cons**: More verbose, requires manual JSON schema creation

### Macro API  
- **Pros**: Automatic introspection, less boilerplate, type-safe, rapid development
- **Cons**: Less control over generated schemas

## Transport Methods Comparison

### Stdio Transport
- **Use case**: CLI integration, process spawning, MCP specification standard
- **Features**: Standard input/output communication, process-based deployment
- **Examples**: `simple_server.nim`, `calculator_server.nim`, `macro_calculator.nim`

### HTTP Transport
- **Use case**: Web services, REST API integration, testing with curl, microservices
- **Features**: RESTful endpoints, standard HTTP methods, CORS support
- **Examples**: `macro_mummy_calculator.nim`, `mummy_calculator.nim`, `authenticated_mummy_calculator.nim`

### WebSocket Transport
- **Use case**: Real-time applications, bidirectional communication, live updates
- **Features**: Persistent connections, real-time messaging, low latency
- **Examples**: `websocket_calculator.nim`, `authenticated_websocket_calculator.nim`


### Testing HTTP Examples
For HTTP examples, test with curl:
```bash
# Initialize
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}}}}'

# Basic tool call
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"add","arguments":{"a":5,"b":3}},"id":1}'

# Authenticated request
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer valid-token-123" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"add","arguments":{"a":5,"b":3}},"id":1}'

# Server info
curl -X GET http://localhost:8080
```

## Authentication Examples

### HTTP Authentication
The `authenticated_mummy_calculator.nim` example demonstrates Bearer token authentication:

```bash
# Valid request with authentication
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer valid-token-123" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"add","arguments":{"a":5,"b":3}},"id":1}'

# Request without authentication (will fail with 401)
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"add","arguments":{"a":5,"b":3}},"id":1}'
```

### WebSocket Authentication
The `authenticated_websocket_calculator.nim` example shows authentication during WebSocket handshake:

```javascript
// WebSocket connection with authentication
const ws = new WebSocket('ws://localhost:8080', [], {
  headers: {
    'Authorization': 'Bearer valid-token-123'
  }
});

// Send JSON-RPC request over WebSocket
ws.send(JSON.stringify({
  jsonrpc: "2.0",
  method: "tools/call",
  params: {name: "add", arguments: {a: 5, b: 3}},
  id: 1
}));
```

## Advanced Feature Examples

### Resource URI Templates
```nim
# From resource_templates_example.nim
mcpResource("/users/{id}", "User Profile", "Get user by ID"):
  proc getUserProfile(uri: string): string =
    let params = extractUriParams(uri, "/users/{id}")
    return fmt"User profile for ID: {params["id"]}"
```

### Server Composition
```nim
# From server_composition_example.nim
let mainServer = newMcpServer("gateway", "1.0.0")
let calculatorServer = newMcpServer("calculator", "1.0.0")
let userServer = newMcpServer("users", "1.0.0")

mainServer.mount("/calc", calculatorServer)
mainServer.mount("/users", userServer)
```

### Pluggable Logging
```nim
# From logging_example.nim
server.logger.addHandler(newConsoleLogHandler())
server.logger.addHandler(newFileLogHandler("server.log"))
server.logger.addHandler(newStructuredLogHandler())
```
