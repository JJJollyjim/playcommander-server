logger = new (require "./logger")
ws = require("ws").Server

# Dev deps

try require('source-map-support').install()

server = new ws {port: 8081}

usedPairCodes = []
playerRemoteMaps = {}
orphanRemotes = []

comparisonIDcounter = 0

uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

genPairCode = ->
  code = 0

  until code.length > 5 and code not in usedPairCodes
    decRand = Math.random()
    code    = (decRand * (Math.pow(10, decRand.toString().length - 2))).toString(16)[0..5]

  usedPairCodes.push code
  return code

server.on "connection", (socket) ->
  logger.log "^ #{server.clients.length} online"

  socket.toString = ->
    unless @comparisonID?
      @comparisonID = "WebSocket #" + (comparisonIDcounter++).toString()

    @comparisonID

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
          # We don't need to do any cleanup if the socket isn't in the prm
          if socket in playerRemoteMaps
            # Tell all the players that they don't have a remote no more
            for remote in playerRemoteMaps[socket].remotes
              remote.sendMessage("noplayer", {cause: "dc"})

            # Remove player from prm
            delete playerRemoteMaps[socket]

        else if socket.clientType is "remote"
          # Remove remote from prm
          remote = findPlayerByRemote socket
          if remote
            playerRemoteMaps[remote].remotes.splice playerRemoteMaps[remote].remotes.indexOf(socket), 1
          else
            loger.warn "Remote not in prm on disconnect"

    catch error
      logger.error "An unknown error occoured while handling a disconnection event"
      logger.error "stacktrace: #{error.stack}"

  socket.on "message", (message) ->
    data = try JSON.parse message

    if data is undefined
      logger.warn "Received invalid JSON from client: #{message}"
      return

    if data.type is undefined or data.payload is undefined
      logger.warn "Received invalid type/payload from client: #{message}"
      return

    try
      handleMessage(socket, data.type, data.payload)
    catch error
      logger.error "An unknown error occoured while handling a message:"
      logger.error "> type: #{data.type}"
      logger.error "> payload: #{JSON.stringify data.payload}"
      logger.error "> stacktrace: #{error.stack}"

      socket.close()

handleMessage = (socket, type, payload) ->
  # Handle various possible errors
  unless type? and payload?
    logger.warn "Received a message with no type or payload"
    return socket.close()
  unless typeof type is "string" and typeof payload is "object"
    logger.warn "Received a message with a weirdly typed 'type' or 'payload'"
    return socket.close()
  unless payload.clientType? and (payload.clientType is "remote" or payload.clientType is "player")
    logger.warn "Received a message has no/malformed clientType"
    return socket.close()

  # Save clientType to socket if it isn't already saved
  socket.clientType = payload.clientType unless socket.clientType?

  if payload.clientType is "player"
    if type is "auth"
      # Handle various possible explosions
      if socket of playerRemoteMaps
        logger.error "Player's socket already in playerRemoteMaps on auth"
        return socket.close()
      if findPlayerByUUID(payload.uuid)
        logger.error "Found a player in the prm with the same uuid as connecting player"
        return socket.close()
      unless payload.uuid?
        logger.warn "Player auth message has no uuid"
        return socket.close()
      unless uuidRegex.test(payload.uuid)
        logger.warn "Received non-compliant UUID (#{payload.uuid})"
        return socket.close()


      # Save the UUID
      socket.uuid = payload.uuid

      # Put socket in the map
      playerRemoteMaps[socket] =
        player: socket
        remotes: []

      # Acknoledge the authentication, sending a pairing code
      paircode = genPairCode()
      socket.sendMessage("ack", {paircode: paircode})

      # Log the successful authentication
      logger.log "Authed new player (id #{payload.uuid}) with pairing code #{paircode}"
  else if payload.clientType is "remote"
    if type is "getuuid"
      # The client has a pairing code, and wants to find the UUID of its client
      # for player of playerRemotesMap
      console.log()
    if type is "command"
      # Send a command
      return

findPlayerByUUID = (uuid) ->
  return map.player for id, map of playerRemoteMaps when map.player.uuid is uuid
  return false

findPlayerByRemote = (remote) ->
  for id, map of playerRemoteMaps
    if map.remotes.indexOf(remote) isnt -1
      return map.player

  return false