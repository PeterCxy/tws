import * as log from './util/log'
import { serverMain } from './server'
import { clientMain } from './client'

process.nextTick -> main()

main = ->
  { argv } = require 'yargs'
    .usage '$0 <server|client> [options]'
    .demandCommand()
    .command {
      command: 'server [options]',
      desc: 'Run in server mode',
      builder: serverArgs,
      handler: execute 'server'
    }
    .command {
      command: 'client [options]',
      desc: 'Run in client mode',
      builder: clientArgs,
      handler: execute 'client'
    }
    .config()
    .boolean 'v'
    .alias 'v', 'verbose'
    .default 'v', false
    .describe 'v', 'Enable debug output (alternatively, set env NODE_ENV=debug)'
    .help 'h'
    .alias 'h', 'help'
    .describe 'h', 'Print help information'

serverArgs = (yargs) ->
  yargs
    .alias 'l', 'listen'
    .describe 'l', 'Local address:port for WebSocket to bind to'
    .alias 'k', 'password'
    .describe 'k', 'Password for client authentication'
    .demandOption ['l', 'k']

clientArgs = (yargs) ->
  yargs
    .alias 'l', 'listen'
    .describe 'l', 'Local address:port to bind to'
    .alias 's', 'server'
    .describe 's', 'WebSocket server address (ws:// or wss://)'
    .alias 'r', 'remote'
    .describe 'r', 'The remote server to finally forward to'
    .alias 'k', 'password'
    .describe 'k', 'Password for authenticating to the server'
    .alias 'c', 'concurrency'
    .number 'c'
    .default 'c', 2
    .describe 'c', 'The number of WebSocket connections to maintain.'
    .demandOption ['l', 's', 'r', 'k']

execute = (command) -> (argv) ->
  # Process globally-applied options
  if argv.verbose
    process.env['NODE_ENV'] = 'debug'
  log.initialize()
  if command is 'server'
    serverMain argv
  else if command is 'client'
    clientMain argv