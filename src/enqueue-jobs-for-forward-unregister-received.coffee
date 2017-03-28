async = require 'async'
http  = require 'http'
_     = require 'lodash'

class EnqueueJobsForForwardUnregisterReceived
  constructor: (options) ->
    {@datastore, @jobManager, @uuidAliasResolver} = options

  do: (request, callback) =>
    @_enqueueForReceived {
      uuid: request.metadata.auth.uuid
      route: request.metadata.route
      forwardedRoutes: request.metadata.forwardedRoutes
      rawData: request.rawData
    }, (error) =>
      return @_doErrorCallback request, error, callback if error?
      @_doCallback request, 204, callback

  _doCallback: (request, code, callback) =>
    response =
      metadata:
        responseId: request.metadata.responseId
        code: code
        status: http.STATUS_CODES[code]
    callback null, response

  _doErrorCallback: (request, error, callback) =>
    code = error.code ? 500
    @_doCallback request, code, callback

  _enqueueForReceived: ({forwardedRoutes, rawData, route, uuid}, callback) =>
    lastHop = _.last route
    return callback new Error('Missing last hop') unless lastHop?
    {from, to} = lastHop

    @_resolveUuids {from, to, uuid}, (error, {from, to, uuid}) =>
      return callback error if error?
      return callback() unless from == to

      projection =
        uuid: true
        'meshblu.forwarders': true

      @datastore.findOne {uuid}, projection, (error, device) =>
        return callback error if error?

        forwarders = _.get device.meshblu?.forwarders, 'unregister.received'
        meshbluForwarders = _.filter forwarders, type: 'meshblu'
        @_createRequests meshbluForwarders, {forwardedRoutes, rawData, route, uuid}, callback

  _createRequest: ({forwardedRoutes, rawData, route, uuid}, forwarder, callback) =>
    return callback() if @_isCircular {forwardedRoutes, route}

    forwardedRoutes = _.clone forwardedRoutes ? []
    forwardedRoutes.push route

    request =
      metadata:
        auth: {uuid}
        fromUuid: uuid
        toUuid: uuid
        jobType: 'DeliverUnregisterSent'
        forwardedRoutes: forwardedRoutes
      rawData: rawData

    @jobManager.createRequest 'request', request, callback

  _createRequests: (forwarders, {forwardedRoutes, rawData, route, uuid}, callback)=>
    createRequest = async.apply @_createRequest, {forwardedRoutes, rawData, route, uuid}
    async.each forwarders, createRequest, callback

  _isCircular: ({forwardedRoutes, route}) =>
    return _.some forwardedRoutes, (forwardedRoute) =>
      _.isEqual route, forwardedRoute

  _resolveUuids: ({from, to, uuid}, callback) =>
    async.parallel {
      from: async.apply @uuidAliasResolver.resolve, from
      to:   async.apply @uuidAliasResolver.resolve, to
      uuid: async.apply @uuidAliasResolver.resolve, uuid
    }, callback

module.exports = EnqueueJobsForForwardUnregisterReceived
