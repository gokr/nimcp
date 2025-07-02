## Example demonstrating Resource URI Templates in NimCP
## Shows how to use dynamic URI patterns with parameter extraction

import ../src/nimcp, tables, options

proc handleUserResource(ctx: McpRequestContext, uri: string, params: Table[string, string]): McpResourceContents =
  ## Handle user resource requests with extracted user ID
  let userId = params.getOrDefault("id", "unknown")
  
  # Log the request with context
  ctx.logMessage("info", "Accessing user resource for user: " & userId)
  
  result = McpResourceContents(
    uri: uri,
    mimeType: some("application/json"),
    content: @[McpContent(
      `type`: "text",
      kind: TextContent,
      text: """{"id": """ & userId & """, "name": "User """ & userId & """, "email": "user""" & userId & """@example.com"}"""
    )]
  )

proc handleFileResource(ctx: McpRequestContext, uri: string, params: Table[string, string]): McpResourceContents =
  ## Handle file resource requests with extracted file path
  let filePath = params.getOrDefault("path", "unknown")
  
  ctx.logMessage("info", "Accessing file resource: " & filePath)
  
  result = McpResourceContents(
    uri: uri,
    mimeType: some("text/plain"),
    content: @[McpContent(
      `type`: "text", 
      kind: TextContent,
      text: "Content of file: " & filePath
    )]
  )

proc handleProjectResource(ctx: McpRequestContext, uri: string, params: Table[string, string]): McpResourceContents =
  ## Handle nested project/issue resources
  let projectId = params.getOrDefault("projectId", "unknown")
  let issueId = params.getOrDefault("issueId", "unknown")
  
  ctx.logMessage("info", "Accessing project " & projectId & " issue " & issueId)
  
  result = McpResourceContents(
    uri: uri,
    mimeType: some("application/json"),
    content: @[McpContent(
      `type`: "text",
      kind: TextContent,
      text: """{"projectId": """ & projectId & """, "issueId": """ & issueId & """, "title": "Issue """ & issueId & """ in Project """ & projectId & """"}"""
    )]
  )

when isMainModule:
  echo "=== Resource URI Templates Example ==="
  
  # Create server
  let server = newMcpServer("resource-templates-example", "1.0.0")
  
  # Register resource templates with parameter extraction
  server.registerResourceTemplateWithContext(
    McpResourceTemplate(
      uriTemplate: "/users/{id}",
      name: "User Resource",
      description: some("Access user information by ID"),
      mimeType: some("application/json")
    ),
    handleUserResource
  )
  
  server.registerResourceTemplateWithContext(
    McpResourceTemplate(
      uriTemplate: "/files/{path}",
      name: "File Resource", 
      description: some("Access file content by path"),
      mimeType: some("text/plain")
    ),
    handleFileResource
  )
  
  server.registerResourceTemplateWithContext(
    McpResourceTemplate(
      uriTemplate: "/projects/{projectId}/issues/{issueId}",
      name: "Project Issue Resource",
      description: some("Access project issues"),
      mimeType: some("application/json")
    ),
    handleProjectResource
  )
  
  echo "Resource templates registered:"
  echo "- /users/{id} - User resources with dynamic ID"
  echo "- /files/{path} - File resources with dynamic path"
  echo "- /projects/{projectId}/issues/{issueId} - Nested project issues"
  echo ""
  
  # Demo URI template matching
  let templates = server.resourceTemplates
  
  echo "Testing URI template matching:"
  
  # Test user template
  let userMatch = templates.findTemplateWithContext("/users/123")
  if userMatch.isSome:
    let (resourceTemplate, params, _) = userMatch.get()
    echo "✓ Matched /users/123 -> template: " & resourceTemplate.uriTemplate & ", params: " & $params
  
  # Test file template
  let fileMatch = templates.findTemplateWithContext("/files/config.json")
  if fileMatch.isSome:
    let (resourceTemplate, params, _) = fileMatch.get()
    echo "✓ Matched /files/config.json -> template: " & resourceTemplate.uriTemplate & ", params: " & $params
  
  # Test project template
  let projectMatch = templates.findTemplateWithContext("/projects/abc/issues/456")
  if projectMatch.isSome:
    let (resourceTemplate, params, _) = projectMatch.get()
    echo "✓ Matched /projects/abc/issues/456 -> template: " & resourceTemplate.uriTemplate & ", params: " & $params
  
  echo ""
  echo "Template validation:"
  echo "- /users/{id} valid: " & $validateTemplate("/users/{id}")
  echo "- /invalid/{} valid: " & $validateTemplate("/invalid/{}")
  
  echo ""
  echo "Template parameters:"
  echo "- /users/{id} params: " & $getTemplateParams("/users/{id}")
  echo "- /projects/{projectId}/issues/{issueId} params: " & $getTemplateParams("/projects/{projectId}/issues/{issueId}")
  
  echo ""
  echo "🎯 Resource URI Templates example completed!"
  echo "This demonstrates dynamic URI matching with parameter extraction."