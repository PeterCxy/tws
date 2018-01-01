import * as net from 'net'
import WebSocket from 'ws'
import { logger } from './log'
import * as protocol from './protocol'
import { randomInt } from './util'

wsPool = new Array(32)
wsCallbacks = new Array(32)
wsFunctions = new Array(32)

clientMain = ->
  [0..31].forEach (index) ->
    serverConnection index, 'ws://127.0.0.1:23356', 'testpasswd', '220.181.57.217', 80
  localServer 23357

randomSocket = ->
  index = -1
  while index == -1 || wsFunctions[index] == null # Pick a working socket
    index = randomInt wsPool.length
  return index

serverConnection = (index, server, passwd, targetHost, targetPort) ->
  connectCallbacks = {} # The `resolve` function of the promises of creating new connections.
  closeCallbacks = {} # The callbacks for closing connections
  dataCallbacks = {} # Callbacks for incoming data
  connect = -> # Create a new logical connection
    [connId, packet] = await protocol.buildConnectPacket passwd
    logger.info "Creating connection #{connId}"
    await new Promise (resolve) -> # Wait until the server opens the connection
      connectCallbacks[connId] = (res) ->
        delete connectCallbacks[connId]
        if res
          resolve connId
        else
          resolve null
      wsPool[index].send packet
  close = (connId) -> # Close a logical connection
    wsPool[index].send protocol.buildConnectResponsePacket connId, false
  onClose = (connId, callback) -> # Call `callback` when the logical connection is down
    closeCallbacks[connId] = ->
      delete closeCallbacks[connId]
      callback()
  send = (connId, buf) ->
    wsPool[index].send protocol.buildPayloadPacket connId, buf
  onData = (connId, callback) -> # Call `callback` upon receiving data for the logical connection
    dataCallbacks[connId] = callback

  wsPool[index] = new WebSocket server
  wsPool[index].on 'open', ->
    # handshake
    wsPool[index].send await protocol.buildHandshakePacket passwd, targetHost, targetPort

    # Expose the functions for calling from local TCP server
    wsFunctions[index] = {
      connect: connect,
      close: close,
      onClose: onClose,
      onData: onData,
      send: send
    }
  wsPool[index].on 'message', (msg) ->
    # Test if this is a payload message
    payload = protocol.parsePayloadPacket msg
    if payload?
      [connId, buf] = payload
      logger.info "Received packet from #{connId} with length #{buf.length}"
      dataCallbacks[connId] buf if dataCallbacks[connId]?

    # Test if this is a connect-response message signaling state of connection
    connectResp = protocol.parseConnectResponsePacket msg
    if connectResp?
      [connId, ok] = connectResp
      if ok
        logger.info "Connection #{connId} successfully created"
        if connectCallbacks[connId]?
          connectCallbacks[connId](true)
      else
        if connectCallbacks[connId]?
          connectCallbacks[connId](false)
        if closeCallbacks[connId]?
          closeCallbacks[connId]()

localServer = (localPort) ->
  server = net.createServer localConnection
  server.listen localPort, ->
    logger.info "Listening on #{localPort}"

localConnection = (client) ->
  # Try to create a connection with the server
  socketId = randomSocket()
  connId = await wsFunctions[socketId].connect()
  if not connId?
    client.end()

  # Wait for server's request to close connection
  wsFunctions[socketId].onClose connId, -> client.end()
  wsFunctions[socketId].onData connId, (buf) -> client.write buf
  
  onClose = ->
    logger.info "Tearing down connection #{connId}"
    wsFunctions[socketId].close connId if wsFunctions[socketId]?
  client.once 'close', onClose
  client.once 'error', onClose
  client.on 'data', (buf) ->
    logger.info "Sending data of length #{buf.length} from #{connId}"
    wsFunctions[socketId].send connId, buf

clientMain()
