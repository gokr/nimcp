## Powerful macros for easy MCP server creation

import macros, asyncdispatch, json, tables, options
import types, server, protocol

# For now, let's create simpler versions that work
template mcpServer*(name: string, version: string, body: untyped): untyped =
  let mcpServerInstance = newMcpServer(name, version)
  body
  
  proc runServer*() {.async.} =
    await mcpServerInstance.runStdio()
  
  when isMainModule:
    waitFor runServer()

# Simple tool registration template
template mcpTool*(name: string, description: string, schema: JsonNode, handler: untyped): untyped =
  let tool = McpTool(
    name: name,
    description: some(description),
    inputSchema: schema
  )
  
  proc toolHandler(args: JsonNode): Future[McpToolResult] {.async.} =
    let result = handler(args)
    return McpToolResult(content: @[createTextContent(result)])
  
  mcpServerInstance.registerTool(tool, toolHandler)

# Simple resource registration template  
template mcpResource*(uri: string, name: string, description: string, handler: untyped): untyped =
  let resource = McpResource(
    uri: uri,
    name: name,
    description: some(description)
  )
  
  proc resourceHandler(uriParam: string): Future[McpResourceContents] {.async.} =
    let content = handler(uriParam)
    return McpResourceContents(
      uri: uriParam,
      content: @[createTextContent(content)]
    )
  
  mcpServerInstance.registerResource(resource, resourceHandler)

# Simple prompt registration template
template mcpPrompt*(name: string, description: string, arguments: seq[McpPromptArgument], handler: untyped): untyped =
  let prompt = McpPrompt(
    name: name,
    description: some(description),
    arguments: arguments
  )
  
  proc promptHandler(nameParam: string, args: Table[string, JsonNode]): Future[McpGetPromptResult] {.async.} =
    let messages = handler(nameParam, args)
    return McpGetPromptResult(messages: messages)
  
  mcpServerInstance.registerPrompt(prompt, promptHandler)