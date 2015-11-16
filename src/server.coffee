require './init'

logger = require 'winston'
config = require './config'

express = require 'express'
bodyParser = require 'body-parser'
request = require 'request'
moment = require 'moment'
mediatorUtils = require 'openhim-mediator-utils'
util = require './util'


buildDHIS2Orchestration = (beforeTimestamp, path, querystring, response) ->
  name: 'DHIS2'
  request:
    path: path
    host: config.getConf().dhis2.host
    port: config.getConf().dhis2.port
    querystring: querystring
    headers:
      accept: 'application/xml'
    method: 'GET'
    timestamp: beforeTimestamp
  response:
    status: response.statusCode
    headers: response.headers
    body: response.body?[...10*1024] #cut off if too big
    timestamp: new Date()

buildInfoManOrchestration = (beforeTimestamp, path, querystring, response) ->
  name: 'OpenInfoMan'
  request:
    path: path
    host: config.getConf().openinfoman.host
    port: config.getConf().openinfoman.port
    querystring: querystring
    headers:
      accept: 'multipart/form-data'
    method: 'POST'
    timestamp: beforeTimestamp
    body: 'DXF content...'
  response:
    status: response.statusCode
    headers: response.headers
    body: response.body
    timestamp: new Date()


getBasePath = ->
  _bp = config.getConf().dhis2.basepath
  if _bp? and _bp.length > 0
    if _bp[0] isnt '/'
      _bp = "/#{_bp}"
    if _bp.slice(-1) is '/'
      _bp = _bp[0 ... -1]
    _bp
  else
    ''

queryDHIS2 = (req, res, lastSync, openhimTransactionID, orchestrations, callback) ->
  path = "#{getBasePath()}/api/metaData"
  query = "assumeTrue=false&organisationUnits=true&lastUpdated=#{lastSync}"
  url = "http://#{config.getConf().dhis2.host}:#{config.getConf().dhis2.port}#{path}?#{query}"

  logger.info "[#{openhimTransactionID}] Querying DHIS2 #{url}"

  options =
    url: url
    headers:
      accept: 'application/xml'
    auth:
      user: config.getConf().dhis2.username
      pass: config.getConf().dhis2.password

  before = new Date()
  request options, (err, httpResponse) ->
    if err
      util.handleInternalServerError res, err, orchestrations
      return callback true

    orchestrations.push buildDHIS2Orchestration before, path, query, httpResponse

    if httpResponse.statusCode isnt 200
      util.handleInternalServerError res, err, orchestrations
      return callback true

    callback null, httpResponse.body


_dynamicConf = {}

updateSyncTime = (req, res, openhimTransactionID, orchestrations, callback) ->
  logger.info "[#{openhimTransactionID}] Sending last sync date to core"

  headers = mediatorUtils.genAuthHeaders config.getConf().openhim.api

  _dynamicConf.lastSync = moment().format 'YYYY-MM-DD'
  config.getConf().lastSync = _dynamicConf.lastSync

  options =
    url: "#{config.getConf().openhim.api.apiURL}/mediators/#{config.getMediatorConf().urn}/config"
    headers: headers
    json: _dynamicConf

  request.put options, (err, res, body) ->
    if err
      util.handleInternalServerError res, err, orchestrations
      return callback true

    callback null


sendDXFToInfoMan = (req, res, openhimTransactionID, dxf, orchestrations, callback) ->
  path = "/CSD/csr/#{config.getConf().openinfoman.document}/careServicesRequest/urn:dhis2.org:csd:stored-function:dxf2csd/adapter/dhis2/upload"
  url = "http://#{config.getConf().openinfoman.host}:#{config.getConf().openinfoman.port}#{path}"

  logger.info "[#{openhimTransactionID}] Sending DXF update to OpenInfoMan #{url}"

  options =
    url: url
    formData:
      dxf:
        options:
          filename: 'dxf.xml'
          contentType: 'text/xml'
        value: dxf

  before = new Date()
  request.post options, (err, httpResponse, body) ->
    if err
      util.handleInternalServerError res, err, orchestrations
      return callback true

    orchestrations.push buildInfoManOrchestration before, path, null, httpResponse

    if httpResponse.statusCode isnt 200 and httpResponse.statusCode isnt 302 #infoman redirects on upload
      util.handleInternalServerError res, 'Failed to upload DXF to OpenInfoMan', orchestrations
      return callback true

    callback null


handler = (req, res) ->
  openhimTransactionID = req.headers['x-openhim-transactionid']

  logger.info "[#{openhimTransactionID}] Running sync ..."

  lastSync = config.getConf().lastSync
  orchestrations = []

  queryDHIS2 req, res, lastSync, openhimTransactionID, orchestrations, (err, dxf) ->
    return if err

    sendDXFToInfoMan req, res, openhimTransactionID, dxf, orchestrations, (err) ->
      return if err

      updateSyncTime req, res, openhimTransactionID, orchestrations, (err) ->
        return if err

        res.set 'Content-Type', 'application/json+openhim'
        res.send {
          'x-mediator-urn': config.getMediatorConf().urn
          status: 'Successful'
          orchestrations: orchestrations
          response:
            status: 200
            headers:
              'content-type': 'application/json'
            body: 'done'
            timestamp: new Date()
        }
  


# Setup express
app = express()

app.use bodyParser.json()

app.get '/trigger', handler


server = app.listen config.getConf().server.port, config.getConf().server.hostname, ->
  logger.info "[#{process.env.NODE_ENV}] #{config.getMediatorConf().name} running on port #{server.address().address}:#{server.address().port}"


if process.env.NODE_ENV isnt 'test'
  logger.info 'Attempting to register mediator with core ...'
  config.getConf().openhim.api.urn = config.getMediatorConf().urn

  mediatorUtils.registerMediator config.getConf().openhim.api, config.getMediatorConf(), (err) ->
    return logger.error err if err

    logger.info 'Mediator has been successfully registered'

    configEmitter = mediatorUtils.activateHeartbeat config.getConf().openhim.api

    configEmitter.on 'config', (newConfig) ->
      logger.info 'Received updated config from core'
      _dynamicConf = newConfig
      config.updateConf newConfig

    configEmitter.on 'error', (err) -> logger.error err

    mediatorUtils.fetchConfig config.getConf().openhim.api, (err, newConfig) ->
      return logger.error err if err
      logger.info 'Received initial config from core'
      _dynamicConf = newConfig
      config.updateConf newConfig
 

exports.app = app
