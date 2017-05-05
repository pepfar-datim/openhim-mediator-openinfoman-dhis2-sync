https = require 'https'
fs = require 'fs'
url = require 'url'

server = require '../lib/server'
logger = require 'winston'
should = require 'should'
config = require '../lib/config'

describe 'Post DXF to DHIS2', ->
  pollingTargetCalled = false
  timesTargetCalled = 0
  orchestrations = []

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
      else if urlObj.pathname is '/api/system/tasks/METADATA_IMPORT'
        pollingTargetCalled = true
        timesTargetCalled++
        res.writeHead 200, {'Content-Type': 'application/json'}
        if timesTargetCalled > 3
          res.end JSON.stringify([
            uid: "k6NsQt9w890"
            level: "INFO"
            category: "METADATA_IMPORT"
            time: "2016-09-05T10:01:32.596"
            message: "message"
            completed: true
          ,
            uid: "t2tcsdDRZPg"
            level: "INFO"
            category: "METADATA_IMPORT"
            time: "2016-09-05T10:01:32.596"
            message: "message"
            completed: false
          ])
        else
          res.end JSON.stringify([
            uid: "t2tjPXDR3dr"
            level: "INFO"
            category: "METADATA_IMPORT"
            time: "2016-09-05T10:01:32.596"
            message: "message"
            completed: false
          ])

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

  beforeEach (done) ->
    pollingTargetCalled = false
    timesTargetCalled = 0
    orchestrations = []
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
    config.getConf()['ilr-to-dhis']['dhis2-poll-period'] = 20
    config.getConf()['ilr-to-dhis']['dhis2-poll-timeout'] = 100
    config.getConf()['ilr-to-dhis']['dhis2-async-receiver-url'] = 'https://localhost:8126'
    out =
      info: (data) -> logger.info data
      error: (data) -> logger.error data
      pushOrchestration: (o) -> logger.info o
    server.postToDhis out, dxfData, (success) ->
      success.should.be.exactly true
      done()

  it 'should callback when polling task has completed', (done) ->
    dxfData = fs.readFileSync 'test/resources/metaData.xml'
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8125'
    config.getConf()['ilr-to-dhis']['dhis2-async'] = true
    config.getConf()['ilr-to-dhis']['dhis2-poll-period'] = 20
    config.getConf()['ilr-to-dhis']['dhis2-poll-timeout'] = 100
    config.getConf()['ilr-to-dhis']['dhis2-async-receiver-url'] = 'https://localhost:8126'
    out =
      info: (data) -> logger.info data
      error: (data) -> logger.error data
      pushOrchestration: (o) -> logger.info o
    server.postToDhis out, dxfData, (success) ->
      success.should.be.exactly true
      pollingTargetCalled.should.be.true()
      timesTargetCalled.should.be.exactly 4
      done()

  it 'should return an error when the polling task reached its timeout limit', (done) ->
    dxfData = fs.readFileSync 'test/resources/metaData.xml'
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8125'
    config.getConf()['ilr-to-dhis']['dhis2-async'] = true
    config.getConf()['ilr-to-dhis']['dhis2-poll-period'] = 50
    config.getConf()['ilr-to-dhis']['dhis2-poll-timeout'] = 100
    config.getConf()['ilr-to-dhis']['dhis2-async-receiver-url'] = 'https://localhost:8126'
    out =
      info: (data) -> logger.info data
      error: (data) -> logger.error data
      pushOrchestration: (o) -> logger.info o
    server.postToDhis out, dxfData, (err) ->
      should.exist err
      err.message.should.be.exactly 'Polled tasks endpoint 2 time and still not completed, timing out...'
      pollingTargetCalled.should.be.true()
      timesTargetCalled.should.be.exactly 2
      done()

  it 'should add an orchestration for the polling task', (done) ->
    dxfData = fs.readFileSync 'test/resources/metaData.xml'
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8125'
    config.getConf()['ilr-to-dhis']['dhis2-async'] = true
    config.getConf()['ilr-to-dhis']['dhis2-poll-period'] = 20
    config.getConf()['ilr-to-dhis']['dhis2-poll-timeout'] = 100
    config.getConf()['ilr-to-dhis']['dhis2-async-receiver-url'] = 'https://localhost:8126'
    out =
      info: (data) -> logger.info data
      error: (data) -> logger.error data
      pushOrchestration: (o) ->
        logger.info o
        orchestrations.push o
    server.postToDhis out, dxfData, (success) ->
      success.should.be.exactly true
      pollingTargetCalled.should.be.true()
      timesTargetCalled.should.be.exactly 4
      orchestrations.length.should.be.exactly 3
      orchestrations[0].name.should.be.exactly 'DHIS2 Import'
      orchestrations[1].name.should.be.exactly 'Polled DHIS sites import task 4 times'
      done()
    
  it 'should send dhis2 message to async receiver mediator when async job is complete', (done) ->
    dxfData = fs.readFileSync 'test/resources/metaData.xml'
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8125'
    config.getConf()['ilr-to-dhis']['dhis2-async'] = true
    config.getConf()['ilr-to-dhis']['dhis2-async-receiver-url'] = 'https://localhost:8126'
    out =
      info: (data) -> logger.info data
      error: (data) -> logger.error data
      pushOrchestration: (o) ->
        logger.info o
        orchestrations.push o
    server.postToDhis out, dxfData, (success) ->
      success.should.be.exactly true
      orchestrations[2].name.should.be.exactly 'Send to Async Receiver'
      orchestrations[2].response.body.should.be.exactly 'Test Response'
      done()
