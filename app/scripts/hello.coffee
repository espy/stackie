# Namespace
@stackie = @stackie ? {}

@stackie.app = do (Hoodie, Davis) ->
  init = ->
    window.hoodie = new Hoodie('http://localhost:6007/_api');
    registerEvents()
    setupRoutes()

  registerEvents = ->
    hoodie.account.on 'authenticated', onUserAuthenticated

  onUserAuthenticated = (username) ->
    console.log("onUserAuthenticated: ",username);

  setupRoutes = ->
    $body = $('body');
    routes = Davis(->
      @get "/", (req) ->
        console.log "start page"
        stackie.dropZone.init()
        $.event.trigger('app:cleanup')
        $body.removeClass().addClass('start');
      @get "/stack/:id", (req) ->
        console.log "show stack " + req.params["id"]
        stackie.image.init()
        stackie.chat.init()
        $.event.trigger('app:cleanup')
        $body.removeClass().addClass('stack');
        stackie.image.showImage(req.params["id"])
    )
    routes.configure (config) ->
      config.generateRequestOnPageLoad = true
    routes.start()


  init: init

@stackie.dropZone = do ->
  $el = $('.dropZone')

  init = ->
    registerEvents()

  registerEvents = ->
    $el.on 'dragover', onDragOverDropZone
    $el.on 'drop', onFileDrop

  onDragOverDropZone = (event) ->
    event.stopPropagation()
    event.preventDefault()
    $('.dropZone').text("Come on then…")

  onFileDrop = (event) ->
    event.stopPropagation()
    event.preventDefault()
    files = event.originalEvent.dataTransfer.files # FileList object.
    totalFiles = files.length

    url = window.URL.createObjectURL(files[0])
    fileUpload = files[0]
    fileReader = new FileReader()

    img = new Image()

    img.onload = (event) =>
      imageWidth = event.currentTarget.width
      imageHeight = event.currentTarget.height

      fileReader.onload = (event) =>

        {name, size} = fileUpload
        mimeType = fileUpload.type
        properties = {name, size, mimeType}
        properties.width = imageWidth
        properties.height = imageHeight
        properties._attachments = {}
        properties._attachments[name] =
          content_type: mimeType,
          data: event.target.result.substr(13 + mimeType.length)

        localStorage.setItem 'currentImage', event.target.result

        hoodie.store.add('image', properties).done (image) ->
          window.location = window.location.href + "stack/"+ image.id

      fileReader.readAsDataURL(fileUpload);

    img.onerror = (event) =>
      console.log("error loading image");

    img.src = url;

    # files is a FileList of File objects. List some properties.
    ###
    i = 0
    file = undefined

    while file = files[i]
      reader = new FileReader()
      reader.onload = (event) ->
        contents = event.target.result
        output += contents
        filesParsed++
        doConversions()  if filesParsed is totalFiles

      reader.readAsText file
      i++
    ###

  init: init

@stackie.chat = do ->
  $el = $('.chatContainer')
  $document = $(document)

  init = ->
    registerEvents()

  registerEvents = ->
    $('.chatContainer').on 'click', '.sendMessage', onSendMessage
    hoodie.store.on 'add:message', onNewMessage
    $document.on('app:cleanup', cleanup)

  onSendMessage = (event) ->
    event.preventDefault()
    event.stopPropagation()
    $textarea = $(event.target).siblings('textarea')
    message = {
      text: $textarea.val()
      point: $(event.target).siblings('ul').data('id')
    }
    $textarea.val ""
    hoodie.store.add('message', message)

  onNewMessage = (data) ->
    # If this message's parent chat is open, append the message to it
    $chat = $('.chat ul')
    if data.point is $chat.data('id')
      html = ich.message(data)
      $chat.append(html)

  cleanup = ->
    $('.chatContainer .chat').empty()

  init: init

@stackie.image = do ->
  $imageContainer = $('.imageContainer')
  $pointLayer = $('.pointLayer')
  $document = $(document)

  init = ->
    registerEvents()

  registerEvents = ->
    hoodie.store.on 'add:point', onNewPoint
    $imageContainer.hammer().on "hold", onAddPoint
    $pointLayer.on "click", ".point", onPointClick
    $document.on('app:cleanup', cleanup)

  onNewPoint = (point) ->
    addPointToImage point

  onAddPoint = (event) ->
    pointData = {
      x: event.gesture.srcEvent.offsetX
      y: event.gesture.srcEvent.offsetY
      image: $('.imageContainer').data('id')
    }
    hoodie.store.add('point', pointData).done (point) ->
      $('.point[data-id="'+point.id+'"]').trigger('click')

  onPointClick = (event) ->
    $point = $(event.target).closest('.point')
    id = $point.data('id')
    $('.point.active').removeClass('active')
    $point.addClass('active')
    hoodie.store.findAll('message').done (allMessages) ->
      messages = _.where allMessages, {point: id}
      pointMessages =
        id: id
        messages: messages
      showPointMessages(pointMessages)
      $('#messageBody').show().focus()

  showImage = (id) ->
    localImage = localStorage.getItem("currentImage");
    if localImage
      img = '<img src="'+localImage+'" />';
      $imageContainer.append(img).data('id',id)
      localStorage.removeItem("currentImage");
      return

    # Get the image itself
    hoodie.store.find("image", id).done (image) ->
      imgSrc = hoodie.baseUrl + "/user%2F" + image.createdBy + "/image%2F" + image.id + "/" + image.name
      img = new Image();
      img.src = imgSrc
      $('.imageContainer').append(img).data('id',image.id)
      # Get all the image's points
      hoodie.store.findAll('point').done (points) ->
        pointsForThisImage = _.where points, {image: image.id}
        addPointsToImage pointsForThisImage

  showPointMessages = (messages) ->
    html = ich.messages(messages)
    $('.chat').empty().append(html)

  addPointsToImage = (points) ->
    _.each points, (point)->
      addPointToImage point

  addPointToImage = (point) ->
    pointHTML = ich.point(point)
    $('.pointLayer').append pointHTML

  cleanup = ->
    $('.imageContainer img').remove()
    $('.imageContainer .pointLayer').empty()

  init: init
  showImage: showImage

$(document).ready ->
  stackie.app.init()
  null
