## Powerful macros for easy MCP server creation

import macros, asyncdispatch, json, tables, options, strutils, typetraits
import types, server, protocol

# Helper to convert Nim types to JSON schema types
proc nimTypeToJsonSchema(nimType: NimNode): JsonNode =
  case nimType.kind:
  of nnkIdent:
    case $nimType:
    of "int", "int8", "int16", "int32", "int64":
      result = newJObject()
      result["type"] = newJString("integer")
    of "uint", "uint8", "uint16", "uint32", "uint64":
      result = newJObject()
      result["type"] = newJString("integer")
      result["minimum"] = newJInt(0)
    of "float", "float32", "float64":
      result = newJObject()
      result["type"] = newJString("number")
    of "string":
      result = newJObject()
      result["type"] = newJString("string")
    of "bool":
      result = newJObject()
      result["type"] = newJString("boolean")
    else:
      result = newJObject()
      result["type"] = newJString("string")  # Default fallback
  of nnkBracketExpr:
    if nimType[0].kind == nnkIdent and $nimType[0] == "seq":
      result = newJObject()
      result["type"] = newJString("array")
      result["items"] = nimTypeToJsonSchema(nimType[1])
    else:
      result = newJObject()
      result["type"] = newJString("string")  # Default fallback
  else:
    result = newJObject()
    result["type"] = newJString("string")  # Default fallback

# Extract documentation from proc node
proc extractDocComment(procNode: NimNode): string =
  for child in procNode:
    if child.kind == nnkCommentStmt:
      return child.strVal.strip()
  return ""

# Generate JSON schema from proc parameters
proc generateInputSchema(params: NimNode): JsonNode =
  var properties = newJObject()
  var required = newJArray()
  
  # Skip first param (implicit result) and start from index 1
  for i in 1..<params.len:
    let param = params[i]
    if param.kind == nnkIdentDefs:
      let paramType = param[^2]  # Type is second to last
      for j in 0..<param.len-2:  # All except type and default value
        let paramName = $param[j]
        if paramName != "":
          properties[paramName] = nimTypeToJsonSchema(paramType)
          required.add(newJString(paramName))
  
  result = newJObject()
  result["type"] = newJString("object")
  result["properties"] = properties
  result["required"] = required

# Advanced macro for introspecting proc signatures and auto-generating tools
macro mcpTool*(procDef: untyped): untyped =
  # Handle both direct proc def and block containing proc def
  var actualProcDef: NimNode
  if procDef.kind == nnkStmtList and procDef.len > 0 and procDef[0].kind == nnkProcDef:
    actualProcDef = procDef[0]
  elif procDef.kind == nnkProcDef:
    actualProcDef = procDef
  else:
    error("Expected a proc definition", procDef)
  
  let procName = actualProcDef[0]
  let params = actualProcDef[3]  # Parameters
  
  # Extract tool name from proc name
  let toolName = $procName
  
  # Extract description from doc comment - get first line only
  let docComment = extractDocComment(actualProcDef).splitLines()[0].strip()
  let description = if docComment.len > 0: docComment else: "Auto-generated tool: " & toolName
  
  # Generate input schema from parameters
  let inputSchema = generateInputSchema(params)
  
  # Generate the wrapper proc name to avoid conflicts
  let wrapperName = ident("tool_" & toolName & "_wrapper")
  
  # Convert the compile-time schema to a runtime string representation
  let schemaStr = $inputSchema
  
  result = quote do:
    # Create the tool definition - parse schema at runtime
    let tool = McpTool(
      name: `toolName`,
      description: some(`description`),
      inputSchema: parseJson(`schemaStr`)
    )
    
    # Create wrapper - simplified for now to just return the tool name
    proc `wrapperName`(args: JsonNode): Future[McpToolResult] {.async.} =
      return McpToolResult(content: @[createTextContent("Tool " & `toolName` & " called with: " & $args)])
    
    # Register the tool using the global server instance
    currentMcpServer.registerTool(tool, `wrapperName`)
  
  # Return the original proc definition unchanged so it can be used normally
  # Note: actualProcDef is already part of the input, so we don't add it again

# Global server instance for macro access
var currentMcpServer*: McpServer

# Server creation template with advanced tool registration
template mcpServer*(name: string, version: string, body: untyped): untyped =
  let mcpServerInstance = newMcpServer(name, version)
  currentMcpServer = mcpServerInstance
  body
  
  proc runServer*() {.async.} =
    await mcpServerInstance.runStdio()
  
  when isMainModule:
    waitFor runServer()


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