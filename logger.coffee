colors = require "colors"

Number.prototype.zerofill = ->
  if this.toString().length is 2 then this
  else "0" + this

timestamp = ->
  d = new Date

             # Date - yyyy/mm/dd
  return "#{ d.getFullYear()           }/" +
         "#{ d.getMonth().zerofill()   }/" +
         "#{ d.getDate().zerofill()    } " +

             # Time - hh:mm:ss
         "#{ d.getHours().zerofill()   }:" +
         "#{ d.getMinutes().zerofill() }:" +
         "#{ d.getSeconds().zerofill() }"

bracketise = (text) -> "[#{text}]"

class logger
  log: (msg) ->
    console.log bracketise(timestamp()).grey + "   " +
                bracketise("LOG").white      + " " +
                msg

  warn: (msg) ->
    console.log bracketise(timestamp()).grey + "  " +
                bracketise("WARN").yellow    + " " +
                msg

  error: (msg) ->
    console.log bracketise(timestamp()).grey + " " +
                bracketise("ERROR").red      + " " +
                msg.bold

  debug: (msg) ->
    console.log bracketise(timestamp()).grey + " " +
                bracketise("DEBUG").magenta  + " " +
                msg.bold

module.exports = logger