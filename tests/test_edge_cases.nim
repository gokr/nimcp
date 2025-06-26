## Edge case tests for nimcp
## Tests boundary conditions, unusual inputs, and corner cases

import unittest, json, options, tables, strutils
import ../src/nimcp

suite "Edge Case Tests":
  
  test "Empty and null values handling":
    let server = newMcpServer("", "")  # Empty name and version
    check server.serverInfo.name == ""
    check server.serverInfo.version == ""

    # Test with empty tool name - should raise ValueError
    let emptyTool = McpTool(
      name: "",
      description: none(string),
      inputSchema: %*{}
    )

    proc emptyHandler(args: JsonNode): McpToolResult =
      return McpToolResult(content: @[])

    # This should raise a ValueError due to validation
    expect(ValueError):
      server.registerTool(emptyTool, emptyHandler)

    # Test with valid minimal tool
    let minimalTool = McpTool(
      name: "minimal",
      description: none(string),
      inputSchema: %*{}
    )

    server.registerTool(minimalTool, emptyHandler)
    check server.tools.hasKey("minimal")
  
  test "Very long strings and large data":
    let server = newMcpServer("edge-test", "1.0.0")
    
    # Test with very long tool name and description
    let longName = "a".repeat(1000)
    let longDescription = "b".repeat(10000)
    
    let longTool = McpTool(
      name: longName,
      description: some(longDescription),
      inputSchema: %*{"type": "object"}
    )
    
    proc longHandler(args: JsonNode): McpToolResult =
      let longContent = "c".repeat(50000)
      return McpToolResult(content: @[createTextContent(longContent)])
    
    server.registerTool(longTool, longHandler)
    check server.tools.hasKey(longName)
    check server.tools[longName].description.get() == longDescription
  
  test "Special characters in names and URIs":
    let server = newMcpServer("edge-test", "1.0.0")
    
    # Test tool with special characters
    let specialTool = McpTool(
      name: "tool-with-special!@#$%^&*()_+{}|:<>?[]\\;'\",./ chars",
      description: some("Tool with unicode: 🚀 ñ ü ß"),
      inputSchema: %*{"type": "object"}
    )
    
    proc specialHandler(args: JsonNode): McpToolResult =
      return McpToolResult(content: @[createTextContent("Special chars handled")])
    
    server.registerTool(specialTool, specialHandler)
    
    # Test resource with special URI
    let specialResource = McpResource(
      uri: "special://resource/with spaces and unicode 🌟",
      name: "Special Resource",
      description: some("Resource with special URI")
    )
    
    proc specialResourceHandler(uri: string): McpResourceContents =
      return McpResourceContents(
        uri: uri,
        content: @[createTextContent("Content for special URI: " & uri)]
      )
    
    server.registerResource(specialResource, specialResourceHandler)
    check server.resources.hasKey("special://resource/with spaces and unicode 🌟")
  
  test "Deeply nested JSON structures":
    let server = newMcpServer("edge-test", "1.0.0")
    
    # Create deeply nested input schema
    var deepSchema = %*{"type": "object"}
    var current = deepSchema
    for i in 1..10:
      current["properties"] = %*{
        "level" & $i: {
          "type": "object",
          "properties": {}
        }
      }
      current = current["properties"]["level" & $i]
    
    let deepTool = McpTool(
      name: "deep_tool",
      description: some("Tool with deeply nested schema"),
      inputSchema: deepSchema
    )
    
    proc deepHandler(args: JsonNode): McpToolResult =
      return McpToolResult(content: @[createTextContent("Handled deep structure")])
    
    server.registerTool(deepTool, deepHandler)
    check server.tools.hasKey("deep_tool")
  
  test "Concurrent tool registration":
    let server = newMcpServer("edge-test", "1.0.0")
    
    # Register multiple tools rapidly to test thread safety
    for i in 1..100:
      let tool = McpTool(
        name: "tool_" & $i,
        description: some("Tool number " & $i),
        inputSchema: %*{"type": "object"}
      )
      
      proc handler(args: JsonNode): McpToolResult =
        return McpToolResult(content: @[createTextContent("Result from tool " & $i)])
      
      server.registerTool(tool, handler)
    
    check server.tools.len == 100
    check server.toolHandlers.len == 100
    
    # Verify all tools are properly registered
    for i in 1..100:
      check server.tools.hasKey("tool_" & $i)
      check server.toolHandlers.hasKey("tool_" & $i)
  
  test "Invalid JSON-RPC ID types":
    let server = newMcpServer("edge-test", "1.0.0")
    
    # Test with different ID types
    let stringIdRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridString, str: "string-id-123")),
      `method`: "initialize",
      params: some(%*{
        "protocolVersion": "2024-11-05",
        "capabilities": {}
      })
    )
    
    let response1 = server.handleRequest(stringIdRequest)
    check response1.id.kind == jridString
    check response1.id.str == "string-id-123"
    
    let intIdRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 999)),
      `method`: "tools/list"
    )
    
    let response2 = server.handleRequest(intIdRequest)
    check response2.id.kind == jridInt
    check response2.id.num == 999
  
  test "Resource URI edge cases":
    let server = newMcpServer("edge-test", "1.0.0")
    
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
    
    # Test various URI formats
    let uriCases = @[
      "file:///absolute/path/to/file.txt",
      "http://example.com/resource?param=value&other=123",
      "custom-scheme://host:port/path#fragment",
      "urn:uuid:12345678-1234-5678-9012-123456789012",
      "data:text/plain;base64,SGVsbG8gV29ybGQ=",
      "mailto:test@example.com",
      "ftp://user:pass@ftp.example.com/file.txt"
    ]
    
    for uri in uriCases:
      let resource = McpResource(
        uri: uri,
        name: "Resource for " & uri,
        description: some("Test resource")
      )
      
      proc handler(uriParam: string): McpResourceContents =
        return McpResourceContents(
          uri: uriParam,
          content: @[createTextContent("Content for: " & uriParam)]
        )
      
      server.registerResource(resource, handler)
      check server.resources.hasKey(uri)
  
  test "Tool arguments edge cases":
    let server = newMcpServer("edge-test", "1.0.0")
    
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
    
    # Tool that handles various argument types
    proc flexibleHandler(args: JsonNode): McpToolResult =
      var results: seq[string] = @[]
      
      for key, value in args.pairs:
        case value.kind:
          of JString:
            results.add(key & ": string(" & value.getStr() & ")")
          of JInt:
            results.add(key & ": int(" & $value.getInt() & ")")
          of JFloat:
            results.add(key & ": float(" & $value.getFloat() & ")")
          of JBool:
            results.add(key & ": bool(" & $value.getBool() & ")")
          of JArray:
            results.add(key & ": array[" & $value.len & "]")
          of JObject:
            results.add(key & ": object{" & $value.len & " keys}")
          of JNull:
            results.add(key & ": null")
      
      return McpToolResult(content: @[createTextContent(results.join(", "))])
    
    let flexTool = McpTool(
      name: "flexible_tool",
      description: some("Tool that handles various argument types"),
      inputSchema: %*{"type": "object"}
    )
    
    server.registerTool(flexTool, flexibleHandler)
    
    # Test with various argument types
    let callRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 2)),
      `method`: "tools/call",
      params: some(%*{
        "name": "flexible_tool",
        "arguments": {
          "string_arg": "hello",
          "int_arg": 42,
          "float_arg": 3.14,
          "bool_arg": true,
          "array_arg": [1, 2, 3],
          "object_arg": {"nested": "value"},
          "null_arg": nil
        }
      })
    )
    
    let response = server.handleRequest(callRequest)
    check response.error.isNone
    
    let result = response.result.get
    let content = result["content"][0]["text"].getStr()
    check "string_arg: string(hello)" in content
    check "int_arg: int(42)" in content
    check "bool_arg: bool(true)" in content
