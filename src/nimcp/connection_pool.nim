## This module provides a generic, thread-safe connection pool.
##
## The `ConnectionPool` type manages a collection of connections of any type `T`,
## where each connection is identified by a unique string ID. All operations
## that access the underlying connection table are protected by a lock to
## ensure safe concurrent access from multiple threads.
##
## It is used by transports that handle multiple client connections, such as
## WebSocket or SSE, to keep track of active connections.

import tables, locks, options

type
  ConnectionPool*[T] = ref object
    connections: Table[string, T]
    lock: Lock

proc newConnectionPool*[T](): ConnectionPool[T] =
  new(result)
  result.connections = initTable[string, T]()
  initLock(result.lock)

proc addConnection*[T](pool: ConnectionPool[T], id: string, connection: T) =
  withLock pool.lock:
    pool.connections[id] = connection

proc removeConnection*[T](pool: ConnectionPool[T], id: string) =
  withLock pool.lock:
    if id in pool.connections:
      pool.connections.del(id)

proc getConnection*[T](pool: ConnectionPool[T], id: string): Option[T] =
  withLock pool.lock:
    if id in pool.connections:
      return some(pool.connections[id])
    return none(T)

iterator connections*[T](pool: ConnectionPool[T]): T =
  ## Iterator over all connections in the pool
  ## Note: This acquires a lock for the entire iteration
  withLock pool.lock:
    for connection in pool.connections.values:
      yield connection

proc connectionCount*[T](pool: ConnectionPool[T]): int =
  withLock pool.lock:
    return pool.connections.len