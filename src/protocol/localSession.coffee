import * as net from 'net'
import ClientSession from './clientSession'
import { randomInt } from '../util/util'
import { logger } from '../util/log'

###
  A LocalSession operates a local TCP server.
  Any connection to this TCP server will be
  forwarded to the given WebSocket server
  and futher to a designated remote server.

  Multiple WebSocket connection will be created
  upon start. Every new connection accepted from
  the local server will be randomly assigned to
  one of these WebSocket channels.

  The WebSocket client-side channel implementation
  is separated into ClientSession.
###
export default class LocalSession
  constructor: (@concurrency, @heartbeatInterval, @localAddr,
                @localPort, @server, @passwd, @targetHost, @targetPort) ->
    # Create all the concurrent WebSocket sessions to the server
    @wsPool = [0..(@concurrency - 1)].map (index) =>
      new ClientSession index, @heartbeatInterval, @server, @passwd, @targetHost, @targetPort

    # Create the local server
    @socket = net.createServer @onNewClient
    @socket.listen {
      host: @localAddr,
      port: @localPort
    }, =>
      logger.info "Listening on #{@localAddr}:#{@localPort}"

  randomSession: =>
    index = -1
    count = 0
    while index == -1 || (not @wsPool[index].isReady()) # Pick a working socket
      return null if count > 10 # Possibly no working connection for now.
      index = randomInt @wsPool.length
      count++
    return @wsPool[index]

  onNewClient: (client) =>
    # Immediately pause the client to avoid losing `data` events
    # Resume when we are ready
    client.pause()
    # Randomly choose a session to create logical connection on
    session = @randomSession()
    # If no session is working for now, close the connection directly
    if not session?
      client.end()
      return
    # Pass control over a LocalConnection object
    new LocalConnection session, client

###
  A LocalConnection operates one connection
  accepted from the local TCP server.
  It simply forwards everything to a logical
  connection created on the assigned WebSocket
  channel.
###
class LocalConnection
  constructor: (@session, @socket) ->
    @initialize()

  initialize: =>
    @closed = false
    # Try to create a logical connection and obtain the ID
    @connId = null
    try
      @connId = await @session.createLogicalConnection()
    catch err
      # Just leave @connId as null
    # If no connection can be created, destroy the socket and return
    if not @connId?
      @socket.end()
      return

    # Set up event listeners
    @session.onLogicalConnectionClose @connId, @onRemoteClose
    @session.onLogicalConnectionReceive @connId, @onRemoteReceive
    
    @socket.on 'close', @onClientClose
    @socket.on 'error', @onClientClose
    @socket.on 'data', @onClientReceive

    # We can finally resume the data stream here
    @socket.resume()

  # Invoked when remote has closed the connection
  onRemoteClose: =>
    logger.info "[#{@connId}] closed by remote"
    @socket.end() if not @socket.destroyed

  # Invoked when client has requested to close the connection
  # Will send close request to server
  # Note that onRemoteClose will be invoked after finishing this request
  onClientClose: =>
    return if @closed
    @closed = true
    logger.info "[#{@connId}] closed by client"
    if @session.isReady()
      # If the WebSocket session is still ready, send the close notification
      @session.closeLogicalConnection @connId

  # Forward packets between local and remote
  onRemoteReceive: (buf) =>
    @socket.write buf

  onClientReceive: (buf) =>
    logger.debug "[#{@connId}] sending #{buf.length} bytes"
    @session.sendLogicalConnectionPayload @connId, buf