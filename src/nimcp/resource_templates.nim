## Resource URI Template Implementation for NimCP
## Provides support for dynamic resource URIs with parameter extraction

import tables, strutils, re, options
import types, context

type
  UriTemplateParam* = object
    ## Parameter extracted from a URI template
    name*: string
    value*: string
  
  UriTemplateMatcher* = object
    ## Compiled URI template for efficient matching
    pattern*: Regex
    paramNames*: seq[string]
    uriTemplate*: string
  
  ResourceTemplateHandler* = proc(uri: string, params: Table[string, string]): McpResourceContents {.gcsafe, closure.}
  ResourceTemplateHandlerWithContext* = proc(ctx: McpRequestContext, uri: string, params: Table[string, string]): McpResourceContents {.gcsafe, closure.}

# URI Template parsing and matching
proc compileUriTemplate*(uriTemplate: string): UriTemplateMatcher =
  ## Compile a URI template into a matcher for efficient pattern matching
  ## Example: "/users/{id}/posts/{postId}" -> regex pattern with param extraction
  var regexPattern = uriTemplate
  var paramNames: seq[string] = @[]
  
  # Find all template parameters {paramName}
  let paramRegex = re"\{([^}]*)\}"
  var matches: array[1, string]
  var start = 0
  
  while regexPattern.find(paramRegex, matches, start) != -1:
    let paramName = matches[0]
    if paramName.len == 0:
      raise newException(ValueError, "Invalid template: empty parameter name found")
    paramNames.add(paramName)
    # Replace {paramName} with capture group
    regexPattern = regexPattern.replace("{" & paramName & "}", "([^/]+)")
    start = 0  # Restart search after replacement
  
  # Anchor the pattern to match full URI
  regexPattern = "^" & regexPattern & "$"
  
  UriTemplateMatcher(
    pattern: re(regexPattern),
    paramNames: paramNames,
    uriTemplate: uriTemplate
  )

proc matchUri*(matcher: UriTemplateMatcher, uri: string): Option[Table[string, string]] =
  ## Match a URI against a template and extract parameters
  var matches = newSeq[string](matcher.paramNames.len)
  
  if uri.match(matcher.pattern, matches):
    var params = initTable[string, string]()
    for i, paramName in matcher.paramNames:
      if i < matches.len:
        params[paramName] = matches[i]
    return some(params)

  none(Table[string, string])

proc extractUriParams*(uriTemplate: string, uri: string): Table[string, string] =
  ## Simple utility to extract parameters from URI based on template
  ## Example: template="/users/{id}", uri="/users/123" -> {"id": "123"}
  let matcher = compileUriTemplate(uriTemplate)
  let paramsOpt = matchUri(matcher, uri)
  
  if paramsOpt.isSome:
    return paramsOpt.get()
  else:
    initTable[string, string]()

# Resource template registration and management
type
  ResourceTemplateRegistry* = object
    ## Registry for resource templates with efficient matching
    templates*: seq[tuple[matcher: UriTemplateMatcher, resource: McpResourceTemplate, handler: ResourceTemplateHandler]]
    contextTemplates*: seq[tuple[matcher: UriTemplateMatcher, resource: McpResourceTemplate, handler: ResourceTemplateHandlerWithContext]]

proc newResourceTemplateRegistry*(): ResourceTemplateRegistry =
  ## Create a new resource template registry
  ResourceTemplateRegistry(
    templates: @[],
    contextTemplates: @[]
  )

proc registerTemplate*(registry: var ResourceTemplateRegistry, 
                      resourceTemplate: McpResourceTemplate, 
                      handler: ResourceTemplateHandler) =
  ## Register a resource template with handler
  let matcher = compileUriTemplate(resourceTemplate.uriTemplate)
  registry.templates.add((matcher, resourceTemplate, handler))

proc registerTemplateWithContext*(registry: var ResourceTemplateRegistry,
                                 resourceTemplate: McpResourceTemplate,
                                 handler: ResourceTemplateHandlerWithContext) =
  ## Register a context-aware resource template with handler  
  let matcher = compileUriTemplate(resourceTemplate.uriTemplate)
  registry.contextTemplates.add((matcher, resourceTemplate, handler))

proc findTemplate*(registry: ResourceTemplateRegistry, uri: string): Option[tuple[resourceTemplate: McpResourceTemplate, params: Table[string, string], handler: ResourceTemplateHandler]] =
  ## Find a matching template for the given URI
  for item in registry.templates:
    let paramsOpt = matchUri(item.matcher, uri)
    if paramsOpt.isSome:
      return some((item.resource, paramsOpt.get(), item.handler))

  none(tuple[resourceTemplate: McpResourceTemplate, params: Table[string, string], handler: ResourceTemplateHandler])

proc findTemplateWithContext*(registry: ResourceTemplateRegistry, uri: string): Option[tuple[resourceTemplate: McpResourceTemplate, params: Table[string, string], handler: ResourceTemplateHandlerWithContext]] =
  ## Find a matching context-aware template for the given URI
  for item in registry.contextTemplates:
    let paramsOpt = matchUri(item.matcher, uri)
    if paramsOpt.isSome:
      return some((item.resource, paramsOpt.get(), item.handler))

  none(tuple[resourceTemplate: McpResourceTemplate, params: Table[string, string], handler: ResourceTemplateHandlerWithContext])

proc handleTemplateRequest*(registry: ResourceTemplateRegistry, uri: string): Option[McpResourceContents] =
  ## Handle a resource request using templates, returns none if no template matches
  # Try context-aware templates first
  let contextMatch = registry.findTemplateWithContext(uri)
  if contextMatch.isSome:
    let (_, params, handler) = contextMatch.get()
    let ctx = newMcpRequestContext()
    return some(handler(ctx, uri, params))

  # Try regular templates
  let match = registry.findTemplate(uri)
  if match.isSome:
    let (_, params, handler) = match.get()
    return some(handler(uri, params))

  none(McpResourceContents)

proc handleTemplateRequestWithContext*(registry: ResourceTemplateRegistry, ctx: McpRequestContext, uri: string): Option[McpResourceContents] =
  ## Handle a resource request using templates with provided context
  # Try context-aware templates first
  let contextMatch = registry.findTemplateWithContext(uri)
  if contextMatch.isSome:
    let (_, params, handler) = contextMatch.get()
    return some(handler(ctx, uri, params))

  # Try regular templates with new context
  let match = registry.findTemplate(uri)
  if match.isSome:
    let (_, params, handler) = match.get()
    return some(handler(uri, params))

  none(McpResourceContents)

proc listTemplates*(registry: ResourceTemplateRegistry): seq[McpResourceTemplate] =
  ## List all registered resource templates
  result = @[]
  for item in registry.templates:
    result.add(item.resource)
  for item in registry.contextTemplates:
    result.add(item.resource)

# Template validation utilities
proc validateTemplate*(uriTemplate: string): bool =
  ## Validate that a URI template is well-formed
  try:
    discard compileUriTemplate(uriTemplate)
    true
  except:
    false

proc getTemplateParams*(uriTemplate: string): seq[string] =
  ## Extract parameter names from a URI template
  try:
    let matcher = compileUriTemplate(uriTemplate)
    matcher.paramNames
  except:
    @[]

# Convenience functions for common template patterns
proc userTemplate*(userIdParam: string = "id"): string =
  ## Create a user resource template
  "/users/{" & userIdParam & "}"

proc fileTemplate*(pathParam: string = "path"): string =
  ## Create a file resource template  
  "/files/{" & pathParam & "}"

proc collectionItemTemplate*(collection: string, itemParam: string = "id"): string =
  ## Create a collection item template
  "/" & collection & "/{" & itemParam & "}"

proc nestedTemplate*(parent: string, parentParam: string, child: string, childParam: string): string =
  ## Create a nested resource template
  "/" & parent & "/{" & parentParam & "}/" & child & "/{" & childParam & "}"