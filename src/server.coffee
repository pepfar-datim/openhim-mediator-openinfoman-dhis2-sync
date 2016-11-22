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
nullIfEmpty = (s) -> if s? and s.trim().length>0 then s else null

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

dhisToIlr = (out, callback) ->
  out.info "Running dhis-to-ilr ..."
  args = buildArgs()
  beforeTimestamp = new Date()
  script = spawn('bash', args)
  out.info "Executing bash script #{args.join ' '}"

  logs = ""
  script.stdout.on 'data', out.info
  script.stdout.on 'data', (data) -> logs += data.toString() + '\n'
  script.stderr.on 'data', out.error
  script.stderr.on 'data', (data) -> logs += data.toString() + '\n'

  script.on 'close', (code) ->
    out.info "Script exited with status #{code}"
    logs += "Script exited with status #{code}"

    out.pushOrchestration
      name: 'Execute Publish_to_ilr.sh'
      request:
        timestamp: beforeTimestamp
      response:
        status: code
        body: logs
        timestamp: new Date()

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

setDHISDataStore = (namespace, key, data, update, callback) ->
  options =
    url: config.getConf()['ilr-to-dhis']['dhis2-url'] + "/api/dataStore/#{namespace}/#{key}"
    body: data
    auth:
      username: config.getConf()['ilr-to-dhis']['dhis2-user']
      password: config.getConf()['ilr-to-dhis']['dhis2-pass']
    cert: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-cert']
    key: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-key']
    ca: nullIfEmpty config.getConf()['sync-type']['both-trigger-ca-cert']
    json: true

  if update
    options.method = 'PUT'
  else
    options.method = 'POST'

  request options, (err, res, body) ->
    if err
      return callback err
    else if (res.statusCode isnt 201 and not update) or (res.statusCode isnt 200 and update)
      return callback new Error "Set value in datastore failed: [status #{res.statusCode}] #{JSON.stringify(body)}"
    else
      return callback null, body


getDHISDataStore = (namespace, key, callback) ->
  options =
    url: config.getConf()['ilr-to-dhis']['dhis2-url'] + "/api/dataStore/#{namespace}/#{key}"
    auth:
      username: config.getConf()['ilr-to-dhis']['dhis2-user']
      password: config.getConf()['ilr-to-dhis']['dhis2-pass']
    cert: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-cert']
    key: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-key']
    ca: nullIfEmpty config.getConf()['sync-type']['both-trigger-ca-cert']
    json: true

  request.get options, (err, res, body) ->
    if err
      return callback err
    else if res.statusCode isnt 200
      return callback new Error "Get value in datastore failed: [status #{res.statusCode}] #{JSON.stringify(body)}"
    else
      return callback null, body

# Fetch last import timestamp and create if it doesn't exist
fetchLastImportTs = (callback) ->
  getDHISDataStore 'CSD-Loader-Last-Import', config.getConf()['ilr-to-dhis']['ilr-doc'], (err, data) ->
    if err
      logger.info 'Could not find last updated timestamp, creating one.'
      date = new Date(0)
      setDHISDataStore 'CSD-Loader-Last-Import', config.getConf()['ilr-to-dhis']['ilr-doc'], value: date, false, (err) ->
        if err then return callback new Error "Could not write last export to DHIS2 datastore #{err.stack}"
        callback null, date.toISOString()
    else
      callback null, data.value

# Fetch DXF from ILR (openinfoman)
fetchDXFFromIlr = (out, callback) ->
  fetchLastImportTs (err, lastImport) ->
    if err then return callback err

    ilrOptions =
      url: "#{config.getConf()['ilr-to-dhis']['ilr-url']}/csr/#{config.getConf()['ilr-to-dhis']['ilr-doc']}/careServicesRequest/urn:dhis.org:transform_to_dxf:#{config.getConf()['ilr-to-dhis']['dhis2-version']}"
      body: """<csd:requestParams xmlns:csd='urn:ihe:iti:csd:2013'>
                <processUsers value='0'/>
                <preserveUUIDs value='1'/>
                <zip value='0'/>
                <onlyDirectChildren value='0'/>
                <csd:record updated='#{lastImport}'/>
              </csd:requestParams>"""
      headers:
        'Content-Type': 'text/xml'
      cert: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-cert']
      key: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-key']
      ca: nullIfEmpty config.getConf()['sync-type']['both-trigger-ca-cert']

    if config.getConf()['ilr-to-dhis']['ilr-user'] and config.getConf()['ilr-to-dhis']['ilr-pass']
      ilrOptions.auth =
        user: config.getConf()['ilr-to-dhis']['ilr-user']
        pass: config.getConf()['ilr-to-dhis']['ilr-pass']

    out.info "Fetching DXF from ILR #{ilrOptions.url} ..."
    out.info "with body: #{ilrOptions.body}"
    beforeTimestamp = new Date()
    ilrReq = request.post ilrOptions, (err, res, body) ->
      if err
        out.error "POST to ILR failed: #{err.stack}"
        return callback err
      if res.statusCode isnt 200
        out.error "ILR stored query failed with response code #{res.statusCode} and body: #{body}"
        return callback new Error "Returned non-200 response code: #{body}"

      out.pushOrchestration
        name: 'Extract DXF from ILR'
        request:
          path: ilrOptions.url
          method: 'POST'
          body: ilrOptions.body
          timestamp: beforeTimestamp
        response:
          status: res.statusCode
          headers: res.headers
          body: body
          timestamp: new Date()

      setDHISDataStore 'CSD-Loader-Last-Import', config.getConf()['ilr-to-dhis']['ilr-doc'], value: beforeTimestamp, true, (err) ->
        if err then logger.error "Failed to set last import date in DHIS2 datastore #{err}"
      callback null, body


# post DXF data to DHIS2 api
postToDhis = (out, dxfData, callback) ->
  if not dxfData
    out.info "No DXF body supplied"
    return callback false

  options =
    url: config.getConf()['ilr-to-dhis']['dhis2-url'] + '/api/metadata'
    body: dxfData
    method: 'POST'
    auth:
      username: config.getConf()['ilr-to-dhis']['dhis2-user']
      password: config.getConf()['ilr-to-dhis']['dhis2-pass']
    cert: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-cert']
    key: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-key']
    ca: nullIfEmpty config.getConf()['sync-type']['both-trigger-ca-cert']
    timeout: 0
    headers: { 'content-type': 'application/xml' }

  beforeTimestamp = new Date()
  request.post options, (err, res, body) ->
    if err
      out.error "Post to DHIS2 failed: #{err}"
      return callback false

    out.pushOrchestration
      name: 'DHIS2 Import'
      request:
        path: options.url
        method: options.method
        body: options.body
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

# Poll DHIS2 task, period and timeout are in ms
pollTask = (out, task, period, timeout, callback) ->
  pollNum = 0
  beforeTimestamp = new Date()
  interval = setInterval () ->
    options =
      url: config.getConf()['ilr-to-dhis']['dhis2-url'] + '/api/system/tasks/' + task
      auth:
        username: config.getConf()['ilr-to-dhis']['dhis2-user']
        password: config.getConf()['ilr-to-dhis']['dhis2-pass']
      cert: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-cert']
      key: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-key']
      ca: nullIfEmpty config.getConf()['sync-type']['both-trigger-ca-cert']
      json: true
    request.get options, (err, res, tasks) ->
      if err
        clearInterval interval
        return callback err
      if res.statusCode isnt 200
        clearInterval interval
        return callback new Error "Incorrect status code recieved, #{res.statusCode}"
      pollNum++
      if not tasks[0]?.completed?
        return callback new Error 'No tasks returned or bad tasks response recieved'
      if tasks[0]?.completed is true
        clearInterval interval

        out.pushOrchestration
          name: "Polled DHIS resource rebuild task #{pollNum} times"
          request:
            path: options.url
            method: options.method
            body: options.body
            timestamp: beforeTimestamp
          response:
            status: res.statusCode
            headers: res.headers
            body: JSON.stringify(tasks)
            timestamp: new Date()

        return callback()
      if pollNum * period >= timeout
        clearInterval interval
        return callback new Error "Polled tasks endpoint #{pollNum} time and still not completed, timing out..."
  , period

# initiate a resource table rebuild task on DHIS and wait for the task to complete
rebuildDHIS2resourceTable = (out, callback) ->
  options =
    url: config.getConf()['ilr-to-dhis']['dhis2-url'] + '/api/resourceTables'
    method: 'POST'
    auth:
      username: config.getConf()['ilr-to-dhis']['dhis2-user']
      password: config.getConf()['ilr-to-dhis']['dhis2-pass']
    cert: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-cert']
    key: nullIfEmpty config.getConf()['sync-type']['both-trigger-client-key']
    ca: nullIfEmpty config.getConf()['sync-type']['both-trigger-ca-cert']

  beforeTimestamp = new Date()
  request.post options, (err, res, body) ->
    if err
      out.error "Resource tables refresh in DHIS2 failed: #{err}"
      return callback err

    out.pushOrchestration
      name: 'DHIS2 resource table refresh'
      request:
        path: options.url
        method: options.method
        body: options.body
        timestamp: beforeTimestamp
      response:
        status: res.statusCode
        headers: res.headers
        body: body
        timestamp: new Date()

    out.info "Response: [#{res.statusCode}] #{body}"
    if res.statusCode is 200
      period = config.getConf()['ilr-to-dhis']['dhis2-poll-period']
      timeout = config.getConf()['ilr-to-dhis']['dhis2-poll-timeout']
      pollTask out, 'RESOURCETABLE_UPDATE', period, timeout, (err) ->
        if err then return callback err

        return callback()
    else
      out.error "Resource tables refresh in DHIS2 failed, statusCode: #{res.statusCode}"
      callback new Error "Resource tables refresh in DHIS2 failed, statusCode: #{res.statusCode}"


ilrToDhis = (out, callback) ->
  fetchDXFFromIlr out, (err, dxf) ->
    if err then return callback false
    postToDhis out, dxf, (result) ->
      if result
        if config.getConf()['ilr-to-dhis']['dhis2-rebuild-resources']
          rebuildDHIS2resourceTable out, (err) ->
            if err then return callback false
            callback true
        else
          callback true
      else
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

server = null
exports.start = (callback) ->
  server = app.listen config.getConf().server.port, config.getConf().server.hostname, ->
    logger.info "[#{process.env.NODE_ENV}] #{config.getMediatorConf().name} running on port #{server.address().address}:#{server.address().port}"
    if callback then callback null, server
  server.on 'error', (err) ->
    if callback then callback err
  server.timeout = 0

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

exports.stop = (callback) ->
  server.close ->
    if callback then callback()

if not module.parent then exports.start()

if process.env.NODE_ENV is 'test'
  exports.app = app
  exports.bothTrigger = bothTrigger
  exports.postToDhis = postToDhis
  exports.fetchDXFFromIlr = fetchDXFFromIlr
  exports.pollTask = pollTask
  exports.rebuildDHIS2resourceTable = rebuildDHIS2resourceTable
  exports.setDHISDataStore = setDHISDataStore
  exports.getDHISDataStore = getDHISDataStore
  exports.fetchLastImportTs = fetchLastImportTs
