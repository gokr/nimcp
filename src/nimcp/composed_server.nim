## ComposedServer implementation for NimCP
##
## This module provides functionality for composing multiple MCP servers
## into a single server that can route requests to the appropriate mounted servers.

import json, tables, options, strutils
import types, protocol, context, server, stdio_transport, logging

type
  MountPoint* = object
    ## Represents a mount point for a server
    path*: string
    server*: McpServer
    prefix*: Option[string]  # Optional prefix for tool/resource names

  ComposedServer* = ref object
    ## A standalone server that composes multiple MCP servers into a single interface
    ## Uses composition over inheritance - owns and delegates to child servers
    name*: string
    version*: string
    mountPoints*: seq[MountPoint]
    pathMappings*: Table[string, MountPoint]
    logger*: Logger
    initialized*: bool

  ServerNamespace* = object
    ## Namespace configuration for mounted servers
    toolPrefix*: Option[string]
    resourcePrefix*: Option[string]
    promptPrefix*: Option[string]

# Basic mount point and server creation
proc newMountPoint*(path: string, server: McpServer, prefix: Option[string] = none(string)): MountPoint =
  ## Create a new mount point
  MountPoint(
    path: path,
    server: server,  # Direct ref assignment instead of unsafe pointer cast
    prefix: prefix
  )

proc newComposedServer*(name: string, version: string): ComposedServer =
  ## Create a new composed server that can mount other servers
  ## Uses composition - no inheritance, owns child servers
  new(result)
  result.name = name
  result.version = version
  result.initialized = false
  result.mountPoints = @[]
  result.pathMappings = initTable[string, MountPoint]()

  # Initialize logging with server-specific component name
  result.logger = newLogger(llInfo)
  result.logger.setComponent("mcp-composed-server-" & name)
  result.logger.setupChroniclesLogging()
  
  # Log server initialization
  result.logger.info("MCP composed server initialized", 
    context = {"name": %name, "version": %version}.toTable)

# Server mounting and unmounting
proc mountServer*(composed: ComposedServer, mountPoint: MountPoint) =
  ## Mount a server at the specified mount point
  if mountPoint.path in composed.pathMappings:
    raise newException(ValueError, "Mount point already exists: " & mountPoint.path)
  
  composed.mountPoints.add(mountPoint)
  composed.pathMappings[mountPoint.path] = mountPoint

proc mountServerAt*(composed: ComposedServer, path: string, server: McpServer, prefix: Option[string] = none(string)) =
  ## Mount a server at the specified path with optional prefix
  let mountPoint = newMountPoint(path, server, prefix)
  composed.mountServer(mountPoint)

proc unmountServer*(composed: ComposedServer, path: string): bool =
  ## Unmount a server from the specified path, returns true if unmounted
  if path notin composed.pathMappings:
    result = false
    return

  composed.pathMappings.del(path)

  # Remove from mountPoints sequence
  for i in countdown(composed.mountPoints.len - 1, 0):
    if composed.mountPoints[i].path == path:
      composed.mountPoints.del(i)
      break

  return true

# Mount point resolution
proc findMountPointForTool*(composed: ComposedServer, toolName: string): Option[MountPoint] =
  ## Find the mount point that should handle a given tool name
  for mountPoint in composed.mountPoints:
    if mountPoint.prefix.isSome:
      let prefix = mountPoint.prefix.get()
      if toolName.startsWith(prefix):
        result = some(mountPoint)
        return
    else:
      # Check if the mounted server has this tool
      let server = mountPoint.server
      let tools = server.getRegisteredToolNames()
      if toolName in tools:
        result = some(mountPoint)
        return

  return none(MountPoint)

proc findMountPointForResource*(composed: ComposedServer, uri: string): Option[MountPoint] =
  ## Find the mount point that should handle a given resource URI
  for mountPoint in composed.mountPoints:
    if mountPoint.prefix.isSome:
      let prefix = mountPoint.prefix.get()
      if uri.startsWith(mountPoint.path) or uri.startsWith(prefix):
        result = some(mountPoint)
        return
    else:
      # Check if the mounted server has this resource
      let server = mountPoint.server
      let resources = server.getRegisteredResourceUris()
      if uri in resources:
        result = some(mountPoint)
        return

  return none(MountPoint)

proc findMountPointForPrompt*(composed: ComposedServer, promptName: string): Option[MountPoint] =
  ## Find the mount point that should handle a given prompt name
  for mountPoint in composed.mountPoints:
    if mountPoint.prefix.isSome:
      let prefix = mountPoint.prefix.get()
      if promptName.startsWith(prefix):
        return some(mountPoint)
    else:
      # Check if the mounted server has this prompt
      let server = mountPoint.server
      let prompts = server.getRegisteredPromptNames()
      if promptName in prompts:
        return some(mountPoint)
  
  return none(MountPoint)

# Utility functions
proc stripPrefix*(name: string, prefix: Option[string]): string =
  ## Strip prefix from a name if present
  if prefix.isSome:
    let prefixStr = prefix.get()
    if name.startsWith(prefixStr):
      return name[prefixStr.len..^1]
  return name

proc addPrefix*(name: string, prefix: Option[string]): string =
  ## Add prefix to a name if specified
  if prefix.isSome:
    return prefix.get() & name
  return name

proc listMountPoints*(composed: ComposedServer): seq[MountPoint] =
  ## List all mount points
  return composed.mountPoints

proc getMountedServerInfo*(composed: ComposedServer): Table[string, JsonNode] =
  ## Get information about all mounted servers
  result = initTable[string, JsonNode]()
  
  for mountPoint in composed.mountPoints:
    let server = mountPoint.server
    var info = newJObject()
    info["path"] = %mountPoint.path
    info["serverName"] = %server.serverInfo.name
    info["serverVersion"] = %server.serverInfo.version
    if mountPoint.prefix.isSome:
      info["prefix"] = %mountPoint.prefix.get()
    info["toolCount"] = %server.getRegisteredToolNames().len
    info["resourceCount"] = %server.getRegisteredResourceUris().len
    info["promptCount"] = %server.getRegisteredPromptNames().len
    
    result[mountPoint.path] = info

# ComposedServer JSON-RPC handlers
proc handleToolsList*(composed: ComposedServer): JsonNode =
  ## Handle tools/list request by aggregating tools from all mounted servers
  var allTools: seq[JsonNode] = @[]
  for mountPoint in composed.mountPoints:
    let server = mountPoint.server
    if server.isNil:
      raise newException(ValueError, "Mounted server is nil for path: " & mountPoint.path)
    # Call server's method directly - much more efficient than JSON-RPC overhead
    let toolsData = server.handleToolsList()
    if toolsData.hasKey("tools"):
      let tools = toolsData["tools"]
      for toolJson in tools.getElems():
        var prefixedTool = toolJson.copy()
        let originalName = toolJson["name"].getStr()
        let prefixedName = addPrefix(originalName, mountPoint.prefix)
        prefixedTool["name"] = %prefixedName
        allTools.add(prefixedTool)
  return %*{"tools": allTools}

proc handleToolsCall*(composed: ComposedServer, params: JsonNode, ctx: McpRequestContext = nil): JsonNode =
  ## Handle tools/call request by routing to the appropriate mounted server
  let toolName = requireStringField(params, "name")
  if toolName.len == 0:
    raise newException(ValueError, "Tool name cannot be empty")

  # Find the mount point for this tool
  let mountPointOpt = composed.findMountPointForTool(toolName)
  if mountPointOpt.isNone:
    raise newException(ValueError, "Tool not found: " & toolName)
  
  let mountPoint = mountPointOpt.get()
  let server = mountPoint.server
  
  # Strip the prefix from the tool name before calling the mounted server
  let actualToolName = stripPrefix(toolName, mountPoint.prefix)
  
  # Create new params with the stripped tool name
  var newParams = params.copy()
  newParams["name"] = %actualToolName
  
  # Call server's method directly - much more efficient than JSON-RPC overhead
  return server.handleToolsCall(newParams, ctx)

proc handleResourcesList*(composed: ComposedServer): JsonNode =
  ## Handle resources/list request by aggregating resources from all mounted servers
  var allResources: seq[JsonNode] = @[]
  
  for mountPoint in composed.mountPoints:
    let server = mountPoint.server
    
    # Call server's method directly - much more efficient than JSON-RPC overhead
    let resourcesData = server.handleResourcesList()
    
    if resourcesData.hasKey("resources"):
      let resources = resourcesData["resources"]
      for resourceJson in resources.getElems():
        var prefixedResource = resourceJson.copy()
        let originalUri = resourceJson["uri"].getStr()
        let prefixedUri = addPrefix(originalUri, mountPoint.prefix)
        prefixedResource["uri"] = %prefixedUri
        allResources.add(prefixedResource)
  
  return %*{"resources": allResources}

proc handleResourcesRead*(composed: ComposedServer, params: JsonNode, ctx: McpRequestContext = nil): JsonNode =
  ## Handle resources/read request by routing to the appropriate mounted server
  let uri = requireStringField(params, "uri")
  if uri.len == 0:
    raise newException(ValueError, "Resource URI cannot be empty")

  # Find the mount point for this resource
  let mountPointOpt = composed.findMountPointForResource(uri)
  if mountPointOpt.isNone:
    raise newException(ValueError, "Resource not found: " & uri)
  
  let mountPoint = mountPointOpt.get()
  let server = mountPoint.server
  
  # Strip the prefix from the URI before calling the mounted server
  let actualUri = stripPrefix(uri, mountPoint.prefix)
  
  # Create new params with the stripped URI
  var newParams = params.copy()
  newParams["uri"] = %actualUri
  
  # Call server's method directly - much more efficient than JSON-RPC overhead
  return server.handleResourcesRead(newParams, ctx)

proc handlePromptsList*(composed: ComposedServer): JsonNode =
  ## Handle prompts/list request by aggregating prompts from all mounted servers
  var allPrompts: seq[JsonNode] = @[]
  
  for mountPoint in composed.mountPoints:
    let server = mountPoint.server
    
    # Call server's method directly - much more efficient than JSON-RPC overhead
    let promptsData = server.handlePromptsList()
    
    if promptsData.hasKey("prompts"):
      let prompts = promptsData["prompts"]
      for promptJson in prompts.getElems():
        var prefixedPrompt = promptJson.copy()
        let originalName = promptJson["name"].getStr()
        let prefixedName = addPrefix(originalName, mountPoint.prefix)
        prefixedPrompt["name"] = %prefixedName
        allPrompts.add(prefixedPrompt)
  
  return %*{"prompts": allPrompts}

proc handlePromptsGet*(composed: ComposedServer, params: JsonNode, ctx: McpRequestContext = nil): JsonNode =
  ## Handle prompts/get request by routing to the appropriate mounted server
  let promptName = requireStringField(params, "name")
  if promptName.len == 0:
    raise newException(ValueError, "Prompt name cannot be empty")

  # Find the mount point for this prompt
  let mountPointOpt = composed.findMountPointForPrompt(promptName)
  if mountPointOpt.isNone:
    raise newException(ValueError, "Prompt not found: " & promptName)
  
  let mountPoint = mountPointOpt.get()
  let server = mountPoint.server
  
  # Strip the prefix from the prompt name before calling the mounted server
  let actualPromptName = stripPrefix(promptName, mountPoint.prefix)
  
  # Create new params with the stripped prompt name
  var newParams = params.copy()
  newParams["name"] = %actualPromptName
  
  # Call server's method directly - much more efficient than JSON-RPC overhead
  return server.handlePromptsGet(newParams, ctx)

proc buildCapabilities*(composed: ComposedServer): McpCapabilities =
  ## Build capabilities by aggregating from all mounted servers
  result = McpCapabilities()
  
  # Check if any mounted server has tools
  var hasTools = false
  var hasResources = false
  var hasPrompts = false
  
  for mountPoint in composed.mountPoints:
    let server = mountPoint.server
    if server.getRegisteredToolNames().len > 0:
      hasTools = true
    if server.getRegisteredResourceUris().len > 0:
      hasResources = true
    if server.getRegisteredPromptNames().len > 0:
      hasPrompts = true
  
  # Set capabilities based on what we found
  if hasTools:
    result.tools = some(McpToolsCapability())
  if hasResources:
    result.resources = some(McpResourcesCapability())
  if hasPrompts:
    result.prompts = some(McpPromptsCapability())

proc handleRequest*(composed: ComposedServer, request: JsonRpcRequest): JsonRpcResponse =
  ## Main request handler for ComposedServer that routes requests appropriately
  try:
    let id = if request.id.isSome: request.id.get() else: JsonRpcId(kind: jridString, str: "")
    let requestCtx = newMcpRequestContext()
    let responseData = case request.`method`
    of "initialize":
      # Initialize this composed server first
      composed.initialized = true
      
      # Then propagate initialization to all mounted servers using direct method calls
      for mountPoint in composed.mountPoints:
        if not mountPoint.server.initialized:
          let initParams = request.params.get(newJObject())
          discard mountPoint.server.handleInitialize(initParams)
          # Ensure child initialization succeeded
          if not mountPoint.server.initialized:
            raise newException(ValueError, "Failed to initialize mounted server: " & mountPoint.path)
      
      # Return standard initialize response with aggregated capabilities
      let serverInfo = McpServerInfo(name: composed.name, version: composed.version)
      let capabilities = composed.buildCapabilities()
      createInitializeResponseJson(serverInfo, capabilities)
    of "tools/list":
      composed.handleToolsList()
    of "tools/call":
      composed.handleToolsCall(request.params.get(newJObject()), requestCtx)
    of "resources/list":
      composed.handleResourcesList()
    of "resources/read":
      composed.handleResourcesRead(request.params.get(newJObject()), requestCtx)
    of "prompts/list":
      composed.handlePromptsList()
    of "prompts/get":
      composed.handlePromptsGet(request.params.get(newJObject()), requestCtx)
    of "ping":
      newJObject()
    else:
      raise newException(ValueError, "Method not found: " & request.`method`)

    return JsonRpcResponse(
      jsonrpc: "2.0",
      id: id,
      result: some(responseData)
    )
  except Exception as e:
    let requestId = if request.id.isSome: request.id.get() else: JsonRpcId(kind: jridString, str: "")
    return createInternalError(requestId, e.msg)

proc handleNotification*(composed: ComposedServer, request: JsonRpcRequest) {.gcsafe.} =
  ## Handle notification - ComposedServer doesn't need special notification handling
  discard

proc shutdown*(composed: ComposedServer) =
  ## Shutdown composed server and all mounted servers
  for mountPoint in composed.mountPoints:
    mountPoint.server.shutdown()

