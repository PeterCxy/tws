import 'babel-polyfill'
import * as net from 'net'
import { logger } from './log'

export just = (val) ->
  new Promise (resolve) -> resolve val

DICTIONARY = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890'
export generateId = ->
  [1..6].map -> DICTIONARY[Math.floor(Math.random() * DICTIONARY.length)]
    .join('')

export randomInt = (max) ->
  Math.floor(Math.random() * max)

printInvalidHost = (str) ->
  logger.warn "Invalid host: #{str}"
  return null

# Parse a host:port string
# return null if invalid
export parseHost = (str) ->
  # If empty, then it can't be valid anyway.
  return printInvalidHost str if str is null or str.length is 0

  # Split with colons.
  parts = str.split ':'
  return printInvalidHost str if parts.length < 2

  # Since we have support for IPv6, there might
  # be more than one ':' in the string.
  ip = parts[0...(parts.length - 1)].join ':'
  # Neither IPv4 nor IPv6
  return printInvalidHost str if net.isIP(ip) is 0

  # Parse the port as a number
  port = parseInt parts[parts.length - 1]
  # If the number is invalid or the port is out of range
  return printInvalidHost str if isNaN(port) or (port is 0) or (port > 65535)

  # Finally return the parsed result
  return [ip, port]