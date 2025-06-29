## Powerful macros for easy MCP server creation

import macros, json, tables, options, strutils, typetraits, sequtils, times, strformat
import types, server, protocol

# Enhanced helper to convert Nim types to JSON schema types with support for more types
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
      # Try to handle as object type
      result = newJObject()
      result["type"] = newJString("object")
      result["description"] = newJString("Custom type: " & $nimType)
  of nnkBracketExpr:
    if nimType[0].kind == nnkIdent:
      case $nimType[0]:
      of "seq":
        result = newJObject()
        result["type"] = newJString("array")
        result["items"] = nimTypeToJsonSchema(nimType[1])
      of "Option":
        # Optional type - make the inner type nullable
        result = nimTypeToJsonSchema(nimType[1])
        if result.hasKey("type"):
          let innerType = result["type"].getStr()
          result["anyOf"] = %[%*{"type": innerType}, %*{"type": "null"}]
          result.delete("type")
      of "set":
        result = newJObject()
        result["type"] = newJString("array")
        result["uniqueItems"] = newJBool(true)
        result["items"] = nimTypeToJsonSchema(nimType[1])
      else:
        result = newJObject()
        result["type"] = newJString("object")
        result["description"] = newJString("Generic type: " & $nimType[0])
    else:
      result = newJObject()
      result["type"] = newJString("string")  # Default fallback
  of nnkTupleConstr, nnkTupleTy:
    # Tuple type - represent as object
    result = newJObject()
    result["type"] = newJString("object")
    result["description"] = newJString("Tuple type")
  of nnkObjectTy, nnkRefTy:
    # Object type
    result = newJObject()
    result["type"] = newJString("object")
    result["description"] = newJString("Object type")
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

# Generate wrapper code that extracts arguments from JSON and calls the original proc
proc generateArgumentExtraction(params: NimNode, procName: NimNode): NimNode =
  result = newStmtList()
  
  # Skip first param (return type) and generate extraction for each parameter
  for i in 1..<params.len:
    let param = params[i]
    if param.kind == nnkIdentDefs:
      let paramType = param[^2]  # Type is second to last
      for j in 0..<param.len-2:  # All names except type and default value
        let paramName = param[j]
        let paramNameStr = newLit($paramName)
        
        # Generate type-safe extraction based on parameter type
        # Create args identifier manually to avoid resolution issues
        let argsIdent = newIdentNode("args")
        let extraction = case $paramType:
          of "int", "int8", "int16", "int32", "int64":
            newStmtList(
              newLetStmt(paramName, newCall("getInt", newNimNode(nnkBracketExpr).add(argsIdent, paramNameStr)))
            )
          of "uint", "uint8", "uint16", "uint32", "uint64":
            newStmtList(
              newLetStmt(paramName, newCall("uint", newCall("getInt", newNimNode(nnkBracketExpr).add(argsIdent, paramNameStr))))
            )
          of "float", "float32", "float64":
            newStmtList(
              newLetStmt(paramName, newCall("getFloat", newNimNode(nnkBracketExpr).add(argsIdent, paramNameStr)))
            )
          of "string":
            newStmtList(
              newLetStmt(paramName, newCall("getStr", newNimNode(nnkBracketExpr).add(argsIdent, paramNameStr)))
            )
          of "bool":
            newStmtList(
              newLetStmt(paramName, newCall("getBool", newNimNode(nnkBracketExpr).add(argsIdent, paramNameStr)))
            )
          else:
            # Handle seq types and complex types
            if paramType.kind == nnkBracketExpr and $paramType[0] == "seq":
              let getElemsCall = newCall("getElems", newNimNode(nnkBracketExpr).add(argsIdent, paramNameStr))
              let mapItCall = newCall("mapIt", getElemsCall, newCall("getStr", newIdentNode("it")))
              newStmtList(newLetStmt(paramName, mapItCall))
            else:
              newStmtList(
                newLetStmt(paramName, newCall("$", newNimNode(nnkBracketExpr).add(argsIdent, paramNameStr)))
              )
        
        result.add(extraction)

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
  discard actualProcDef[6]       # Body (not used in tool generation)
  
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
  
  # Generate argument extraction code
  let argumentExtraction = generateArgumentExtraction(params, procName)
  
  # Build parameter list for calling the original proc
  var callArgs = newSeq[NimNode]()
  for i in 1..<params.len:
    let param = params[i]
    if param.kind == nnkIdentDefs:
      for j in 0..<param.len-2:
        callArgs.add(param[j])
  
  # Generate the call to the original procedure
  let procCall = if callArgs.len > 0:
    newCall(procName, callArgs)
  else:
    newCall(procName)
    
  result = newStmtList()
  
  # Add the original proc definition first
  result.add(actualProcDef)
  
  # Create tool definition and wrapper
  result.add(quote do:
    # Create the tool definition - parse schema at runtime
    let tool = McpTool(
      name: `toolName`,
      description: some(`description`),
      inputSchema: parseJson(`schemaStr`)
    )
    
    # Create wrapper that calls the actual proc with proper argument extraction
    proc `wrapperName`(args: JsonNode): McpToolResult =
      try:
        # Validate that all required arguments are present
        if args.kind != JObject:
          return McpToolResult(content: @[createTextContent("Error: Arguments must be a JSON object")])
        
        # Extract arguments with type conversion
        `argumentExtraction`
        
        # Call the original procedure
        let result = `procCall`
        return McpToolResult(content: @[createTextContent($result)])
          
      except JsonKindError as e:
        return McpToolResult(content: @[createTextContent("Error: Invalid argument type - " & e.msg)])
      except KeyError as e:
        return McpToolResult(content: @[createTextContent("Error: Missing required argument - " & e.msg)])
      except Exception as e:
        return McpToolResult(content: @[createTextContent("Error: " & e.msg)])
    
    # Register the tool using the global server instance
    currentMcpServer.registerTool(tool, `wrapperName`)
  )

# Context-aware tool macro for tools that need request context
macro mcpToolWithContext*(procDef: untyped): untyped =
  # Similar to mcpTool but generates context-aware wrapper
  var actualProcDef: NimNode
  if procDef.kind == nnkStmtList and procDef.len > 0 and procDef[0].kind == nnkProcDef:
    actualProcDef = procDef[0]
  elif procDef.kind == nnkProcDef:
    actualProcDef = procDef
  else:
    error("Expected a proc definition", procDef)
  
  let procName = actualProcDef[0]
  let params = actualProcDef[3]
  
  # Verify first parameter is McpRequestContext
  if params.len < 2 or $params[1][^2] != "McpRequestContext":
    error("Context-aware tools must have McpRequestContext as first parameter", procDef)
  
  let toolName = $procName
  let docComment = extractDocComment(actualProcDef).splitLines()[0].strip()
  let description = if docComment.len > 0: docComment else: "Auto-generated context-aware tool: " & toolName
  
  # Generate schema excluding the context parameter
  var modifiedParams = newNimNode(nnkFormalParams)
  modifiedParams.add(params[0])  # Return type
  for i in 2..<params.len:  # Skip context parameter
    modifiedParams.add(params[i])
  
  let inputSchema = generateInputSchema(modifiedParams)
  let wrapperName = ident("tool_" & toolName & "_context_wrapper")
  let schemaStr = $inputSchema
  
  # Generate argument extraction excluding context
  let argumentExtraction = generateArgumentExtraction(modifiedParams, procName)
  
  # Build call args including context
  var callArgs = @[ident("ctx")]
  for i in 2..<params.len:
    let param = params[i]
    if param.kind == nnkIdentDefs:
      for j in 0..<param.len-2:
        callArgs.add(param[j])
  
  let procCall = newCall(procName, callArgs)
  
  result = newStmtList()
  result.add(actualProcDef)
  
  result.add(quote do:
    let tool = McpTool(
      name: `toolName`,
      description: some(`description`),
      inputSchema: parseJson(`schemaStr`)
    )
    
    proc `wrapperName`(args: JsonNode): McpToolResult =
      try:
        let ctx = newMcpRequestContext()
        if args.kind != JObject:
          return McpToolResult(content: @[createTextContent("Error: Arguments must be a JSON object")])
        
        `argumentExtraction`
        let result = `procCall`
        return McpToolResult(content: @[createTextContent($result)])
      except Exception as e:
        return McpToolResult(content: @[createTextContent("Error: " & e.msg)])
    
    currentMcpServer.registerTool(tool, `wrapperName`)
  )

# Global server instance for macro access 
# WARNING: This is internal to the macro system - users should not access this directly
var currentMcpServer*: McpServer

# Server creation template with advanced tool registration
template mcpServer*(name: string, version: string, body: untyped): untyped =
  let mcpServerInstance* = newMcpServer(name, version)
  currentMcpServer = mcpServerInstance
  body
  
  proc runServer*(transport: McpTransportConfig = StdioTransport()) =
    case transport.kind:
    of mtStdio:
      mcpServerInstance.runStdio()
    of mtHttp:
      let authConfig = if transport.tokenValidator != nil:
                        newAuthConfig(transport.tokenValidator, transport.requireHttps)
                      else:
                        newAuthConfig()
      mcpServerInstance.runHttp(transport.port, transport.host, authConfig)
    of mtWebSocket:
      let authConfig = if transport.wsTokenValidator != nil:
                        newAuthConfig(transport.wsTokenValidator, transport.wsRequireHttps)
                      else:
                        newAuthConfig()
      mcpServerInstance.runWebSocket(transport.wsPort, transport.wsHost, authConfig)


# Simple resource registration template  
template mcpResource*(uri: string, name: string, description: string, handler: untyped): untyped =
  let resource = McpResource(
    uri: uri,
    name: name,
    description: some(description)
  )
  
  proc resourceHandler(uriParam: string): McpResourceContents =
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
  
  proc promptHandler(nameParam: string, args: Table[string, JsonNode]): McpGetPromptResult =
    let messages = handler(nameParam, args)
    return McpGetPromptResult(messages: messages)
  
  mcpServerInstance.registerPrompt(prompt, promptHandler)