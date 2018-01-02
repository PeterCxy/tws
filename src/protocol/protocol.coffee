import * as crypto from 'crypto'
import { just, generateId } from '../util/util'

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
  return lines[2][7..].split(':')

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
  return null if not (connId? && connId.length > 0)
  return connId

export buildConnectResponsePacket = (connId, ok) ->
  "CONNECTION #{connId} #{if ok then 'OK' else 'CLOSED'}"

export parseConnectResponsePacket = (packet) ->
  words = Buffer.from(packet).toString('utf-8').split ' '
  return null if words.length != 3
  return null if words[0] != 'CONNECTION'
  return null if (words[2] != 'OK' && words[2] != 'CLOSED')
  return [words[1], (words[2] == 'OK')]

export buildPayloadPacket = (connId, payload) ->
  Buffer.concat([Buffer.from("P" + connId), payload])

export parsePayloadPacket = (packet) ->
  return null if packet.length < 8 # 'P' + connId(6) + 1
  return null if packet[0] != 'P'.charCodeAt(0) # Starts with 'P'
  return [packet[1..6], packet[7..]]