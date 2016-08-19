https = require 'https'
fs = require 'fs'
server = require '../lib/server'
logger = require 'winston'
should = require 'should'
config = require '../lib/config'

describe 'Trigger test', ->
  target = null
  targetCalled = false

  errorTarget = null
  errorTargetCalled = false

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
      targetCalled = true
      res.writeHead 200, {'Content-Type': 'text/plain'}
      res.end 'OK'
    errorTarget = https.createServer options, (req, res) ->
      errorTargetCalled = true
      res.writeHead 500, {'Content-Type': 'text/plain'}
      res.end 'Not OK'

    target.listen 7123, (err) ->
      return done err if err
      errorTarget.listen 7124, done


  beforeEach (done) ->
    targetCalled = false
    errorTargetCalled = false
    done()

  after (done) -> target.close -> errorTarget.close -> done()

  it 'should send a GET request to a target server', (done) ->
    config.getConf()['sync-type']['both-trigger-url'] = 'https://localhost:7123/ILR/CSD/pollService/directory/DATIM-OU-TZ/update_cache'
    out =
      info: (data) -> logger.info data
      error: (data) -> logger.error data
    server.bothTrigger out, (successful) ->
      successful.should.be.exactly true
      targetCalled.should.be.exactly true
      done()

  it 'should return with successful false if target responds with a non-200 status code', (done) ->
    config.getConf()['sync-type']['both-trigger-url'] = 'https://localhost:7124/ILR/CSD/pollService/directory/DATIM-OU-TZ/update_cache'
    out =
      info: (data) -> logger.info data
      error: (data) -> logger.info "[this is expected] #{data}"
    server.bothTrigger out, (successful) ->
      successful.should.be.exactly false
      errorTargetCalled.should.be.exactly true
      done()
