## Tests for the calculator_server example
## Identifies issues with the macro-based server and suggests fixes

import unittest, json, options, math, strutils
import ../src/nimcp

suite "Calculator Server Tests":
  
  test "Manual calculator server implementation (working version)":
    # This shows how the calculator_server SHOULD be implemented
    let server = newMcpServer("calculator", "1.0.0")
    
    # Initialize server first
    let initRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 1)),
      `method`: "initialize",
      params: some(%*{
        "protocolVersion": "2024-11-05",
        "capabilities": {"tools": {}}
      })
    )
    discard server.handleRequest(initRequest)
    
    # Register add tool manually (correct implementation)
    let addTool = McpTool(
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
    )
    
    proc addHandler(args: JsonNode): McpToolResult =
      let a = args["a"].getFloat()
      let b = args["b"].getFloat()
      return McpToolResult(content: @[createTextContent($(a + b))])
    
    server.registerTool(addTool, addHandler)
    
    # Test the add tool
    let callRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 2)),
      `method`: "tools/call",
      params: some(%*{
        "name": "add",
        "arguments": {"a": 5.0, "b": 3.0}
      })
    )
    
    let callResponse = server.handleRequest(callRequest)
    check callResponse.error.isNone
    check callResponse.result.isSome
    let content = callResponse.result.get()["content"].getElems()
    check content.len == 1
    check content[0]["text"].getStr() == "8.0"
  
  test "Math constants resource":
    let server = newMcpServer("calculator", "1.0.0")
    
    # Initialize server
    let initRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 1)),
      `method`: "initialize",
      params: some(%*{
        "protocolVersion": "2024-11-05",
        "capabilities": {"resources": {}}
      })
    )
    discard server.handleRequest(initRequest)
    
    # Register math constants resource
    let constantsResource = McpResource(
      uri: "math://constants",
      name: "Mathematical Constants",
      description: some("Common mathematical constants")
    )
    
    proc constantsHandler(uri: string): McpResourceContents =
      return McpResourceContents(
        uri: uri,
        content: @[createTextContent("""Mathematical Constants:
- π (Pi): 3.14159265359
- e (Euler's number): 2.71828182846  
- φ (Golden ratio): 1.61803398875
- √2 (Square root of 2): 1.41421356237""")]
      )
    
    server.registerResource(constantsResource, constantsHandler)
    
    # Test resource access
    let readRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 2)),
      `method`: "resources/read",
      params: some(%*{
        "uri": "math://constants"
      })
    )
    
    let readResponse = server.handleRequest(readRequest)
    check readResponse.error.isNone
    check readResponse.result.isSome
    let content = readResponse.result.get()["content"].getElems()
    check content.len == 1
    check "π (Pi)" in content[0]["text"].getStr()
  
  test "Power calculation tool":
    let server = newMcpServer("calculator", "1.0.0")
    
    # Initialize server
    let initRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 1)),
      `method`: "initialize",
      params: some(%*{
        "protocolVersion": "2024-11-05",
        "capabilities": {"tools": {}}
      })
    )
    discard server.handleRequest(initRequest)
    
    # Register power tool
    let powerTool = McpTool(
      name: "power",
      description: some("Calculate a raised to the power of b"),
      inputSchema: %*{
        "type": "object",
        "properties": {
          "base": {"type": "number", "description": "Base number"},
          "exponent": {"type": "number", "description": "Exponent"}
        },
        "required": ["base", "exponent"]
      }
    )
    
    proc powerHandler(args: JsonNode): McpToolResult =
      let base = args["base"].getFloat()
      let exponent = args["exponent"].getFloat()
      return McpToolResult(content: @[createTextContent($pow(base, exponent))])
    
    server.registerTool(powerTool, powerHandler)
    
    # Test power calculation: 2^3 = 8
    let callRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 2)),
      `method`: "tools/call",
      params: some(%*{
        "name": "power",
        "arguments": {"base": 2.0, "exponent": 3.0}
      })
    )
    
    let callResponse = server.handleRequest(callRequest)
    check callResponse.error.isNone
    check callResponse.result.isSome
    let content = callResponse.result.get()["content"].getElems()
    check content.len == 1
    check content[0]["text"].getStr() == "8.0"