fs = require 'fs'
https = require 'https'
should = require 'should'
logger = require 'winston'

config = require '../lib/config'
server = require '../lib/server'

describe 'fetchDXFFromIlr()', ->
  target = null
  targetCalled = false

  errorTarget = null
  errorTargetCalled = false

  out =
    info: (data) -> logger.info data
    error: (data) -> logger.error data
    pushOrchestration: (o) -> logger.info o

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
      res.end 'DXF'
    errorTarget = https.createServer options, (req, res) ->
      errorTargetCalled = true
      res.writeHead 500, {'Content-Type': 'text/plain'}
      res.end 'Error'

    target.listen 7125, (err) ->
      return done err if err
      errorTarget.listen 7126, done

  it 'should call ilr to fetch dxf', (done) ->
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7125/ILR/CSD'
    server.fetchDXFFromIlr out, (err, dxf) ->
      should.not.exist err
      dxf.toString().should.be.exactly 'DXF'
      done()

  it 'should return an error when a non-200 response code is received', (done) ->
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7126/ILR/CSD'
    server.fetchDXFFromIlr out, (err, dxf) ->
      should.exist err
      err.message.should.be.exactly 'Returned non-200 response code: Error'
      done()

  it 'should return an error when a connection error occurs', (done) ->
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7127/ILR/CSD'
    server.fetchDXFFromIlr out, (err, dxf) ->
      should.exist err
      err.message.should.be.exactly 'connect ECONNREFUSED 127.0.0.1:7127'
      done()
