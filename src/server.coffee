import * as net from 'net'
import WebSocket from 'ws'
import { logger } from './log'
import * as protocol from './protocol'

wss = null

serverMain = (port) ->
  wss = new WebSocket.Server { port: port }
  wss.on 'connection', clientConnection 'testpasswd'

clientConnection = (passwd) -> (conn) ->
  proxyConns = {}
  stage = 0
  targetHost = null
  targetPort = 0
  conn.on 'message', (msg) ->
    if stage == 0 # haven't handshaked yet
      target = await protocol.parseHandshakePacket passwd, msg
      if not (target? && target.length == 2) # Close immediately for unknown packets
        conn.close 1002
        return
      [targetHost, targetPort] = target
      logger.info "Client tunneling to #{targetHost}:#{targetPort}"
      stage = 1
    else if stage = 1 # handshaked
      # Test if it is a payload packet
      payload = protocol.parsePayloadPacket msg
      if payload?
        [connId, buf] = payload
        logger.info "Packet sent from #{connId} with length #{buf.length}"
        #console.log buf.toString('utf-8')
        proxyConns[connId].write buf if proxyConns[connId]?
        return
      # Test if it is a connect-response packet
      # In this case, it must be a packet requesting
      # to close a connection
      connResp = protocol.parseConnectResponsePacket msg
      if connResp?
        [connId, _] = connResp
        if proxyConns[connId]?
          proxyConns[connId].end()
        return

      # Test if it is a connect packet
      connId = await protocol.parseConnectPacket passwd, msg
      if connId?
        logger.info "Client requesting new connection #{connId}"
        
        # Create the connection
        socket = net.createConnection targetPort, targetHost
        cleanup = ->
          logger.info "Tearing down connection #{connId}"
          delete proxyConns[connId]
          conn.send protocol.buildConnectResponsePacket connId, false
        socket.once 'close', cleanup
        socket.once 'error', cleanup
        socket.once 'connect', ->
          proxyConns[connId] = socket
          conn.send protocol.buildConnectResponsePacket connId, true
        socket.on 'data', (buf) ->
          logger.info "Packet received from #{connId} with length #{buf.length}"
          conn.send protocol.buildPayloadPacket connId, buf
      #conn.send 'CONNECTION CREATED'

#remoteConnection = (connId, wsConn, targetHost, targetPort, onConnect, onError) ->
#  socket = net.createConnection targetPort, targetHost
#  socket.once 'error', -> onError()
#  socket.once 'connect', -> onConnect()
#  return socket

serverMain 23356