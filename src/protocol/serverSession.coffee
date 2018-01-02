import { logger } from '../util/log'
import * as protocol from './protocol'
import { randomInt } from '../util/util'
import RemoteSession from './remoteSession'

export default class ServerSession
  constructor: (@passwd, @conn) ->
    @proxyConns = {}
    @stage = 0
    @targetHost = null
    @targetPort = 0
    @closed = false
    @timer = null # heartbeat timer object

    # Listen on the needed events
    @conn.on 'close', @connClose
    @conn.on 'error', @connClose
    @conn.on 'message', @onReceive

  connClose: =>
    return if @closed
    @closed = true

    # Clean-up job
    if @timer?
      clearInterval @timer
      @timer = null
    @conn = null

    # Terminate all TCP connections
    for _, v of @proxyConns
      v.onConnectionClose()
    @proxyConns = null

  onReceive: (msg) =>
    if @stage is 0 # Handshake not completed
      @serverHandshake msg
    else if @stage is 1 # Server up, accepting logical connections
      @processRequest msg

  serverHandshake: (msg) =>
    target = await protocol.parseHandshakePacket @passwd, msg
    if not (target? and target.length is 2) # Close immediately for unknown packets
      logger.error "Unknown client is connecting to this server. Disconnecting."
      @conn.close 1002
      return
    [@targetHost, @targetPort] = target

    # Send anything back to client to activate this connection
    @conn.send('' + randomInt())
    logger.info "Client tunneling to #{@targetHost}:#{@targetPort}"
    @stage = 1

    # Enable heartbeat packets
    if not @timer?
      @timer = protocol.heartbeat @conn, @connClose

  processRequest: (msg) =>
    # Test if the request is a payload
    payload = protocol.parsePayloadPacket msg
    if payload?
      # Forward the payload packet to remote (target)
      @forwardPayload payload
      payload = null
      return

    # Test if the request is a connect-response packet
    # If a server receives such packet, it must be closing the connection
    # It shares the packet type `connect-response` though it is not
    connResp = protocol.parseConnectResponsePacket msg
    if connResp?
      @processConnectResponse connResp
      return

    # Test if the request is a CONNECT request
    # This kind of request opens a new logical connection within our session
    # which maps to a real connection from the server to the target
    # The client supplies the proposed connId
    # TODO: Check if there is any duplicated connId and close the connection if so
    #       while this does not seem to be ever possible. (probability: 1/(62^6))
    connId = await protocol.parseConnectPacket @passwd, msg
    if connId?
      # Create the connection
      @processLogicalConnection connId

  forwardPayload: (payload) =>
    [connId, buf] = payload
    logger.info "Packet sent from #{connId} with length #{buf.length}"
    @proxyConns[connId].sendPayload buf if @proxyConns[connId]?

  processConnectResponse: (connResp) =>
    [connId, _] = connResp
    if @proxyConns[connId]?
      @proxyConns[connId].onConnectionClose()

  processLogicalConnection: (connId) =>
    logger.info "Client requesting new connection #{connId}"
    @proxyConns[connId] = new RemoteSession this, connId, @targetHost, @targetPort

  # Logical connection events
  # Interact with RemoteSession
  onLogicalConnectionUp: (connId) =>
    @conn?.send protocol.buildConnectResponsePacket connId, true

  onLogicalConnectionDown: (connId) =>
    return if @closed or (not @proxyConns[connId]?)
    delete @proxyConns[connId]
    @conn?.send protocol.buildConnectResponsePacket connId, false

  sendLogicalConnectionPayload: (connId, buf) =>
    @conn?.send protocol.buildPayloadPacket connId, buf