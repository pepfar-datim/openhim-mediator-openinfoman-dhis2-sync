fs = require 'fs'
https = require 'https'
should = require 'should'
logger = require 'winston'

config = require '../lib/config'
server = require '../lib/server'

describe 'fetchDXFFromIlr()', ->
  target = null
  targetCalled = false
  authPresent = false
  fetchTsCallled = false
  updateTsCallled = false

  errorTarget = null
  errorTargetCalled = false
  orchestrations = []

  out =
    info: (data) -> logger.info data
    error: (data) -> logger.error data
    pushOrchestration: (o) ->
      logger.info o
      orchestrations.push o

  before (done) ->
    config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://localhost:32001/dhis2"

    options =
      key: fs.readFileSync 'test/resources/server-key.pem'
      cert: fs.readFileSync 'test/resources/server-cert.pem'
      ca: fs.readFileSync 'test/resources/client-cert.pem'
      requestCert: true
      rejectUnauthorized: true
      secureProtocol: 'TLSv1_method'

    target = https.createServer options, (req, res) ->
      targetCalled = true
      authPresent = req.headers.authorization?
      res.writeHead 200, {'Content-Type': 'text/plain'}
      res.end 'DXF'
    errorTarget = https.createServer options, (req, res) ->
      errorTargetCalled = true
      res.writeHead 500, {'Content-Type': 'text/plain'}
      res.end 'Error'
    dhisMock = https.createServer options, (req, res) ->
      if req.method is 'GET'
        fetchTsCallled = true
        res.writeHead 200, {'Content-Type': 'application/json'}
        res.end(JSON.stringify(value: new Date))
      else if req.method is 'PUT'
        updateTsCallled = true
        res.writeHead 200, {'Content-Type': 'application/json'}
        res.end()

    target.listen 7125, (err) ->
      return done err if err
      errorTarget.listen 7126, ->
        dhisMock.listen 32001, done

  beforeEach (done) ->
    targetCalled = false
    errorTargetCalled = false
    authPresent = false
    orchestrations = []

    done()

  it 'should call ilr to fetch dxf', (done) ->
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7125/ILR/CSD'
    server.fetchDXFFromIlr out, (err, dxf) ->
      should.not.exist err
      dxf.toString().should.be.exactly 'DXF'
      targetCalled.should.be.true()
      done()

  it 'should return an error when a non-200 response code is received', (done) ->
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7126/ILR/CSD'
    server.fetchDXFFromIlr out, (err, dxf) ->
      should.exist err
      err.message.should.be.exactly 'Returned non-200 response code: Error'
      errorTargetCalled.should.be.true()
      done()

  it 'should return an error when a connection error occurs', (done) ->
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7127/ILR/CSD'
    server.fetchDXFFromIlr out, (err, dxf) ->
      should.exist err
      err.message.should.be.exactly 'connect ECONNREFUSED 127.0.0.1:7127'
      targetCalled.should.be.false()
      errorTargetCalled.should.be.false()
      done()

  it 'should add an orchestration', (done) ->
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7125/ILR/CSD'
    server.fetchDXFFromIlr out, (err, dxf) ->
      should.not.exist err
      orchestrations.length.should.be.exactly 1
      orchestrations[0].name.should.be.exactly 'Extract DXF from ILR'
      done()

  it 'should add basic auth if ilr auth config present', (done) ->
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7125/ILR/CSD'
    config.getConf()['ilr-to-dhis']['ilr-user'] = 'user'
    config.getConf()['ilr-to-dhis']['ilr-pass'] = 'pass'
    server.fetchDXFFromIlr out, (err, dxf) ->
      should.not.exist err
      authPresent.should.be.true()
      done()

  it 'should fetch last updated ts', (done) ->
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7125/ILR/CSD'
    server.fetchDXFFromIlr out, (err, dxf) ->
      should.not.exist err
      fetchTsCallled.should.be.true()
      done()

  it 'should update last updated ts', (done) ->
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7125/ILR/CSD'
    server.fetchDXFFromIlr out, (err, dxf) ->
      should.not.exist err
      updateTsCallled.should.be.true()
      done()
