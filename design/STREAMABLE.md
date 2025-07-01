So implementing streamable http as a new Transport is simply making sure the server can return chunked header as encoding (or is it the client specifying that?) and then simply feed chunks without closing? And that is it?

1. HTTP/1.1 with Transfer-Encoding: chunked
   * Send Transfer-Encoding: chunked header
   * Write data in chunks without closing connection
   * Client reads chunks as they arrive

Yes, exactly! It's that simple for the basic implementation:

Server side:

Set Transfer-Encoding: chunked header in response
Write data chunks without closing the connection
Each chunk prefixed with its size in hex + \r\n
End with 0\r\n\r\n when done
Client side:

Reads chunks as they arrive
Parses each chunk (removing size headers)
Keeps connection open until server signals end
Who sets the header: The server sets Transfer-Encoding: chunked - it's telling the client "I'm going to send you data in chunks rather than all at once with Content-Length."

Example flow:

Client: POST /rpc HTTP/1.1

Server: HTTP/1.1 200 OK
        Transfer-Encoding: chunked
        
        1A\r\n
        {"jsonrpc":"2.0","id":1}\r\n
        1B\r\n  
        {"jsonrpc":"2.0","id":2}\r\n
        0\r\n
        \r\n
        
That's the core mechanism.