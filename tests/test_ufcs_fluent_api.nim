## Test UFCS Fluent API functionality

import unittest, json, options, tables
import ../src/nimcp

suite "UFCS Fluent API Tests":
  
  test "Fluent server configuration with withTool":
    let server = newMcpServer("fluent-test", "1.0.0")
    
    let tool = McpTool(
      name: "test_tool",
      description: some("A test tool"),
      inputSchema: %*{"type": "object"}
    )
    
    proc testHandler(args: JsonNode): McpToolResult =
      return McpToolResult(content: @[createTextContent("test result")])
    
    # Test fluent API - should return the server for chaining
    let result = server.withTool(tool, testHandler)
    check result == server  # Should return the same server instance
    check server.tools.hasKey("test_tool")
    check server.capabilities.tools.isSome
  
  test "Fluent server configuration with withResource":
    let server = newMcpServer("fluent-test", "1.0.0")
    
    let resource = McpResource(
      uri: "test://resource",
      name: "Test Resource",
      description: some("A test resource")
    )
    
    proc testHandler(uri: string): McpResourceContents =
      return McpResourceContents(
        uri: uri,
        content: @[createTextContent("test content")]
      )
    
    # Test fluent API
    let result = server.withResource(resource, testHandler)
    check result == server
    check server.resources.hasKey("test://resource")
    check server.capabilities.resources.isSome
  
  test "Fluent server configuration with withPrompt":
    let server = newMcpServer("fluent-test", "1.0.0")
    
    let prompt = McpPrompt(
      name: "test_prompt",
      description: some("A test prompt"),
      arguments: @[]
    )
    
    proc testHandler(name: string, args: Table[string, JsonNode]): McpGetPromptResult =
      return McpGetPromptResult(
        messages: @[McpPromptMessage(
          role: User,
          content: createTextContent("test prompt")
        )]
      )
    
    # Test fluent API
    let result = server.withPrompt(prompt, testHandler)
    check result == server
    check server.prompts.hasKey("test_prompt")
    check server.capabilities.prompts.isSome
  
  test "Chained fluent configuration":
    let server = newMcpServer("fluent-chain-test", "1.0.0")
    
    let tool = McpTool(
      name: "chain_tool",
      description: some("A chained tool"),
      inputSchema: %*{"type": "object"}
    )
    
    let resource = McpResource(
      uri: "chain://resource",
      name: "Chain Resource",
      description: some("A chained resource")
    )
    
    let prompt = McpPrompt(
      name: "chain_prompt",
      description: some("A chained prompt"),
      arguments: @[]
    )
    
    proc toolHandler(args: JsonNode): McpToolResult =
      return McpToolResult(content: @[createTextContent("chain tool result")])
    
    proc resourceHandler(uri: string): McpResourceContents =
      return McpResourceContents(
        uri: uri,
        content: @[createTextContent("chain resource content")]
      )
    
    proc promptHandler(name: string, args: Table[string, JsonNode]): McpGetPromptResult =
      return McpGetPromptResult(
        messages: @[McpPromptMessage(
          role: User,
          content: createTextContent("chain prompt")
        )]
      )
    
    # Test chained fluent API
    let result = server
      .withTool(tool, toolHandler)
      .withResource(resource, resourceHandler)
      .withPrompt(prompt, promptHandler)
    
    check result == server
    check server.tools.hasKey("chain_tool")
    check server.resources.hasKey("chain://resource")
    check server.prompts.hasKey("chain_prompt")
    check server.capabilities.tools.isSome
    check server.capabilities.resources.isSome
    check server.capabilities.prompts.isSome
  
  test "UFCS style: tool.registerWith(server)":
    let server = newMcpServer("ufcs-test", "1.0.0")
    
    let tool = McpTool(
      name: "ufcs_tool",
      description: some("A UFCS tool"),
      inputSchema: %*{"type": "object"}
    )
    
    proc testHandler(args: JsonNode): McpToolResult =
      return McpToolResult(content: @[createTextContent("ufcs result")])
    
    # Test UFCS style - object.method(args)
    let result = tool.registerWith(server, testHandler)
    check result == server
    check server.tools.hasKey("ufcs_tool")
    check server.capabilities.tools.isSome
  
  test "UFCS style: resource.registerWith(server)":
    let server = newMcpServer("ufcs-test", "1.0.0")
    
    let resource = McpResource(
      uri: "ufcs://resource",
      name: "UFCS Resource",
      description: some("A UFCS resource")
    )
    
    proc testHandler(uri: string): McpResourceContents =
      return McpResourceContents(
        uri: uri,
        content: @[createTextContent("ufcs content")]
      )
    
    # Test UFCS style
    let result = resource.registerWith(server, testHandler)
    check result == server
    check server.resources.hasKey("ufcs://resource")
    check server.capabilities.resources.isSome
  
  test "UFCS style: prompt.registerWith(server)":
    let server = newMcpServer("ufcs-test", "1.0.0")
    
    let prompt = McpPrompt(
      name: "ufcs_prompt",
      description: some("A UFCS prompt"),
      arguments: @[]
    )
    
    proc testHandler(name: string, args: Table[string, JsonNode]): McpGetPromptResult =
      return McpGetPromptResult(
        messages: @[McpPromptMessage(
          role: User,
          content: createTextContent("ufcs prompt")
        )]
      )
    
    # Test UFCS style
    let result = prompt.registerWith(server, testHandler)
    check result == server
    check server.prompts.hasKey("ufcs_prompt")
    check server.capabilities.prompts.isSome
  
  test "Mixed fluent and UFCS styles":
    let server = newMcpServer("mixed-test", "1.0.0")
    
    let tool = McpTool(
      name: "mixed_tool",
      description: some("A mixed tool"),
      inputSchema: %*{"type": "object"}
    )
    
    let resource = McpResource(
      uri: "mixed://resource",
      name: "Mixed Resource",
      description: some("A mixed resource")
    )
    
    proc toolHandler(args: JsonNode): McpToolResult =
      return McpToolResult(content: @[createTextContent("mixed tool result")])
    
    proc resourceHandler(uri: string): McpResourceContents =
      return McpResourceContents(
        uri: uri,
        content: @[createTextContent("mixed resource content")]
      )
    
    # Mix fluent and UFCS styles
    let result1 = server.withTool(tool, toolHandler)
    let result2 = resource.registerWith(result1, resourceHandler)
    
    check result1 == server
    check result2 == server
    check server.tools.hasKey("mixed_tool")
    check server.resources.hasKey("mixed://resource")
    check server.capabilities.tools.isSome
    check server.capabilities.resources.isSome
