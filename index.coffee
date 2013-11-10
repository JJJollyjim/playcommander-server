logger = new (require "./logger")
ws = require("ws").Server

# Dev deps

try require('source-map-support').install()

server = new ws {port: 8081}

usedPairCodes = []
playerRemoteMaps = {}
orphanRemotes = []

comparisonIDcounter = 0

regexes =
  uuid: /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
  paircode: /^[0-9a-f]{6}$/i


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
          if socket of playerRemoteMaps
            for remote in playerRemoteMaps[socket].remotes
              # Inform the remotes about the death of their parent
              remote.sendMessage("playerdied")

              # Throw 'em in an orphanage
              orphanRemotes.push remote

            # Remove player from prm
            delete playerRemoteMaps[socket]
          else
            logger.error "Player not in prm on diconnect"

        else if socket.clientType is "remote"
          # Remove remote from prm
          player = findPlayerByRemote socket
          if player
            playerRemoteMaps[player].remotes.splice playerRemoteMaps[player].remotes.indexOf(socket), 1

            # Inform the player about the loss of it's child
            player.sendMessage "remotenum", num: playerRemoteMaps[player].remotes.length
          else
            # Remote isn't in the prm
            # Is it in the orphanage?
            if socket in orphanRemotes
              # Expell it from the orphanage!
              orphanRemotes.splice orphanRemotes.indexOf(socket), 1
            else
              logger.error "Remote not in the prm or orphanage on disconnect"

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
      unless regexes.uuid.test(payload.uuid)
        logger.warn "Received non-compliant UUID (#{payload.uuid})"
        return socket.close()

      # Save the UUID
      socket.uuid = payload.uuid

      # Put socket in the map
      playerRemoteMaps[socket] =
        player: socket
        remotes: []

      # Acknoledge the authentication, sending a pairing code
      socket.paircode = genPairCode()
      socket.sendMessage("ack", {paircode: socket.paircode})

      # Find any orphaned remotes to be adopted by this player
      for orphan in orphanRemotes
        if orphan.playerUUID is payload.uuid
          # Get out of that smelly old orphanage
          orphanRemotes.splice orphanRemotes.indexOf(orphan), 1

          # Into your brand new home
          playerRemoteMaps[socket].remotes.push orphan

          # Whadda ya think, kiddo?
          orphan.sendMessage "connect"

          # We'd better tell the parent at some point, too
          socket.sendMessage "remotenum", num: playerRemoteMaps[socket].remotes.length

      # Log the successful authentication
      logger.log "Authed new player (id #{payload.uuid}) with pairing code #{socket.paircode}"

  else if payload.clientType is "remote"
    if type is "pair"
      # The client has a pairing code, and wants to find the UUID of its client

      # Handle possible errors
      unless payload.paircode?
        logger.warn "Remote sent no paircode in pairing"
        return socket.close()
      unless regexes.paircode.test(payload.paircode)
        logger.warn "Remote sent an invalid paircode in pairing (#{payload.paircode})"
        return socket.close()

      payload.paircode = payload.paircode.toLowerCase()

      foundplayer = false
      for id, map of playerRemoteMaps
        if map.player.paircode is payload.paircode
          foundplayer = map.player

      if foundplayer
        socket.sendMessage "pair", uuid: foundplayer.uuid
      else
        socket.sendMessage "npair"

    else if type is "connect"
      # The client knows the UUID they want to connect to (probbably from a previous pair)

      # Handle possible errors
      unless payload.uuid?
        logger.warn "Remote sent no UUID for connection"
        return socket.close()

      socket.playerUUID = payload.uuid

      player = findPlayerByUUID payload.uuid
      unless player
        # The player that the remote is looking for isn't connected
        socket.sendMessage "nconnect"

        orphanRemotes.push socket
      else
        # Tell the remote that it's connected
        socket.sendMessage "connect"

        # Add it to the prm
        playerRemoteMaps[player].remotes.push socket

        # Tell the player that it has a new remote
        player.sendMessage "remotenum", num: playerRemoteMaps[player].remotes.length

    else if type is "command"
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