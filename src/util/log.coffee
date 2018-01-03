import * as winston from 'winston'

myFormat = winston.format.printf (info) ->
  "#{info.timestamp} [#{info.level}] #{info.message}"

export logger = null

export initialize = ->
  logger = winston.createLogger {
    format: winston.format.combine(
      winston.format.timestamp(),
      myFormat
    ),
    transports: [
      new winston.transports.Console()
    ],
    level: if process.env['NODE_ENV'] is 'debug' then 'debug' else 'info'
}