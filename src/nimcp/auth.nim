import options, tables, mummy, strutils

type
  TokenValidator* = proc(token: string): bool {.gcsafe.}
  
  AuthConfig* = object
    enabled*: bool
    validator*: TokenValidator
    requireHttps*: bool
    customErrorResponses*: Table[int, string]

proc newAuthConfig*(): AuthConfig =
  ## Create a default authentication configuration (disabled)
  AuthConfig(
    enabled: false,
    validator: nil,
    requireHttps: false,
    customErrorResponses: initTable[int, string]()
  )

proc newAuthConfig*(validator: TokenValidator, requireHttps: bool = false): AuthConfig =
  ## Create an enabled authentication configuration with custom validator
  AuthConfig(
    enabled: true,
    validator: validator,
    requireHttps: requireHttps,
    customErrorResponses: initTable[int, string]()
  )

proc extractBearerToken*(headers: HttpHeaders): Option[string] =
  ## Extract Bearer token from Authorization header
  if "Authorization" in headers:
    let authHeader = headers["Authorization"]
    if authHeader.startsWith("Bearer "):
      return some(authHeader[7..^1].strip())
  return none(string)

proc validateToken*(config: AuthConfig, token: string): bool =
  ## Validate token using configured validator
  if not config.enabled: return true
  if config.validator == nil: return false
  try: config.validator(token) except: false

proc validateRequest*(config: AuthConfig, request: Request): tuple[valid: bool, errorCode: int, errorMsg: string] =
  ## Validate authentication according to MCP specification
  if not config.enabled: return (true, 0, "")
  
  # Check HTTPS requirement
  if config.requireHttps:
    let proto = if "X-Forwarded-Proto" in request.headers: request.headers["X-Forwarded-Proto"] else: "http"
    if not proto.startsWith("https"):
      return (false, 400, "HTTPS required for authentication")
  
  # Extract Bearer token
  let tokenOpt = extractBearerToken(request.headers)
  if tokenOpt.isNone:
    return (false, 401, "Authorization required: Bearer token missing")
  
  let token = tokenOpt.get()
  if token.len == 0:
    return (false, 400, "Malformed authorization: empty token")
  
  # Validate token
  if not config.validateToken(token):
    return (false, 401, "Authorization required: token invalid")
  
  return (true, 0, "")