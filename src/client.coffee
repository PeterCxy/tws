import * as net from 'net'
import { logger } from './log'
import { randomInt } from './util'
import ClientSession from './protocol/clientSession'

CONNECTION_COUNT = 2

wsPool = null

process.nextTick -> clientMain()

clientMain = ->
  wsPool = [0..(CONNECTION_COUNT - 1)].map (index) ->
    new ClientSession index, 'ws://127.0.0.1:23356', 'testpasswd', '118.178.213.186', 80
  localServer 23357

randomSession = ->
  index = -1
  count = 0
  while index == -1 || (not wsPool[index].isReady()) # Pick a working socket
    return null if count > 10 # Possibly no working connection for now.
    index = randomInt wsPool.length
    count++
  return wsPool[index]

localServer = (localPort) ->
  server = net.createServer localConnection
  server.listen localPort, ->
    logger.info "Listening on #{localPort}"

localConnection = (client) ->
  # Immediatly pause the reading of data
  # Resume when we have finished all the dirty work here
  client.pause()

  # Try to create a connection with the server
  session = randomSession()
  if not session?
    client.end()
    return
  connId = null
  try
    connId = await session.createLogicalConnection()
  catch error
    # Nothing
  if not connId?
    client.end()
    return

  # Wait for server's request to close connection
  session.onLogicalConnectionClose connId, -> client.end()
  session.onLogicalConnectionReceive connId, (buf) -> client.write buf
  
  onClose = ->
    logger.info "Tearing down connection #{connId}"
    if session.isReady()
      # If this close event is not caused by the `onLogicalConnectionClose` event
      # sent when the whole session is torn down
      # then notify the session that the client connection is closed
      session.closeLogicalConnection connId
  client.once 'close', onClose
  client.once 'error', onClose
  client.on 'data', (buf) ->
    logger.info "Sending data of length #{buf.length} from #{connId}"
    session.sendLogicalConnectionPayload connId, buf

  # Now we can safely resume the socket
  # Without worrying about losing data
  client.resume()
