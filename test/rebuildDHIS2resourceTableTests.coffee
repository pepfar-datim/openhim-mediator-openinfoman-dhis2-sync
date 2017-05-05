https = require 'https'
fs = require 'fs'
logger = require 'winston'
should = require 'should'
sinon = require 'sinon'
rewire = require 'rewire'
server = rewire '../lib/server'
config = require '../lib/config'

describe 'Rebuild DHIS2 resource table', ->

  describe '.pollTask()', ->
    target = null
    targetCalled = false
    authPresent = false

    errorTarget = null
    errorTargetCalled = false
    orchestrations = []
    timesTargetCalled = 0

    out =
      info: (data) -> logger.info data
      error: (data) -> logger.error data
      pushOrchestration: (o) ->
        logger.info o
        orchestrations.push o

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
        timesTargetCalled++
        authPresent = req.headers.authorization?
        res.writeHead 200, {'Content-Type': 'application/json'}
        if timesTargetCalled > 3
          res.end JSON.stringify([
            uid: "k6NsQt9wPY1"
            level: "INFO"
            category: "RESOURCETABLE_UPDATE"
            time: "2016-09-05T10:01:32.596"
            message: "Resource tables generated: 00:00:17.862"
            completed: true
          ,
            uid: "t2tjPXDRZPg"
            level: "INFO"
            category: "RESOURCETABLE_UPDATE"
            time: "2016-09-05T10:01:32.596"
            message: "Generating resource tables"
            completed: false
          ])
        else
          res.end JSON.stringify([
            uid: "t2tjPXDRZPg"
            level: "INFO"
            category: "RESOURCETABLE_UPDATE"
            time: "2016-09-05T10:01:32.596"
            message: "Generating resource tables"
            completed: false
          ])

      errorTarget = https.createServer options, (req, res) ->
        errorTargetCalled = true
        res.writeHead 500, {'Content-Type': 'text/plain'}
        res.end 'Error'

      target.listen 7130, (err) ->
        return done err if err
        errorTarget.listen 7131, done

    beforeEach (done) ->
      targetCalled = false
      errorTargetCalled = false
      authPresent = false
      orchestrations = []
      timesTargetCalled = 0

      done()

    after (done) ->
      target.close ->
        errorTarget.close ->
          done()

    it 'should poll tasks until completed is returned', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:7130'
      server.pollTask out, 'resource rebuild', 'RESOURCETABLE_UPDATE', 20, 100, (err) ->
        should.not.exist err
        timesTargetCalled.should.be.exactly 4
        authPresent.should.be.true()
        done()

    it 'should return an error if something goes wrong querying tasks', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:7131'
      server.pollTask out, 'resource rebuild', 'RESOURCETABLE_UPDATE', 20, 100, (err) ->
        should.exist err
        err.message.should.be.exactly 'Incorrect status code received, 500'
        done()

    it 'should timeout', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:7130'
      server.pollTask out, 'resource rebuild', 'RESOURCETABLE_UPDATE', 80, 100, (err) ->
        should.exist err
        err.message.should.be.exactly 'Polled tasks endpoint 2 time and still not completed, timing out...'
        done()

    it 'should record an orchestration', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:7130'
      server.pollTask out, 'resource rebuild', 'RESOURCETABLE_UPDATE', 20, 100, (err) ->
        should.not.exist err
        orchestrations.length.should.be.exactly 1
        orchestrations[0].name.should.be.exactly 'Polled DHIS resource rebuild task 4 times'
        done()

  describe '.rebuildDHIS2resourceTable()', ->
    target = null
    targetCalled = false
    authPresent = false

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
        authPresent = req.headers.authorization?
        res.writeHead 200, {'Content-Type': 'application/json'}
        res.end()
      errorTarget = https.createServer options, (req, res) ->
        errorTargetCalled = true
        res.writeHead 500, {'Content-Type': 'application/json'}
        res.end()

      target.listen 8543, (err) ->
        return done err if err
        errorTarget.listen 8544, done

    origPollTaskFunc = null
    beforeEach (done) ->
      stub = sinon.stub()
      stub.callsArg 5
      origPollTaskFunc = server.__get__('pollTask')
      server.__set__('pollTask', stub)
      targetCalled = false
      errorTargetCalled = false
      authPresent = false
      orchestrations = []

      done()

    afterEach ->
      server.__set__('pollTask', origPollTaskFunc)

    after (done) ->
      target.close ->
        errorTarget.close ->
          done()

    it 'should callback when a 200 response is received', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8543'
      server.rebuildDHIS2resourceTable out, (err) ->
        should.not.exist err
        targetCalled.should.be.true()
        authPresent.should.be.true()
        done()

    it 'should return an error when a NON 200 response is received', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8544'
      server.rebuildDHIS2resourceTable out, (err) ->
        should.exist err
        err.message.should.be.exactly 'Resource tables refresh in DHIS2 failed, statusCode: 500'
        errorTargetCalled.should.be.true()
        done()

    it 'should add an orchestration', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8543'
      server.rebuildDHIS2resourceTable out, (err) ->
        should.not.exist err
        orchestrations.length.should.be.exactly 1
        orchestrations[0].name.should.be.exactly 'DHIS2 resource table refresh'
        done()
