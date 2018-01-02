import * as net from 'net'
import { logger } from '../util/log'

###
  RemoteSession is a dependency of ServerSession.
  A RemoteSession operates one connection from the server
  (which is requested by the client) to the remote. It then
  forwards payload back to its ServerSession and further
  to the client.
###
export default class RemoteSession
  constructor: (@serverSession, @connId, @targetHost, @targetPort) ->
    @closed = false
    # Create the TCP socket
    @socket = net.createConnection @targetPort, @targetHost
    # Subscribe to our events
    @socket.on 'close', @onConnectionClose
    @socket.on 'error', @onConnectionClose
    @socket.on 'connect', @onConnectionUp
    @socket.on 'data', @onDataReceived

  sendPayload: (buf) =>
    @socket.write buf

  onConnectionUp: =>
    @serverSession.onLogicalConnectionUp @connId
  
  onDataReceived: (buf) =>
    logger.info "Packet received from #{@connId} with length #{buf.length}"
    @serverSession?.sendLogicalConnectionPayload @connId, buf

  onConnectionClose: =>
    return if @closed
    @closed = true
    logger.info "Tearing down connection #{@connId}"
    if not @socket.destroyed
      @socket.end()
      @socket.destroy()
    @serverSession.onLogicalConnectionDown @connId
    @serverSession = null