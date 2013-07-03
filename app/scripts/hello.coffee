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
        stackie.stackList.init()
        stackie.dropZone.init()
        $.event.trigger('app:cleanup')
        $body.removeClass().addClass('start');
      @get "/stack/:id", (req) ->
        console.log "show stack " + req.params["id"]
        stackie.image.init()
        stackie.chat.init()
        stackie.stackList.init()
        $.event.trigger('app:cleanup')
        $body.removeClass().addClass('stack');
        stackie.image.showImage(req.params["id"])
    )
    routes.configure (config) ->
      config.generateRequestOnPageLoad = true
    routes.start()


  init: init

@stackie.stackList = do ->
  $el = $('.stackList')
  $list = $el.find('.list')
  initialized = false

  init = ->
    unless initialized
      initialized = true
      registerEvents()
      populateList()

  registerEvents = ->
    $el.on 'click', '.deleteStack', deleteStack
    hoodie.store.on 'add:image', onStackAdded
    hoodie.store.on 'remove:image', onStackRemoved
    hoodie.store.on 'change:point', onPointChanged

  populateList = ->
    $.when(
      hoodie.store.findAll('point')
      hoodie.store.findAll('image')
    ).then (points, stacks) ->
      data =
        stacks: []
        baseUrl: hoodie.baseUrl
        amount: stacks.length
      stacks.reverse()
      for stack in stacks
        stack.pointAmount = _.where(points, {image: stack.id}).length
        data.stacks.push stack
      html = ich.stackList data
      $el.append(html)

  deleteStack = (event) ->
    event.preventDefault()
    id = $(event.target).closest('[data-id]').data('id')
    # Remove all points belonging to the stack
    hoodie.store.removeAll (point) ->
      if point.type is "point" and point.image is id
        # Remove messages belonging to each point
        hoodie.store.removeAll (message) ->
          if message.type is "message" and message.point is point.id
            return true
        return true
    hoodie.store.remove 'image', id

  onStackRemoved = (data) ->
    $el.find('[data-id="'+data.id+'"]').remove()

  onStackAdded = (data) ->
    data.baseUrl = hoodie.baseUrl
    html = ich.stackItem data
    $list.prepend(html)

  onPointChanged = (event, data) ->
    console.log("onPointChanged: ");
    $target = $el.find '[data-id="'+data.image+'"]'
    console.log("target: ",$target);
    $counter = $target.find '.pointAmount'
    console.log("counter: ",$counter);
    #debugger
    switch event
      when "add"
        $counter.text(parseInt($counter.text(), 10)+1)
      when "remove"
        $counter.text(parseInt($counter.text(), 10)-1)
      else
        null

  init: init

@stackie.dropZone = do ->
  $el = $('.dropZone')
  initialized = false

  init = ->
    unless initialized
      initialized = true
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
        # Cut away "data:image/jpeg;base64," from the data string, because
        # CouchDB knows how to serve the object from the mime type
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
  initialized = false

  init = ->
    unless initialized
      initialized = true
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
  initialized = false

  init = ->
    unless initialized
      initialized = true
      registerEvents()

  registerEvents = ->
    hoodie.store.on 'add:point', onNewPoint
    $imageContainer.hammer({release: true}).on "hold", onAddPoint
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
