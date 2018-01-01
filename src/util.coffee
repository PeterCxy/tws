import 'babel-polyfill'

export just = (val) ->
  new Promise (resolve) -> resolve val

export generateId = ->
  Math.random().toString(36).substring(7)

export randomInt = (max) ->
  Math.floor(Math.random() * max)