#!/bin/bash

# Test script for macro composition example
# Sends initialize command and tools list command to the MCP server

EXAMPLE_PATH="examples/macro_composition_example.nim"

# Compile the example first
echo "Compiling $EXAMPLE_PATH..."
nim c "$EXAMPLE_PATH"

if [ $? -ne 0 ]; then
    echo "Compilation failed"
    exit 1
fi

# Run the compiled example and send MCP commands
echo "Running MCP server and sending commands..."

# Create a temporary file with the commands
cat > /tmp/mcp_commands.json << 'EOF'
{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {"roots": {"listChanged": true}, "sampling": {}}}}
{"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
EOF

# Send commands to the server
"${EXAMPLE_PATH%%.nim}" < /tmp/mcp_commands.json

# Clean up
rm -f /tmp/mcp_commands.json "${EXAMPLE_PATH%%.nim}"