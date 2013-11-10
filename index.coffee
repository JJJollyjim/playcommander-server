logger = new (require "./logger")
ws = require("ws").Server

server = new ws {port: 8081}

usedPairCodes = []
playerRemotesMap = {}
orphanRemotes = []

genPairCode = ->
  code = 0

  until code.length > 5 and code not in usedPairCodes
    decRand = Math.random()
    code    = (decRand * (Math.pow(10, decRand.toString().length - 2))).toString(16)[0..5]

  usedPairCodes.push code
  return code

server.on "connection", (socket) ->
  logger.log "^ #{server.clients.length} online"

  socket.sendMessage = (type, payload = {}) ->
    message = {
      type: type
      payload: payload
    }

    this.send(JSON.stringify message)

  socket.on "close", ->
    # Log the disconnect and
    logger.log "v #{server.clients.length} online"

    try
      if socket.clientType?
        if socket.clientType is "player"
          # Disconnect all the remotes
          if socket of playerRemotesMap
            for remote in playerRemotesMap[socket]
              remote.sendMessage("noplayer", {on: "playerclose"})
              remote.close()

          # Remove player from prm
          delete playerRemotesMap[socket]

        else if socket.clientType is "remote"
          # Remove remote from prm
          playerRemotesMap.splice playerRemotesMap.indexOf
    catch
      logger.error "Error occoured"

  socket.on "message", (message) ->
    data = try JSON.parse message

    if data is undefined
      logger.error "Received invalid JSON from client: #{message}"
      return

    if data.type is undefined or data.payload is undefined
      logger.error "Received invalid type/payload from client: #{message}"
      return

    try
      handleMessage(socket, data.type, data.payload)
    catch error
      logger.error "An unknown error occoured while handling a message:"
      logger.error "> type: #{data.type}"
      logger.error "> payload: #{JSON.stringify data.payload}"

      socket.close()

handleMessage = (socket, type, payload) ->
  # Handle various possible errors
  # No type or payload in the message
  unless type? and payload?
    logger.error "Message has no type or payload"
    return socket.close()

  # Type or payload has the wrong type
  unless typeof type is "string" and typeof payload is "object"
    logger.error "Type isn't string or payload isn't object"
    return socket.close()

  # Payload contains no clientType
  unless payload.clientType? and (payload.clientType is "remote" or payload.clientType is "player")
    logger.error "Message has no/malformed clientType"
    return socket.close()

  # Save clientType to socket if it isn't already saved
  socket.clientType = payload.clientType unless socket.clientType?

  if payload.clientType is "player"
    if type is "auth"
      # Handle various possible explosions
      if socket of playerRemotesMap     then logger.error "Player's socket already in playerRemotesMap on auth"; return socket.close()
      if findPlayerByUUID(payload.uuid) then logger.error "Found a player in the prm with the same uuid as connecting player"; return socket.close()
      unless payload.uuid?              then logger.error "Player auth frame has no uuid"; return socket.close()

      # Save the UUID
      socket.uuid = payload.uuid

      # Put socket in the map
      playerRemotesMap[socket] = []

      # Acknoledge the authentication with a pairing code
      paircode = genPairCode()
      socket.sendMessage("ack", {paircode: paircode})

      # Log the successful authentication
      logger.log "Authed new player (id #{payload.uuid}) with pairing code #{paircode}"
  else if payload.clientType is "remote"
    if type is "command"
      # Send a command
      return

findPlayerByUUID = (uuid) ->
  return player for player of playerRemotesMap when player.uuid is uuid
  return false