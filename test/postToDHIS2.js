/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const https = require('https');
const fs = require('fs');
const url = require('url');

const server = require('../lib/server');
const logger = require('winston');
const should = require('should');
const config = require('../lib/config');

describe('Post DXF to DHIS2', function() {
  let pollingTargetCalled = false;
  let timesTargetCalled = 0;
  let orchestrations = [];

  before(function(done) {
    const options = {
      key: fs.readFileSync('test/resources/server-key.pem'),
      cert: fs.readFileSync('test/resources/server-cert.pem'),
      ca: fs.readFileSync('test/resources/client-cert.pem'),
      requestCert: true,
      rejectUnauthorized: true,
      secureProtocol: 'TLSv1_method'
    };

    const target = https.createServer(options, function(req, res) {
      res.writeHead(200, {'Content-Type': 'text/plain'});
      return res.end('OK');
    });
    const errorTarget = https.createServer(options, function(req, res) {
      res.writeHead(500, {'Content-Type': 'text/plain'});
      return res.end('Not OK');
    });
    const asyncTarget = https.createServer(options, function(req, res) {
      const urlObj = url.parse(req.url, true);
      if (urlObj.query.async) {
        res.writeHead(202, {'Content-Type': 'text/plain'});
        return res.end('OK');
      } else if (urlObj.pathname === '/api/system/tasks/METADATA_IMPORT') {
        pollingTargetCalled = true;
        timesTargetCalled++;
        res.writeHead(200, {'Content-Type': 'application/json'});
        if (timesTargetCalled > 3) {
          return res.end(JSON.stringify([{
            uid: "k6NsQt9w890",
            level: "INFO",
            category: "METADATA_IMPORT",
            time: "2016-09-05T10:01:32.596",
            message: "message",
            completed: true
          }
          , {
            uid: "t2tcsdDRZPg",
            level: "INFO",
            category: "METADATA_IMPORT",
            time: "2016-09-05T10:01:32.596",
            message: "message",
            completed: false
          }
          ])
          );
        } else {
          return res.end(JSON.stringify([{
            uid: "t2tjPXDR3dr",
            level: "INFO",
            category: "METADATA_IMPORT",
            time: "2016-09-05T10:01:32.596",
            message: "message",
            completed: false
          }
          ])
          );
        }

      } else {
        res.writeHead(500, {'Content-Type': 'text/plain'});
        return res.end('Not OK');
      }
    });

    const asyncReceiverTarget = https.createServer(options, function(req, res) {
      const adxAdapterID = req.url.split('/')[1];

      if (adxAdapterID) {
        res.writeHead(200, {'Content-Type': 'text/plain'});
        return res.end('Test Response');
      } else {
        res.writeHead(500);
        return res.end('Internal server error');
      }
    });

    return target.listen(8443, function(err) {
      if (err) { return done(err); }
      return errorTarget.listen(8124, function(err) {
        if (err) { return done(err); }
        return asyncTarget.listen(8125, function(err) {
          if (err) { return done(err); }
          return asyncReceiverTarget.listen(8126, function(err) {
            if (err) { return done(err); }
            return done();
          });
        });
      });
    });
  });

  beforeEach(function(done) {
    pollingTargetCalled = false;
    timesTargetCalled = 0;
    orchestrations = [];
    return done();
  });

  it('should NOT send request if DXF is empty', function(done) {
    const dxfData = undefined;
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8443';
    const out = {
      info(data) { return logger.info(data); },
      error(data) { return logger.error(data); },
      pushOrchestration(o) { return logger.info(o); },
      adxAdapterID: '1234'
    };
    return server.postToDhis(out, dxfData, function(err) {
      should.exist(err);
      err.message.should.be.exactly('No DXF body supplied');
      return done();
    });
  });

  it('should send a POST request with DXF body to a DHIS2 server', function(done) {
    const dxfData = fs.readFileSync('test/resources/metaData.xml');
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8443';
    const out = {
      info(data) { return logger.info(data); },
      error(data) { return logger.error(data); },
      pushOrchestration(o) { return logger.info(o); },
      adxAdapterID: '1234'
    };
    return server.postToDhis(out, dxfData, function(err) {
      should.not.exist(err);
      return done();
    });
  });

  it('should send async option if it is set', function(done) {
    const dxfData = fs.readFileSync('test/resources/metaData.xml');
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8125';
    config.getConf()['ilr-to-dhis']['dhis2-async'] = true;
    config.getConf()['ilr-to-dhis']['dhis2-poll-period'] = 20;
    config.getConf()['ilr-to-dhis']['dhis2-poll-timeout'] = 100;
    config.getConf()['ilr-to-dhis']['dhis2-async-receiver-url'] = 'https://localhost:8126';
    const out = {
      info(data) { return logger.info(data); },
      error(data) { return logger.error(data); },
      pushOrchestration(o) { return logger.info(o); },
      adxAdapterID: '1234'
    };
    return server.postToDhis(out, dxfData, function(err) {
      should.not.exist(err);
      return done();
    });
  });

  it('should callback when polling task has completed', function(done) {
    const dxfData = fs.readFileSync('test/resources/metaData.xml');
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8125';
    config.getConf()['ilr-to-dhis']['dhis2-async'] = true;
    config.getConf()['ilr-to-dhis']['dhis2-poll-period'] = 20;
    config.getConf()['ilr-to-dhis']['dhis2-poll-timeout'] = 100;
    config.getConf()['ilr-to-dhis']['dhis2-async-receiver-url'] = 'https://localhost:8126';
    const out = {
      info(data) { return logger.info(data); },
      error(data) { return logger.error(data); },
      pushOrchestration(o) { return logger.info(o); },
      adxAdapterID: '1234'
    };
    return server.postToDhis(out, dxfData, function(err) {
      should.not.exist(err);
      pollingTargetCalled.should.be.true();
      timesTargetCalled.should.be.exactly(4);
      return done();
    });
  });

  it('should return an error when the polling task reached its timeout limit', function(done) {
    const dxfData = fs.readFileSync('test/resources/metaData.xml');
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8125';
    config.getConf()['ilr-to-dhis']['dhis2-async'] = true;
    config.getConf()['ilr-to-dhis']['dhis2-poll-period'] = 50;
    config.getConf()['ilr-to-dhis']['dhis2-poll-timeout'] = 100;
    config.getConf()['ilr-to-dhis']['dhis2-async-receiver-url'] = 'https://localhost:8126';
    const out = {
      info(data) { return logger.info(data); },
      error(data) { return logger.error(data); },
      pushOrchestration(o) { return logger.info(o); },
      adxAdapterID: '1234'
    };
    return server.postToDhis(out, dxfData, function(err) {
      should.exist(err);
      err.message.should.be.exactly('Polled tasks endpoint 2 time and still not completed, timing out...');
      pollingTargetCalled.should.be.true();
      timesTargetCalled.should.be.exactly(2);
      return done();
    });
  });

  it('should add an orchestration for the polling task', function(done) {
    const dxfData = fs.readFileSync('test/resources/metaData.xml');
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8125';
    config.getConf()['ilr-to-dhis']['dhis2-async'] = true;
    config.getConf()['ilr-to-dhis']['dhis2-poll-period'] = 20;
    config.getConf()['ilr-to-dhis']['dhis2-poll-timeout'] = 100;
    config.getConf()['ilr-to-dhis']['dhis2-async-receiver-url'] = 'https://localhost:8126';
    const out = {
      info(data) { return logger.info(data); },
      error(data) { return logger.error(data); },
      pushOrchestration(o) {
        logger.info(o);
        return orchestrations.push(o);
      },
      adxAdapterID: '1234'
    };
    return server.postToDhis(out, dxfData, function(err) {
      should.not.exist(err);
      pollingTargetCalled.should.be.true();
      timesTargetCalled.should.be.exactly(4);
      orchestrations.length.should.be.exactly(3);
      orchestrations[0].name.should.be.exactly('DHIS2 Import');
      orchestrations[1].name.should.be.exactly('Polled DHIS sites import task 4 times');
      return done();
    });
  });

  it('should send dhis2 message to async receiver mediator when async job is complete', function(done) {
    const dxfData = fs.readFileSync('test/resources/metaData.xml');
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8125';
    config.getConf()['ilr-to-dhis']['dhis2-async'] = true;
    config.getConf()['ilr-to-dhis']['dhis2-async-receiver-url'] = 'https://localhost:8126';
    const out = {
      info(data) { return logger.info(data); },
      error(data) { return logger.error(data); },
      pushOrchestration(o) {
        logger.info(o);
        return orchestrations.push(o);
      },
      adxAdapterID: '1234'
    };
    return server.postToDhis(out, dxfData, function(err) {
      should.not.exist(err);
      orchestrations[2].name.should.be.exactly('Send to Async Receiver');
      orchestrations[2].response.body.should.be.exactly('Test Response');
      return done();
    });
  });

  return it('should return an error when there is no ADXAdapterId to use', function(done) {
    const dxfData = fs.readFileSync('test/resources/metaData.xml');
    config.getConf()['ilr-to-dhis']['dhis2-url'] = 'https://localhost:8125';
    config.getConf()['ilr-to-dhis']['dhis2-async'] = true;
    config.getConf()['ilr-to-dhis']['dhis2-async-receiver-url'] = 'https://localhost:8126';
    const out = {
      info(data) { return logger.info(data); },
      error(data) { return logger.error(data); },
      pushOrchestration(o) {
        logger.info(o);
        return orchestrations.push(o);
      }
    };
    return server.postToDhis(out, dxfData, function(err) {
      should.exist(err);
      err.status.should.be.exactly(400);
      err.message.should.be.exactly('No ADX Adapter ID present, unable to forward response to ADX Adapter');
      return done();
    });
  });
});
