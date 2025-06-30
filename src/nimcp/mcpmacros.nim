## Powerful macros for easy MCP server creation

import macros, asyncdispatch, json, tables, options, strutils, typetraits
import types, server, protocol, auth, mummy_transport, websocket_transport

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

# Generate JSON schema from proc parameters, skipping first parameter (for context-aware tools)
proc generateInputSchemaSkipFirst(params: NimNode): JsonNode =
  var properties = newJObject()
  var required = newJArray()
  
  # Skip first param (implicit result) and second param (context), start from index 2
  for i in 2..<params.len:
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
# Supports both regular tools and context-aware tools with automatic detection
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
  
  # Check if this is a context-aware tool by examining first parameter
  var isContextAware = false
  var contextParamName = ""
  if params.len > 1:  # Has parameters beyond return type
    let firstParam = params[1]
    if firstParam.kind == nnkIdentDefs and firstParam.len >= 2:
      let paramType = firstParam[^2]
      if paramType.kind == nnkIdent and $paramType == "McpRequestContext":
        isContextAware = true
        contextParamName = $firstParam[0]
  
  # Generate input schema from parameters (skip context parameter for schema)
  let inputSchema = if isContextAware: 
                      generateInputSchemaSkipFirst(params) 
                    else: 
                      generateInputSchema(params)
  
  # Generate the wrapper proc name to avoid conflicts
  let wrapperName = ident("tool_" & toolName & "_wrapper")
  
  # Convert the compile-time schema to a runtime string representation
  let schemaStr = $inputSchema
  
  result = newStmtList()
  
  # Create the tool definition with unique name
  let toolIdent = ident("tool_" & toolName)
  result.add(quote do:
    let `toolIdent` = McpTool(
      name: `toolName`,
      description: some(`description`),
      inputSchema: parseJson(`schemaStr`)
    )
  )
  
  # Build wrapper procedure - different signature for context-aware vs regular tools
  if isContextAware:
    # Context-aware wrapper: proc(ctx: McpRequestContext, jsonArgs: JsonNode): McpToolResult
    let ctxParam = newIdentDefs(ident("ctx"), bindSym("McpRequestContext"))
    let jsonArgsParam = newIdentDefs(ident("jsonArgs"), bindSym("JsonNode"))
    let returnType = bindSym("McpToolResult")
    
    # Generate argument extractions (skip context parameter)
    var argExtractions = newSeq[NimNode]()
    argExtractions.add(ident("ctx"))  # Add context as first argument
    
    for i in 2..<params.len:  # Skip result and context params
      let param = params[i]
      if param.kind == nnkIdentDefs:
        let paramType = param[^2]
        for j in 0..<param.len-2:
          let paramName = $param[j]
          if paramName != "":
            let paramNameLit = newLit(paramName)
            let jsonArgsIdent = ident("jsonArgs")
            case $paramType:
            of "int", "int8", "int16", "int32", "int64":
              argExtractions.add(newCall("getInt", newCall("[]", jsonArgsIdent, paramNameLit)))
            of "uint", "uint8", "uint16", "uint32", "uint64":
              argExtractions.add(newCall("getInt", newCall("[]", jsonArgsIdent, paramNameLit)))
            of "float", "float32", "float64":
              argExtractions.add(newCall("getFloat", newCall("[]", jsonArgsIdent, paramNameLit)))
            of "string":
              argExtractions.add(newCall("getStr", newCall("[]", jsonArgsIdent, paramNameLit)))
            of "bool":
              argExtractions.add(newCall("getBool", newCall("[]", jsonArgsIdent, paramNameLit)))
            else:
              argExtractions.add(newCall("getStr", newCall("[]", jsonArgsIdent, paramNameLit)))

    # Build the function call and wrapper body
    let functionCall = newCall(procName, argExtractions)
    let resultAssign = newLetStmt(ident("functionResult"), functionCall)
    let returnStmt = nnkReturnStmt.newTree(
      nnkObjConstr.newTree(
        bindSym("McpToolResult"),
        nnkExprColonExpr.newTree(
          ident("content"),
          newCall(bindSym("@"), newNimNode(nnkBracket).add(
            newCall(bindSym("createTextContent"), ident("functionResult"))
          ))
        )
      )
    )
    
    let wrapperBody = newStmtList(resultAssign, returnStmt)
    let wrapperProc = newProc(
      wrapperName,
      [returnType, ctxParam, jsonArgsParam],
      wrapperBody,
      nnkProcDef
    )
    
    result.add(wrapperProc)
    
    # Add the original function definition first so it's available when the wrapper is compiled
    result.insert(1, actualProcDef)
    
    # Register the context-aware tool
    result.add(quote do:
      currentMcpServer.registerToolWithContext(`toolIdent`, `wrapperName`)
    )
  else:
    # Regular wrapper: proc(jsonArgs: JsonNode): McpToolResult
    let jsonArgsParam = newIdentDefs(ident("jsonArgs"), bindSym("JsonNode"))
    let returnType = bindSym("McpToolResult")
    
    # Generate argument extractions
    var argExtractions = newSeq[NimNode]()
    for i in 1..<params.len:
      let param = params[i]
      if param.kind == nnkIdentDefs:
        let paramType = param[^2]
        for j in 0..<param.len-2:
          let paramName = $param[j]
          if paramName != "":
            let paramNameLit = newLit(paramName)
            let jsonArgsIdent = ident("jsonArgs")
            case $paramType:
            of "int", "int8", "int16", "int32", "int64":
              argExtractions.add(newCall("getInt", newCall("[]", jsonArgsIdent, paramNameLit)))
            of "uint", "uint8", "uint16", "uint32", "uint64":
              argExtractions.add(newCall("getInt", newCall("[]", jsonArgsIdent, paramNameLit)))
            of "float", "float32", "float64":
              argExtractions.add(newCall("getFloat", newCall("[]", jsonArgsIdent, paramNameLit)))
            of "string":
              argExtractions.add(newCall("getStr", newCall("[]", jsonArgsIdent, paramNameLit)))
            of "bool":
              argExtractions.add(newCall("getBool", newCall("[]", jsonArgsIdent, paramNameLit)))
            else:
              argExtractions.add(newCall("getStr", newCall("[]", jsonArgsIdent, paramNameLit)))

    # Build the function call and wrapper body
    let functionCall = newCall(procName, argExtractions)
    let resultAssign = newLetStmt(ident("functionResult"), functionCall)
    let returnStmt = nnkReturnStmt.newTree(
      nnkObjConstr.newTree(
        bindSym("McpToolResult"),
        nnkExprColonExpr.newTree(
          ident("content"),
          newCall(bindSym("@"), newNimNode(nnkBracket).add(
            newCall(bindSym("createTextContent"), ident("functionResult"))
          ))
        )
      )
    )
    
    let wrapperBody = newStmtList(resultAssign, returnStmt)
    let wrapperProc = newProc(
      wrapperName,
      [returnType, jsonArgsParam],
      wrapperBody,
      nnkProcDef
    )
    
    result.add(wrapperProc)
    
    # Add the original function definition first so it's available when the wrapper is compiled
    result.insert(1, actualProcDef)
    
    # Register the regular tool
    result.add(quote do:
      currentMcpServer.registerTool(`toolIdent`, `wrapperName`)
    )

# Global server instance for macro access
var currentMcpServer*: McpServer

# Server creation template with advanced tool registration
template mcpServer*(name: string, version: string, body: untyped): untyped =
  let mcpServerInstance {.inject.} = newMcpServer(name, version)
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
  
  when isMainModule:
    runServer()


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