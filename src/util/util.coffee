import 'babel-polyfill'

export just = (val) ->
  new Promise (resolve) -> resolve val

DICTIONARY = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890'
export generateId = ->
  [1..6].map -> DICTIONARY[Math.floor(Math.random() * DICTIONARY.length)]
    .join('')

export randomInt = (max) ->
  Math.floor(Math.random() * max)