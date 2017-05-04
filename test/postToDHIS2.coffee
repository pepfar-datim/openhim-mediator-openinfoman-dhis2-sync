https = require 'https'
fs = require 'fs'
url = require 'url'

server = require '../lib/server'
logger = require 'winston'
should = require 'should'
config = require '../lib/config'

describe 'Post DXF to DHIS2', ->

  before (done) ->
    config.getConf()['sync-type']['both-trigger-client-cert'] = "#{fs.readFileSync 'test/resources/client-cert.pem'}"
    config.getConf()['sync-type']['both-trigger-client-key'] = "#{fs.readFileSync 'test/resources/client-key.pem'}"
    config.getConf()['sync-type']['both-trigger-ca-cert'] = "#{fs.readFileSync 'test/resources/server-cert.pem'}"

    options =
      key: fs.readFileSync 'test/resources/server-key.pem'
      cert: fs.readFileSync 'test/resources/server-cert.pem'
      ca: fs.readFileSync 'test/resources/client-cert.pem'
      requestCert: true
      rejectUnauthorized: true
      secureProtocol: 'TLSv1_method'

    target = https.createServer options, (req, res) ->
      res.writeHead 200, {'Content-Type': 'text/plain'}
      res.end 'OK'
    errorTarget = https.createServer options, (req, res) ->
      res.writeHead 500, {'Content-Type': 'text/plain'}
      res.end 'Not OK'
    asyncTarget = https.createServer options, (req, res) ->
      urlObj = url.parse req.url, true
      if urlObj.query.async
        res.writeHead 202, {'Content-Type': 'text/plain'}
        res.end 'OK'
      else
        res.writeHead 500, {'Content-Type': 'text/plain'}
        res.end 'Not OK'
        
    asyncReceiverTarget = https.createServer options, (req, res) ->
      res.writeHead 200, {'Content-Type': 'text/plain'}
      res.end 'Test Response'

    target.listen 8443, (err) ->
      return done err if err
      errorTarget.listen 8124, (err) ->
        return done err if err
        asyncTarget.listen 8125, (err) ->
          return done err if err
          asyncReceiverTarget.listen 8126, (err) ->
            return done err if err
            done()

  it 'should NOT send request if DXF is empty', (done) ->
    dxfData = undefined
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8443'
    out =
      info: (data) -> logger.info data
      error: (data) -> logger.error data
      pushOrchestration: (o) -> logger.info o
    server.postToDhis out, dxfData, (success) ->
      success.should.be.exactly false
      done()

  it 'should send a POST request with DXF body to a DHIS2 server', (done) ->
    dxfData = fs.readFileSync 'test/resources/metaData.xml'
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8443'
    out =
      info: (data) -> logger.info data
      error: (data) -> logger.error data
      pushOrchestration: (o) -> logger.info o
    server.postToDhis out, dxfData, (success) ->
      success.should.be.exactly true
      done()

  it 'should send async option if it is set', (done) ->
    dxfData = fs.readFileSync 'test/resources/metaData.xml'
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8125'
    config.getConf()['ilr-to-dhis']['dhis2-async'] = true
    config.getConf()['ilr-to-dhis']['async-receiver-url'] = 'https://localhost:8126'
    out =
      info: (data) -> logger.info data
      error: (data) -> logger.error data
      pushOrchestration: (o) -> logger.info o
    server.postToDhis out, dxfData, (success) ->
      success.should.be.exactly true
      done()
    
  it 'should send dhis2 message to async receiver mediator when async job is complete', (done) ->
    orchestrations = []
    dxfData = fs.readFileSync 'test/resources/metaData.xml'
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8125'
    config.getConf()['ilr-to-dhis']['dhis2-async'] = true
    config.getConf()['ilr-to-dhis']['async-receiver-url'] = 'https://localhost:8126'
    out =
      info: (data) -> logger.info data
      error: (data) -> logger.error data
      pushOrchestration: (o) ->
        logger.info o
        orchestrations.push o
    server.postToDhis out, dxfData, (success) ->
      success.should.be.exactly true
      orchestrations[1].name.should.be.exactly 'Send to Async Receiver'
      orchestrations[1].response.body.should.be.exactly 'Test Response'
      done()
