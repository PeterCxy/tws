import { logger } from './util/log'
import { parseHost } from './util/util'
import LocalSession from './protocol/localSession'

export clientMain = (argv) ->
  parsedListen = parseHost argv.listen
  return if not parsedListen?
  parsedRemote = parseHost argv.remote
  return if not parsedRemote?
  [localHost, localPort] = parsedListen
  [remoteHost, remotePort] = parsedRemote
  new LocalSession(
    argv.concurrency, argv.heartbeat, localHost, localPort,
    argv.server, argv.password, remoteHost, remotePort
  )