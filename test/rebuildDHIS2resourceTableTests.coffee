https = require 'https'
fs = require 'fs'
server = require '../lib/server'
logger = require 'winston'
should = require 'should'
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

    it 'should poll tasks until completed is returned', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:7130'
      server.pollTask out, 'RESOURCETABLE_UPDATE', 10, 50, (err) ->
        should.not.exist err
        timesTargetCalled.should.be.exactly 4
        done()

    it 'should return an error if something goes wrong querying tasks', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:7131'
      server.pollTask out, 'RESOURCETABLE_UPDATE', 10, 50, (err) ->
        should.exist err
        err.message.should.be.exactly 'Incorrect status code recieved, 500'
        done()

    it 'should timeout', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:7130'
      server.pollTask out, 'RESOURCETABLE_UPDATE', 40, 50, (err) ->
        should.exist err
        err.message.should.be.exactly 'Polled tasks endpoint 2 time and still not completed, timing out...'
        done()

    it 'should record an orchestration', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:7130'
      server.pollTask out, 'RESOURCETABLE_UPDATE', 10, 50, (err) ->
        should.not.exist err
        orchestrations.length.should.be.exactly 1
        orchestrations[0].name.should.be.exactly 'Polled DHIS resource rebuild task 4 times'
        done()
