import WebSocket from 'ws'
import { logger } from '../util/log'
import * as protocol from './protocol'

export default class ClientSession
  constructor: (@index, @server, @passwd, @targetHost, @targetPort) ->
    @connect()

  isReady: => @ready
  connect: =>
    @ready = false
    # The `resolve` function of the promises of creating new connections.
    @connectCallbacks = {}
    # The callbacks for closing logical connections
    @closeCallbacks = {}
    # Callbacks for incoming data
    @dataCallbacks = {}
    # Flag for this session being closed
    @closed = false
    # Create the websocket object
    @socket = new WebSocket @server

    # Listen on the needed events
    @socket.on 'close', @onWsClose
    @socket.on 'error', @onWsClose
    @socket.on 'open', =>
      # Send handshake packet
      @socket.send await protocol.buildHandshakePacket @passwd, @targetHost, @targetPort
    @socket.on 'message', @onReceive

  onWsClose: =>
    return if @closed
    @closed = true
    @ready = false
    logger.error "Connection #{@index} closed by server. Retrying..."

    # clean up and re-connect on close
    @connectCallbacks = null
    for _, v of @closeCallbacks
      # Destroy all the connections
      v()
    @closeCallbacks = null
    @dataCallbacks = null
    @socket = null

    # Retry connection
    setTimeout(() =>
      @connect()
    , 1000)
    # TODO: allow customizing this timeout

  onReceive: (msg) =>
    # If we receive anything from the server
    # It is guaranteed that this session is now ready (handshake succeeded)
    # TODO: Maybe we need a Handshake response packet
    #       in case the client is connected to a non-tws server
    @ready = true

    # Test if this is a payload packet
    # If so, forward it to the local TCP socket
    payload = protocol.parsePayloadPacket msg
    if payload?
      @forwardPayload payload
      return

    # Test if this is a connect-response packet
    # Which signals the state of a logical connection
    connResp = protocol.parseConnectResponsePacket msg
    if connResp?
      @processConnectResponse connResp
      return

  forwardPayload: (payload) =>
    [connId, buf] = payload
    logger.info "Received packet from #{connId} with length #{buf.length}"
    @dataCallbacks[connId] buf if @dataCallbacks[connId]?

  processConnectResponse: (connResp) =>
    [connId, ok] = connResp
    if ok
      # This logical connection is now ready
      logger.info "Connection #{connId} successfully created"
      if @connectCallbacks[connId]?
        @connectCallbacks[connId](true)
    else
      # This logical connection is now closed (or not connected at all)
      if @connectCallbacks[connId]?
        @connectCallbacks[connId](false)
      if @closeCallbacks[connId]?
        @closeCallbacks[connId]()
      # No further payload packets can be possible.
      delete @dataCallbacks[connId] if @dataCallbacks[connId]?

  # Methods for the local TCP socket to call
  # Things about managing logical connections
  # Create a new logical connection
  # Returns a promise that will resolve when the logical connection is ready
  createLogicalConnection: =>
    [connId, packet] = await protocol.buildConnectPacket @passwd
    logger.info "Creating connection #{connId}"
    await new Promise (resolve) => # Wait until the server opens the connection
      @connectCallbacks[connId] = (res) =>
        delete @connectCallbacks[connId]
        if res
          resolve connId
        else
          resolve null
      @socket.send packet

  # Propose to close the logical connection with connId
  # Will return immediately.
  # When the connection is actually down, the onLogicalConnectionClose callback will be called
  closeLogicalConnection: (connId) =>
    @socket.send protocol.buildConnectResponsePacket connId, false

  # Send a payload packet to a logical connection
  sendLogicalConnectionPayload: (connId, buf) =>
    @socket.send protocol.buildPayloadPacket connId, buf

  # Register a callback for the close event of a logical connection
  onLogicalConnectionClose: (connId, callback) =>
    @closeCallbacks[connId] = =>
      delete @closeCallbacks[connId]
      callback()

  # Register a callback for the `data` event (receiving data) of the logical connection
  # i.e. this callback will be called once a payload packet needs to be forwarded
  onLogicalConnectionReceive: (connId, callback) =>
    @dataCallbacks[connId] = callback
