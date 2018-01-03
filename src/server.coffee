import WebSocket from 'ws'
import { logger } from './util/log'
import { parseHost } from './util/util'
import ServerSession from './protocol/serverSession'

_serverMain = (host, port, password) ->
  wss = new WebSocket.Server {
    host: host,
    port: port
  }, ->
    logger.info "Listening on ws://#{host}:#{port}/"
  wss.on 'connection', (conn) ->
    new ServerSession password, conn

export serverMain = (argv) ->
  parsedHost = parseHost argv.listen
  return if not parsedHost?
  [host, port] = parsedHost
  _serverMain host, port, argv.password
