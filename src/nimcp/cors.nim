import mummy

proc defaultCorsHeaders*(): HttpHeaders =
  ## Returns default CORS headers for MCP transports
  result["Access-Control-Allow-Origin"] = "*"
  result["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
  result["Access-Control-Allow-Headers"] = "Content-Type, Accept, Origin, Authorization"

proc corsHeadersFor*(methods: string): HttpHeaders =
  ## Returns CORS headers with custom allowed methods
  result = defaultCorsHeaders()
  result["Access-Control-Allow-Methods"] = methods

proc corsHeadersFor*(methods: string, headers: string): HttpHeaders =
  ## Returns CORS headers with custom allowed methods and headers
  result = defaultCorsHeaders()
  result["Access-Control-Allow-Methods"] = methods
  result["Access-Control-Allow-Headers"] = headers