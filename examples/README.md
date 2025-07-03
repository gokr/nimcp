# NimCP Examples

This directory contains comprehensive examples demonstrating NimCP's full feature set. Each example showcases different API styles, transport methods, and architectural patterns.

## Examples Overview

### `simple_server.nim` - Basic Manual API with Stdio
- **API Style**: Manual (low-level API)
- **Transport**: Stdio (JSON-RPC over stdin/stdout)
- **Features**: 
  - Echo tool (returns input with "Echo: " prefix)
  - Current time tool
  - Info resource (demonstrates URI-based resource access)
- **Best for**: Learning basic MCP concepts and resource handling

### `calculator_server.nim` - Complex Manual API with Stdio  
- **API Style**: Manual (low-level API)
- **Transport**: Stdio (JSON-RPC over stdin/stdout)
- **Features**:
  - Mathematical operations (add, multiply, power)
  - Math constants resource (π, e, φ, √2)
- **Best for**: Understanding manual tool registration and mathematical operations

### `macro_calculator.nim` - Macro API with Stdio
- **API Style**: Macro (high-level with automatic introspection)
- **Transport**: Stdio (JSON-RPC over stdin/stdout)
- **Features**:
  - Automatic schema generation from proc signatures
  - Mixed parameter types (int, float, bool, string)
  - Tools: add, multiply, compare, factorial
- **Best for**: Learning the macro API and type-safe parameter handling

### `macro_mummy_calculator.nim` - Macro API with HTTP
- **API Style**: Macro (high-level with automatic introspection)
- **Transport**: HTTP (JSON-RPC over HTTP using Mummy web server)
- **Features**:
  - Same tools as `macro_calculator.nim` but over HTTP
  - Runs on localhost:8080
  - Includes curl test examples
- **Best for**: HTTP-based MCP servers with automatic introspection

### `mummy_calculator.nim` - Manual API with HTTP
- **API Style**: Manual (low-level API)
- **Transport**: HTTP (JSON-RPC over HTTP using Mummy web server)
- **Features**:
  - Manual tool registration with HTTP transport
  - Input validation (factorial range 0-20)
  - Tools: add, multiply, factorial
- **Best for**: HTTP servers requiring fine-grained control

### `authenticated_mummy_calculator.nim` - HTTP with Bearer Token Authentication
- **API Style**: Manual (low-level API)
- **Transport**: HTTP with Bearer token authentication
- **Features**:
  - Bearer token authentication following MCP specification
  - Token validation with configurable validator function
  - Tools: add, multiply, factorial
  - Demonstrates authentication configuration
- **Best for**: Secure HTTP servers requiring token-based authentication

### `websocket_calculator.nim` - Macro API with WebSocket
- **API Style**: Macro (high-level with automatic introspection)
- **Transport**: WebSocket (real-time bidirectional communication)
- **Features**:
  - Real-time calculator tools over WebSocket
  - JSON-RPC 2.0 over WebSocket protocol
  - Connection management and error handling
- **Best for**: Real-time applications requiring bidirectional communication

### `authenticated_websocket_calculator.nim` - WebSocket with Authentication
- **API Style**: Manual (low-level API)
- **Transport**: WebSocket with Bearer token authentication
- **Features**:
  - WebSocket upgrade with authentication validation
  - Bearer token verification during handshake
  - Secure real-time communication
- **Best for**: Secure real-time applications with authentication

### `resource_templates_example.nim` - Dynamic URI Templates
- **Features**:
  - Resource URI templates with parameter extraction (`/users/{id}`)
  - Dynamic resource resolution based on URI patterns
  - Template validation and parameter mapping
- **Best for**: Dynamic resource systems and REST-like APIs

### `server_composition_example.nim` - Server Mounting and API Gateways
- **Features**:
  - Multiple MCP server mounting with path prefixes
  - Server composition for API gateway patterns
  - Namespace management and routing
- **Best for**: Microservices architecture and API gateway patterns

### `logging_example.nim` - Pluggable Logging System
- **Features**:
  - Multiple logging handlers (console, file, structured)
  - Log level filtering and component-based logging
  - Chronicles integration for structured logging
- **Best for**: Production deployments requiring comprehensive logging


### `fluent_api_example.nim` - Fluent API
- **Features**:
  - Method chaining patterns for elegant configuration
  - Fluent builder patterns for server setup  
  - Demonstrates `.withTool()`, `.withResource()`, `.withPrompt()` patterns
- **Best for**: Elegant API design and configuration patterns

### `enhanced_calculator.nim` - Comprehensive Feature Showcase
- **Features**:
  - Combines all advanced features in one example
  - Resource templates, logging, middleware, and composition
  - Production-ready patterns and best practices
- **Best for**: Understanding complete feature integration

## API Styles Comparison

### Manual API
- **Pros**: Full control over tool definitions, explicit schema specification, fine-grained customization
- **Cons**: More verbose, requires manual JSON schema creation
- **Examples**: `simple_server.nim`, `calculator_server.nim`, `mummy_calculator.nim`, `authenticated_mummy_calculator.nim`

### Macro API  
- **Pros**: Automatic introspection, less boilerplate, type-safe, rapid development
- **Cons**: Less control over generated schemas
- **Examples**: `macro_calculator.nim`, `macro_mummy_calculator.nim`, `websocket_calculator.nim`, `enhanced_calculator.nim`

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

## Running Examples

### Stdio Examples
```bash
nim c -r examples/simple_server.nim
nim c -r examples/calculator_server.nim  
nim c -r examples/macro_calculator.nim
```

### HTTP Examples
```bash
nim c -r examples/macro_mummy_calculator.nim
nim c -r examples/mummy_calculator.nim
nim c -r examples/authenticated_mummy_calculator.nim
```

### WebSocket Examples
```bash
nim c -r examples/websocket_calculator.nim
nim c -r examples/authenticated_websocket_calculator.nim
```

### Advanced Examples
```bash
nim c -r examples/resource_templates_example.nim
nim c -r examples/server_composition_example.nim
nim c -r examples/logging_example.nim
nim c -r examples/fluent_api_example.nim
nim c -r examples/enhanced_calculator.nim
```

### Testing HTTP Examples
For HTTP examples, test with curl:
```bash
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

## Architecture Matrix

| Example | API Style | Transport | Authentication | Features |
|---------|-----------|-----------|----------------|----------|
| `simple_server.nim` | Manual | Stdio | None | Basic tools, resources |
| `calculator_server.nim` | Manual | Stdio | None | Math operations, constants |
| `macro_calculator.nim` | Macro | Stdio | None | Automatic schemas |
| `macro_mummy_calculator.nim` | Macro | HTTP | None | HTTP transport |
| `mummy_calculator.nim` | Manual | HTTP | None | Manual HTTP setup |
| `authenticated_mummy_calculator.nim` | Manual | HTTP | Bearer Token | HTTP authentication |
| `websocket_calculator.nim` | Macro | WebSocket | None | Real-time communication |
| `authenticated_websocket_calculator.nim` | Manual | WebSocket | Bearer Token | Secure WebSocket |
| `resource_templates_example.nim` | Macro | Stdio | None | Dynamic URI templates |
| `server_composition_example.nim` | Mixed | Stdio | None | Server mounting |
| `logging_example.nim` | Macro | Stdio | None | Pluggable logging |
| `fluent_api_example.nim` | Fluent | Stdio | None | Method chaining |
| `enhanced_calculator.nim` | Macro | HTTP | Optional | All advanced features |

## Feature Summary

### Core Features (All Examples)
- JSON-RPC 2.0 protocol implementation
- Tool registration and invocation
- Resource access and management
- Basic error handling

### Advanced Features
- Enhanced type system (objects, unions, enums)
- Request context and cancellation
- WebSocket transport with authentication
- Structured error handling
- Resource URI templates with parameters
- Server composition and mounting
- Pluggable logging system
- Real-time communication via WebSocket transport
- Middleware pipeline support
- Fluent API patterns