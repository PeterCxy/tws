import * as net from 'net'
import ClientSession from './clientSession'
import { randomInt } from '../util/util'
import { logger } from '../util/log'

export default class LocalSession
  constructor: (@concurrency, @localPort, @server, @passwd, @targetHost, @targetPort) ->
    # Create all the concurrent WebSocket sessions to the server
    @wsPool = [0..(@concurrency - 1)].map (index) =>
      new ClientSession index, @server, @passwd, @targetHost, @targetPort

    # Create the local server
    @socket = net.createServer @onNewClient
    @socket.listen @localPort

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
    @socket.end() if not @socket.destroyed

  # Invoked when client has requested to close the connection
  # Will send close request to server
  # Note that onRemoteClose will be invoked after finishing this request
  onClientClose: =>
    return if @closed
    @closed = true
    logger.info "Tearing down connection #{@connId}"
    if @session.isReady()
      # If the WebSocket session is still ready, send the close notification
      @session.closeLogicalConnection @connId

  # Forward packets between local and remote
  onRemoteReceive: (buf) =>
    @socket.write buf

  onClientReceive: (buf) =>
    logger.info "Sending data of length #{buf.length} from #{@connId}"
    @session.sendLogicalConnectionPayload @connId, buf