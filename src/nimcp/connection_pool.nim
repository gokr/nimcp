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

proc getAllConnections*[T](pool: ConnectionPool[T]): seq[T] =
  ## Legacy method that returns all connections as a sequence
  ## Consider using the connections() iterator for better performance
  withLock pool.lock:
    for connection in pool.connections.values:
      result.add(connection)

proc connectionCount*[T](pool: ConnectionPool[T]): int =
  withLock pool.lock:
    return pool.connections.len