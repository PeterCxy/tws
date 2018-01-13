import WebSocket from 'ws'
import { logger } from './util/log'
import { parseHost } from './util/util'
import ServerSession from './protocol/serverSession'

_serverMain = (heartbeat, timeout, host, port, password) ->
  wss = new WebSocket.Server {
    host: host,
    port: port
  }, ->
    logger.info "Listening on ws://#{host}:#{port}/"
  wss.on 'connection', (conn) ->
    new ServerSession heartbeat, timeout, password, conn

export serverMain = (argv) ->
  parsedHost = parseHost argv.listen
  return if not parsedHost?
  [host, port] = parsedHost
  _serverMain argv.heartbeat, argv.timeout, host, port, argv.password
