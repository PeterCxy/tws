import WebSocket from 'ws'
import { logger } from './util/log'
import ServerSession from './protocol/serverSession'

wss = null

serverMain = (host, port) ->
  # TODO: support customized listen address (default to 127.0.0.1)
  wss = new WebSocket.Server {
    host: host,
    port: port
  }
  wss.on 'connection', (conn) ->
    new ServerSession 'testpasswd', conn

serverMain '127.0.0.1', 23356
