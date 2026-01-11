## Test for output schema extraction
import unittest, json, options, macros
import ../src/nimcp/mcpmacros

# Test tool with output schema
mcpTool:
  proc testToolWithOutputSchema(param1: string, param2: int = 42): string {.gcsafe.} =
    ## This is a test tool with output schema.
    ## - param1: First parameter description
    ## - param2: Second parameter with default
    ##
    ## returns: {
    ##   "type": "object",
    ##   "properties": {
    ##     "result": {"type": "string", "description": "The result string"},
    ##     "count": {"type": "integer", "description": "Number of items processed"}
    ##   },
    ##   "required": ["result", "count"]
    ## }
    return "Test result"

# Test tool without output schema (backward compatibility)
mcpTool:
  proc testToolWithoutOutputSchema(param: string): string {.gcsafe.} =
    ## This tool has no output schema for backward compatibility test.
    ## - param: Input parameter
    return "No schema"

suite "Output schema extraction":
  test "Extracts output schema from doc comments":
    # Verify the tool was created with output schema
    # The tool should be available as 'tool_testToolWithOutputSchema'
    # Check that outputSchema is not None
    check false  # Placeholder - need to access the tool to verify

  test "Handles tools without output schema":
    # Verify tools without output schema still work (backward compatibility)
    check false  # Placeholder
