require './init'

logger = require 'winston'
config = require './config'

express = require 'express'
bodyParser = require 'body-parser'
mediatorUtils = require 'openhim-mediator-utils'
util = require './util'
fs = require 'fs'
spawn = require('child_process').spawn
request = require 'request'


tmpCfg = '/tmp/openhim-mediator-openinfoman-dhis2-sync.cfg'

falseIfEmpty = (s) -> if s? and s.trim().length>0 then s else false

cfg = -> """
########################################################################
# Configuration Options for publish_to_ilr.sh
########################################################################

ILR_URL='#{config.getConf()['dhis-to-ilr']['ilr-url']}'
ILR_USER=#{falseIfEmpty config.getConf()['dhis-to-ilr']['ilr-user']}
ILR_PASS=#{falseIfEmpty config.getConf()['dhis-to-ilr']['ilr-pass']}
ILR_DOC='#{config.getConf()['dhis-to-ilr']['ilr-doc']}'
DHIS2_URL='#{config.getConf()['dhis-to-ilr']['dhis2-url']}'
DHIS2_EXT_URL=$DHIS2_URL
DHIS2_USER="#{falseIfEmpty config.getConf()['dhis-to-ilr']['dhis2-user']}"
DHIS2_PASS="#{falseIfEmpty config.getConf()['dhis-to-ilr']['dhis2-pass']}"
DOUSERS=#{config.getConf()['dhis-to-ilr']['dousers']}
DOSERVICES=#{config.getConf()['dhis-to-ilr']['dousers']}
IGNORECERTS=#{config.getConf()['dhis-to-ilr']['ignorecerts']}
LEVELS=#{config.getConf()['dhis-to-ilr']['levels']}
GROUPCODES=#{config.getConf()['dhis-to-ilr']['groupcodes']}
"""

saveConfigToFile = ->
  cfgStr = cfg()
  logger.debug "Config to save:\n#{cfgStr}"
  fs.writeFile tmpCfg, cfgStr, (err) ->
    if err
      logger.error err
      process.exit 1
    else
      logger.debug "Saved config to #{tmpCfg}"


buildArgs = ->
  args = []
  args.push "#{appRoot}/resources/publish_to_ilr.sh"
  args.push "-c #{tmpCfg}"
  args.push '-r' if config.getConf()['dhis-to-ilr']['reset']
  args.push '-f' if config.getConf()['dhis-to-ilr']['publishfull']
  args.push '-d' if config.getConf()['dhis-to-ilr']['debug']
  args.push '-e' if config.getConf()['dhis-to-ilr']['empty']
  return args

nullIfEmpty = (s) -> if s? and s.trim().length>0 then s else null

dhisToIlr = (out, callback) ->
  out.info "Running dhis-to-ilr ..."
  args = buildArgs()
  script = spawn('bash', args)
  out.info "Executing bash script #{args.join ' '}"

  script.stdout.on 'data', out.info
  script.stderr.on 'data', out.error

  script.on 'close', (code) ->
    out.info "Script exited with status #{code}"
    callback code is 0


bothTrigger = (out, callback) ->
  options =
    url: config.getConf()['sync-type']['both-trigger-url']
    cert: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-cert']
    key: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-key']
    ca: nullIfEmpty config.getConf()['sync-type']['both-trigger-ca-cert']
    timeout: 0

  out.info "Triggering #{options.url} ..."

  beforeTimestamp = new Date()
  request.get options, (err, res, body) ->
    if err
      out.error "Trigger failed: #{err}"
      return callback false

    out.pushOrchestration
      name: 'Trigger'
      request:
        path: options.url
        method: 'GET'
        timestamp: beforeTimestamp
      response:
        status: res.statusCode
        headers: res.headers
        body: body
        timestamp: new Date()

    out.info "Response: [#{res.statusCode}] #{body}"
    if 200 <= res.statusCode <= 399
      callback true
    else
      out.error 'Trigger failed'
      callback false


ilrToDhis = (out, callback) ->
  # TODO

  # get dxfData to import from ILR
  # TODO - Get dxfData from ILR request
  dxfData = null
  postToDhis out, dxfData, (result) ->
    if result
      callback true
    else
      out.error 'POST to DHIS2 failed'
      callback false

# post DXF data to DHIS2 api
postToDhis = (out, dxfData, callback) ->
  if not dxfData
    out.info "No DXF body supplied"
    return callback false

  options =
    url: config.getConf()['ilr-to-dhis']['dhis2-url'] + '/api/metadata.xml'
    data: dxfData
    auth:
      username: config.getConf()['ilr-to-dhis']['dhis2-user']
      password: config.getConf()['ilr-to-dhis']['dhis2-pass']
    cert: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-cert']
    key: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-key']
    ca: nullIfEmpty config.getConf()['sync-type']['both-trigger-ca-cert']
    timeout: 0

  beforeTimestamp = new Date()
  request.post options, (err, res, body) ->
    if err
      out.error "Post to DHIS2 failed: #{err}"
      return callback false

    out.pushOrchestration
      name: 'DHIS2 Import'
      request:
        path: options.url
        method: 'POST'
        timestamp: beforeTimestamp
      response:
        status: res.statusCode
        headers: res.headers
        body: body
        timestamp: new Date()

    out.info "Response: [#{res.statusCode}] #{body}"
    if 200 <= res.statusCode <= 399
      callback true
    else
      out.error 'Post to DHIS2 failed'
      callback false


handler = (req, res) ->
  openhimTransactionID = req.headers['x-openhim-transactionid']

  _out = ->
    body = ""
    orchestrations = []

    append = (level, data) ->
      logger[level]("[#{openhimTransactionID}] #{data}")
      if data[-1..] isnt '\n'
        body = "#{body}#{data}\n"
      else
        body = "#{body}#{data}"

    return {
      body: -> body
      info: (data) -> append 'info', data
      error: (data) -> append 'error', data
      pushOrchestration: (o) -> orchestrations.push o
      orchestrations: -> orchestrations
    }
  out = _out()

  out.info "Running sync with mode #{config.getConf()['sync-type']['mode']} ..."

  end = (successful) ->
    res.set 'Content-Type', 'application/json+openhim'
    res.send {
      'x-mediator-urn': config.getMediatorConf().urn
      status: if successful then 'Successful' else 'Failed'
      response:
        status: if successful then 200 else 500
        headers:
          'content-type': 'application/json'
        body: out.body()
        timestamp: new Date()
      orchestrations: out.orchestrations()
    }

  if config.getConf()['sync-type']['mode'] is 'DHIS2 to ILR'
    dhisToIlr out, end
  else if config.getConf()['sync-type']['mode'] is 'ILR to DHIS2'
    ilrToDhis out, end
  else
    dhisToIlr out, (successful) ->
      if not successful then return end false

      next = ->
        ilrToDhis out, end
      if config.getConf()['sync-type']['both-trigger-enabled']
        bothTrigger out, (successful) ->
          if not successful then return end false
          next()
      else
        next()
  

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
    if err
      logger.error err
      process.exit 1

    logger.info 'Mediator has been successfully registered'

    configEmitter = mediatorUtils.activateHeartbeat config.getConf().openhim.api

    configEmitter.on 'config', (newConfig) ->
      logger.info 'Received updated config from core'
      config.updateConf newConfig
      saveConfigToFile()

    configEmitter.on 'error', (err) -> logger.error err

    mediatorUtils.fetchConfig config.getConf().openhim.api, (err, newConfig) ->
      return logger.error err if err
      logger.info 'Received initial config from core'
      config.updateConf newConfig
      saveConfigToFile()
 

if process.env.NODE_ENV is 'test'
  exports.app = app
  exports.bothTrigger = bothTrigger
  exports.postToDhis = postToDhis
