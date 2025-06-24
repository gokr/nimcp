# NimCP Examples

This directory contains examples demonstrating different ways to create MCP servers using NimCP. Each example showcases different API styles and transport methods.

## Examples Overview

### 1. `simple_server.nim` - Basic Manual API with Stdio
- **API Style**: Manual (low-level API)
- **Transport**: Stdio (JSON-RPC over stdin/stdout)
- **Features**: 
  - Echo tool (returns input with "Echo: " prefix)
  - Current time tool
  - Info resource (demonstrates URI-based resource access)
- **Best for**: Learning basic MCP concepts and resource handling

### 2. `calculator_server.nim` - Complex Manual API with Stdio  
- **API Style**: Manual (low-level API)
- **Transport**: Stdio (JSON-RPC over stdin/stdout)
- **Features**:
  - Mathematical operations (add, multiply, power)
  - Math constants resource (π, e, φ, √2)
- **Best for**: Understanding manual tool registration and mathematical operations

### 3. `macro_calculator.nim` - Macro API with Stdio
- **API Style**: Macro (high-level with automatic introspection)
- **Transport**: Stdio (JSON-RPC over stdin/stdout)
- **Features**:
  - Automatic schema generation from proc signatures
  - Mixed parameter types (int, float, bool, string)
  - Tools: add, multiply, compare, factorial
- **Best for**: Learning the macro API and type-safe parameter handling

### 4. `macro_mummy_calculator.nim` - Macro API with HTTP
- **API Style**: Macro (high-level with automatic introspection)
- **Transport**: HTTP (JSON-RPC over HTTP using Mummy web server)
- **Features**:
  - Same tools as `macro_calculator.nim` but over HTTP
  - Runs on localhost:8080
  - Includes curl test examples
- **Best for**: HTTP-based MCP servers with automatic introspection

### 5. `mummy_calculator.nim` - Manual API with HTTP
- **API Style**: Manual (low-level API)
- **Transport**: HTTP (JSON-RPC over HTTP using Mummy web server)
- **Features**:
  - Manual tool registration with HTTP transport
  - Input validation (factorial range 0-20)
  - Tools: add, multiply, factorial
- **Best for**: HTTP servers requiring fine-grained control

## API Styles Comparison

### Manual API
- **Pros**: Full control over tool definitions, explicit schema specification
- **Cons**: More verbose, requires manual JSON schema creation
- **Examples**: `simple_server.nim`, `calculator_server.nim`, `mummy_calculator.nim`

### Macro API  
- **Pros**: Automatic introspection, less boilerplate, type-safe
- **Cons**: Less control over generated schemas
- **Examples**: `macro_calculator.nim`, `macro_mummy_calculator.nim`

## Transport Methods Comparison

### Stdio Transport
- **Use case**: CLI integration, process spawning, MCP specification standard
- **Examples**: `simple_server.nim`, `calculator_server.nim`, `macro_calculator.nim`

### HTTP Transport
- **Use case**: Web services, REST API integration, testing with curl
- **Examples**: `macro_mummy_calculator.nim`, `mummy_calculator.nim`

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
```

For HTTP examples, test with curl:
```bash
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"add","arguments":{"a":5,"b":3}},"id":1}'
```

## Architecture Matrix

| Example | API Style | Transport | Complexity |
|---------|-----------|-----------|------------|
| `simple_server.nim` | Manual | Stdio | Basic |
| `calculator_server.nim` | Manual | Stdio | Intermediate |
| `macro_calculator.nim` | Macro | Stdio | Intermediate |
| `macro_mummy_calculator.nim` | Macro | HTTP | Intermediate |
| `mummy_calculator.nim` | Manual | HTTP | Advanced |