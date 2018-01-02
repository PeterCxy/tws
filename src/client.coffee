import { logger } from './util/log'
import LocalSession from './protocol/localSession'

CONNECTION_COUNT = 2
process.nextTick -> clientMain()

clientMain = ->
  new LocalSession CONNECTION_COUNT, 23357, 'ws://127.0.0.1:23356', 'testpasswd', '127.0.0.1', 5201
  #wsPool = [0..(CONNECTION_COUNT - 1)].map (index) ->
  #  new ClientSession index, 'ws://127.0.0.1:23356', 'testpasswd', '118.178.213.186', 80
  #localServer 23357