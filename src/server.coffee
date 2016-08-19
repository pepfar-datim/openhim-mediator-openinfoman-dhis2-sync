require './init'

logger = require 'winston'
config = require './config'

express = require 'express'
bodyParser = require 'body-parser'
mediatorUtils = require 'openhim-mediator-utils'
util = require './util'
fs = require 'fs'
spawn = require('child_process').spawn


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

handler = (req, res) ->
  openhimTransactionID = req.headers['x-openhim-transactionid']
  logger.info "[#{openhimTransactionID}] Running sync ..."

  args = buildArgs()
  script = spawn('bash', args)
  logger.info "[#{openhimTransactionID}] Executing bash script #{args.join ' '}"

  out = ""
  appendToOut = (data) -> out = "#{out}#{data}"
  script.stdout.on 'data', appendToOut
  script.stderr.on 'data', appendToOut

  script.on 'close', (code) ->
    logger.info "[#{openhimTransactionID}] Script exited with status #{code}"

    res.set 'Content-Type', 'application/json+openhim'
    res.send {
      'x-mediator-urn': config.getMediatorConf().urn
      status: if code == 0 then 'Successful' else 'Failed'
      response:
        status: if code == 0 then 200 else 500
        headers:
          'content-type': 'application/json'
        body: out
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
 

exports.app = app
