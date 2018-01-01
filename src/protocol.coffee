import * as crypto from 'crypto'
import { just, generateId } from './util'

authenticate = (passwd, data) ->
  new Promise (resolve) ->
    hmac = crypto.createHmac('sha256', passwd)
    hmac.on 'readable', ->
      data = hmac.read()
      resolve data.toString('base64') if data?
    hmac.write data
    hmac.end()

export buildHandshakePacket = (passwd, targetHost, targetPort) ->
  connRequest = "TARGET #{targetHost}:#{targetPort}"
  authCode = await authenticate passwd, connRequest
  return "AUTH #{authCode}\n#{connRequest}"

export parseHandshakePacket = (passwd, packet) ->
  lines = new Buffer(packet).toString('utf-8').split '\n'
  return just null if lines.length != 2
  return null if lines[0] != "AUTH " + (await authenticate passwd, lines[1])
  return null if not lines[1].startsWith 'TARGET '
  return lines[1][7..].split(':')

export buildConnectPacket = (passwd) ->
  connId = generateId()
  connRequest = "NEW CONNECTION " + connId
  authCode = await authenticate passwd, connRequest
  return [connId, "AUTH #{authCode}\n#{connRequest}"]

export parseConnectPacket = (passwd, packet) ->
  lines = new Buffer(packet).toString('utf-8').split '\n'
  return just null if lines.length != 2
  return null if lines[0] != "AUTH " + (await authenticate passwd, lines[1])
  return null if not lines[1].startsWith 'NEW CONNECTION '
  connId = lines[1][15..]
  return null if not (connId? && connId.length > 0)
  return connId

export buildConnectResponsePacket = (connId, ok) ->
  "CONNECTION #{connId} #{if ok then 'OK' else 'CLOSED'}"

export parseConnectResponsePacket = (packet) ->
  words = new Buffer(packet).toString('utf-8').split ' '
  return null if words.length != 3
  return null if words[0] != 'CONNECTION'
  return null if (words[2] != 'OK' && words[2] != 'CLOSED')
  return [words[1], (words[2] == 'OK')]

export buildPayloadPacket = (connId, payload) ->
  Buffer.concat([new Buffer("P" + connId), payload])