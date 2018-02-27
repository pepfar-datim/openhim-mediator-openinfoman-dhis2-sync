/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const https = require('https');
const fs = require('fs');
const logger = require('winston');
const should = require('should');
const sinon = require('sinon');
const rewire = require('rewire');
const server = rewire('../lib/server');
const config = require('../lib/config');

describe('Rebuild DHIS2 resource table', function() {

  describe('.pollTask()', function() {
    let target = null;
    let targetCalled = false;
    let authPresent = false;

    let errorTarget = null;
    let errorTargetCalled = false;
    let orchestrations = [];
    let timesTargetCalled = 0;

    const out = {
      info(data) { return logger.info(data); },
      error(data) { return logger.error(data); },
      pushOrchestration(o) {
        logger.info(o);
        return orchestrations.push(o);
      }
    };

    before(function(done) {
      const options = {
        key: fs.readFileSync('test/resources/server-key.pem'),
        cert: fs.readFileSync('test/resources/server-cert.pem'),
        ca: fs.readFileSync('test/resources/client-cert.pem'),
        requestCert: true,
        rejectUnauthorized: true,
        secureProtocol: 'TLSv1_method'
      };

      target = https.createServer(options, function(req, res) {
        targetCalled = true;
        timesTargetCalled++;
        authPresent = (req.headers.authorization != null);
        res.writeHead(200, {'Content-Type': 'application/json'});
        if (timesTargetCalled > 3) {
          return res.end(JSON.stringify([{
            uid: "k6NsQt9wPY1",
            level: "INFO",
            category: "RESOURCETABLE_UPDATE",
            time: "2016-09-05T10:01:32.596",
            message: "Resource tables generated: 00:00:17.862",
            completed: true
          }
          , {
            uid: "t2tjPXDRZPg",
            level: "INFO",
            category: "RESOURCETABLE_UPDATE",
            time: "2016-09-05T10:01:32.596",
            message: "Generating resource tables",
            completed: false
          }
          ])
          );
        } else {
          return res.end(JSON.stringify([{
            uid: "t2tjPXDRZPg",
            level: "INFO",
            category: "RESOURCETABLE_UPDATE",
            time: "2016-09-05T10:01:32.596",
            message: "Generating resource tables",
            completed: false
          }
          ])
          );
        }
      });

      errorTarget = https.createServer(options, function(req, res) {
        errorTargetCalled = true;
        res.writeHead(500, {'Content-Type': 'text/plain'});
        return res.end('Error');
      });

      return target.listen(7130, function(err) {
        if (err) { return done(err); }
        return errorTarget.listen(7131, done);
      });
    });

    beforeEach(function(done) {
      targetCalled = false;
      errorTargetCalled = false;
      authPresent = false;
      orchestrations = [];
      timesTargetCalled = 0;

      return done();
    });

    after(done =>
      target.close(() =>
        errorTarget.close(() => done())
      )
    );

    it('should poll tasks until completed is returned', function(done) {
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:7130';
      return server.pollTask(out, 'resource rebuild', 'RESOURCETABLE_UPDATE', 20, 100, function(err) {
        should.not.exist(err);
        timesTargetCalled.should.be.exactly(4);
        authPresent.should.be.true();
        return done();
      });
    });

    it('should return an error if something goes wrong querying tasks', function(done) {
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:7131';
      return server.pollTask(out, 'resource rebuild', 'RESOURCETABLE_UPDATE', 20, 100, function(err) {
        should.exist(err);
        err.message.should.be.exactly('Incorrect status code received, 500');
        return done();
      });
    });

    it('should timeout', function(done) {
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:7130';
      return server.pollTask(out, 'resource rebuild', 'RESOURCETABLE_UPDATE', 80, 100, function(err) {
        should.exist(err);
        err.message.should.be.exactly('Polled tasks endpoint 2 time and still not completed, timing out...');
        return done();
      });
    });

    return it('should record an orchestration', function(done) {
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:7130';
      return server.pollTask(out, 'resource rebuild', 'RESOURCETABLE_UPDATE', 20, 100, function(err) {
        should.not.exist(err);
        orchestrations.length.should.be.exactly(1);
        orchestrations[0].name.should.be.exactly('Polled DHIS resource rebuild task 4 times');
        return done();
      });
    });
  });

  return describe('.rebuildDHIS2resourceTable()', function() {
    let target = null;
    let targetCalled = false;
    let authPresent = false;

    let errorTarget = null;
    let errorTargetCalled = false;
    let orchestrations = [];

    const out = {
      info(data) { return logger.info(data); },
      error(data) { return logger.error(data); },
      pushOrchestration(o) {
        logger.info(o);
        return orchestrations.push(o);
      }
    };

    before(function(done) {
      const options = {
        key: fs.readFileSync('test/resources/server-key.pem'),
        cert: fs.readFileSync('test/resources/server-cert.pem'),
        ca: fs.readFileSync('test/resources/client-cert.pem'),
        requestCert: true,
        rejectUnauthorized: true,
        secureProtocol: 'TLSv1_method'
      };

      target = https.createServer(options, function(req, res) {
        targetCalled = true;
        authPresent = (req.headers.authorization != null);
        res.writeHead(200, {'Content-Type': 'application/json'});
        return res.end();
      });
      errorTarget = https.createServer(options, function(req, res) {
        errorTargetCalled = true;
        res.writeHead(500, {'Content-Type': 'application/json'});
        return res.end();
      });

      return target.listen(8543, function(err) {
        if (err) { return done(err); }
        return errorTarget.listen(8544, done);
      });
    });

    let origPollTaskFunc = null;
    beforeEach(function(done) {
      const stub = sinon.stub();
      stub.callsArg(5);
      origPollTaskFunc = server.__get__('pollTask');
      server.__set__('pollTask', stub);
      targetCalled = false;
      errorTargetCalled = false;
      authPresent = false;
      orchestrations = [];

      return done();
    });

    afterEach(() => server.__set__('pollTask', origPollTaskFunc));

    after(done =>
      target.close(() =>
        errorTarget.close(() => done())
      )
    );

    it('should callback when a 200 response is received', function(done) {
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8543';
      return server.rebuildDHIS2resourceTable(out, function(err) {
        should.not.exist(err);
        targetCalled.should.be.true();
        authPresent.should.be.true();
        return done();
      });
    });

    it('should return an error when a NON 200 response is received', function(done) {
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8544';
      return server.rebuildDHIS2resourceTable(out, function(err) {
        should.exist(err);
        err.message.should.be.exactly('Resource tables refresh in DHIS2 failed, statusCode: 500');
        errorTargetCalled.should.be.true();
        return done();
      });
    });

    return it('should add an orchestration', function(done) {
      config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8543';
      return server.rebuildDHIS2resourceTable(out, function(err) {
        should.not.exist(err);
        orchestrations.length.should.be.exactly(1);
        orchestrations[0].name.should.be.exactly('DHIS2 resource table refresh');
        return done();
      });
    });
  });
});
