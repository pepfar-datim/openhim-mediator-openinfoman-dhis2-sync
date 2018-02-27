/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const https = require('https');
const fs = require('fs');
const server = require('../lib/server');
const logger = require('winston');
const should = require('should');
const config = require('../lib/config');

describe('Trigger test', function() {
  let target = null;
  let targetCalled = false;

  let errorTarget = null;
  let errorTargetCalled = false;

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
      res.writeHead(200, {'Content-Type': 'text/plain'});
      return res.end('OK');
    });
    errorTarget = https.createServer(options, function(req, res) {
      errorTargetCalled = true;
      res.writeHead(500, {'Content-Type': 'text/plain'});
      return res.end('Not OK');
    });

    return target.listen(7123, function(err) {
      if (err) { return done(err); }
      return errorTarget.listen(7124, done);
    });
  });


  beforeEach(function(done) {
    targetCalled = false;
    errorTargetCalled = false;
    return done();
  });

  after(done => target.close(() => errorTarget.close(() => done())));

  it('should send a GET request to a target server', function(done) {
    config.getConf()['sync-type']['both-trigger-url'] = 'https://localhost:7123/ILR/CSD/pollService/directory/DATIM-OU-TZ/update_cache';
    const out = {
      info(data) { return logger.info(data); },
      error(data) { return logger.error(data); },
      pushOrchestration(o) { return logger.info(o); }
    };
    return server.bothTrigger(out, function(err) {
      should.not.exist(err);
      targetCalled.should.be.exactly(true);
      return done();
    });
  });

  it('should return with err if target responds with a non-200 status code', function(done) {
    config.getConf()['sync-type']['both-trigger-url'] = 'https://localhost:7124/ILR/CSD/pollService/directory/DATIM-OU-TZ/update_cache';
    const out = {
      info(data) { return logger.info(data); },
      error(data) { return logger.info(`[this is expected] ${data}`); },
      pushOrchestration(o) { return logger.info(o); }
    };
    return server.bothTrigger(out, function(err) {
      should.exist(err);
      errorTargetCalled.should.be.exactly(true);
      return done();
    });
  });

  return it('should create an orchestration', function(done) {
    config.getConf()['sync-type']['both-trigger-url'] = 'https://localhost:7123/ILR/CSD/pollService/directory/DATIM-OU-TZ/update_cache';
    const orch = [];
    const out = {
      info(data) { return logger.info(data); },
      error(data) { return logger.error(data); },
      pushOrchestration(o) { return orch.push(o); }
    };
    return server.bothTrigger(out, function(err) {
      should.not.exist(err);
      orch.length.should.be.exactly(1);
      orch[0].name.should.be.exactly('Trigger');
      orch[0].request.path.should.be.exactly(config.getConf()['sync-type']['both-trigger-url']);
      orch[0].response.status.should.be.exactly(200);
      orch[0].response.body.should.be.exactly('OK');
      return done();
    });
  });
});
