import WebSocket from 'ws'
import { logger } from './util/log'
import ServerSession from './protocol/serverSession'

wss = null

serverMain = (port) ->
  # TODO: support customized listen address (default to 127.0.0.1)
  wss = new WebSocket.Server { port: port }
  wss.on 'connection', (conn) ->
    new ServerSession 'testpasswd', conn

serverMain 23356
