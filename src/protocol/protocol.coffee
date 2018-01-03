import * as crypto from 'crypto'
import { just, generateId, parseHost } from '../util/util'

# SHA256-based HMAC authentication
# Sign any arbitary data with a password
#
# Note that for now the server is never
# authenticated. This protocol is designed
# to rely on SSL certificates for server
# authentication.
authenticate = (passwd, data) ->
  new Promise (resolve) ->
    hmac = crypto.createHmac('sha256', passwd)
    hmac.on 'readable', ->
      data = hmac.read()
      resolve data.toString('base64') if data?
    hmac.write data
    hmac.end()

# Perform heartbeat to avoid connection being stalled
# Returns a Timer object. This timer should be cancelled
# when the websocket is closed or closed by this function
export heartbeat = (webSocket, onClose) ->
  isAlive = true
  webSocket.on 'pong', ->
    isAlive = true
  checker = ->
    if not isAlive
      webSocket.terminate()
      onClose()
      return
    isAlive = false
    webSocket.ping '', false, true
  setInterval checker, 10000 # TODO: allow changing this interval

###
  Client: first handshake packet
  Sent right after opening a WebSocket connection.
  Authenticates itself and sends the target host
  to forward to.

  > AUTH [authentication code]
  > NOW [current time]
  > TARGET [targetHost]:[targetPort]

  [authentication code] is generated by signing
  the two lines without `AUTH` by a pre-shared
  password.
  Any packet older than 10 seconds are regarded
  as illegal.
  TODO: make this configurable
###
export buildHandshakePacket = (passwd, targetHost, targetPort) ->
  connRequest = "NOW #{Date.now()}\nTARGET #{targetHost}:#{targetPort}"
  authCode = await authenticate passwd, connRequest
  return "AUTH #{authCode}\n#{connRequest}"

export parseHandshakePacket = (passwd, packet) ->
  lines = Buffer.from(packet).toString('utf-8').split '\n'
  return just null if lines.length != 3
  return null if lines[0] != "AUTH " + (await authenticate passwd, "#{lines[1]}\n#{lines[2]}")
  return null if not lines[1].startsWith 'NOW '
  # Disallow packets that are more than 10 seconds old
  # TODO: Make this a configurable option
  return null if Date.now() - parseInt(lines[1][4..]) > 10000
  return null if not lines[2].startsWith 'TARGET '
  # Pass the TARGET part to parseHost
  return parseHost lines[2][7..]

###
  Client: CONNECT packet
  Requests a new logical connection through
  the WebSocket tunnel.

  > AUTH [authentication code]
  > NEW CONNECTION [connection id]

  [authentication code] is again generated by
  signing the line without `AUTH` by the password.

  The [connection id] should be a random string
  with 6 characters. This should be unique for
  every connection, since it is used to identify
  logical connections from each other.
###
export buildConnectPacket = (passwd) ->
  connId = generateId()
  connRequest = "NEW CONNECTION " + connId
  authCode = await authenticate passwd, connRequest
  return [connId, "AUTH #{authCode}\n#{connRequest}"]

export parseConnectPacket = (passwd, packet) ->
  lines = Buffer.from(packet).toString('utf-8').split '\n'
  return just null if lines.length != 2
  return null if lines[0] != "AUTH " + (await authenticate passwd, lines[1])
  return null if not lines[1].startsWith 'NEW CONNECTION '
  connId = lines[1][15..]
  return null if not (connId? && connId.length is 6)
  return connId

###
  Client and Server: the Connect-Response packet.
  This was designed for the response to CONNECT
  requests to indicate whether a connection
  is successful. However, it is used by both
  the client and the server to indicate state
  changes of the logical connections.

  > CONNECTION [connection id] <OK|CLOSED>
###
export buildConnectResponsePacket = (connId, ok) ->
  "CONNECTION #{connId} #{if ok then 'OK' else 'CLOSED'}"

export parseConnectResponsePacket = (packet) ->
  words = Buffer.from(packet).toString('utf-8').split ' '
  return null if words.length != 3
  return null if words[0] != 'CONNECTION'
  return null if (words[2] != 'OK' && words[2] != 'CLOSED')
  return [words[1], (words[2] == 'OK')]

###
  Client and Server: Payload packet
  Forwards payload of the TCP connection
  over the WebSocket channel.

  > P[connection id][payload]

  where [payload] is the binary data
  of the TCP connection.
###
export buildPayloadPacket = (connId, payload) ->
  Buffer.concat([Buffer.from("P" + connId), payload])

CHAR_P = 'P'.charCodeAt(0)
export parsePayloadPacket = (packet) ->
  return null if packet.length < 8 # 'P' + connId(6) + 1
  return null if packet[0] != CHAR_P # Starts with 'P'
  return [packet[1..6], packet[7..]]