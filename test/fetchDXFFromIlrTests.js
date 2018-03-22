/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const fs = require('fs');
const https = require('https');
const should = require('should');
const logger = require('winston');

const config = require('../lib/config');
const server = require('../lib/server');

describe('fetchDXFFromIlr()', function() {
  let target = null;
  let targetCalled = false;
  let authPresent = false;
  let fetchTsCallled = false;
  let updateTsCallled = false;

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
    config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://localhost:32001/dhis2";

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
      res.writeHead(200, {'Content-Type': 'text/plain'});
      return res.end('DXF');
    });
    errorTarget = https.createServer(options, function(req, res) {
      errorTargetCalled = true;
      res.writeHead(500, {'Content-Type': 'text/plain'});
      return res.end('Error');
    });
    const dhisMock = https.createServer(options, function(req, res) {
      if (req.method === 'GET') {
        fetchTsCallled = true;
        res.writeHead(200, {'Content-Type': 'application/json'});
        return res.end(JSON.stringify({value: new Date}));
      } else if (req.method === 'PUT') {
        updateTsCallled = true;
        res.writeHead(200, {'Content-Type': 'application/json'});
        return res.end();
      }
    });

    return target.listen(7125, function(err) {
      if (err) { return done(err); }
      return errorTarget.listen(7126, () => dhisMock.listen(32001, done));
    });
  });

  beforeEach(function(done) {
    targetCalled = false;
    errorTargetCalled = false;
    authPresent = false;
    orchestrations = [];

    return done();
  });

  it('should call ilr to fetch dxf', function(done) {
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7125/ILR/CSD';
    return server.fetchDXFFromIlr(out, function(err, dxf) {
      should.not.exist(err);
      dxf.toString().should.be.exactly('DXF');
      targetCalled.should.be.true();
      return done();
    });
  });

  it('should return an error when a non-200 response code is received', function(done) {
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7126/ILR/CSD';
    return server.fetchDXFFromIlr(out, function(err, dxf) {
      should.exist(err);
      err.message.should.be.exactly('Returned non-200 response code: Error');
      errorTargetCalled.should.be.true();
      return done();
    });
  });

  it('should return an error when a connection error occurs', function(done) {
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7127/ILR/CSD';
    return server.fetchDXFFromIlr(out, function(err, dxf) {
      should.exist(err);
      err.message.should.be.exactly('connect ECONNREFUSED 127.0.0.1:7127');
      targetCalled.should.be.false();
      errorTargetCalled.should.be.false();
      return done();
    });
  });

  it('should add an orchestration', function(done) {
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7125/ILR/CSD';
    return server.fetchDXFFromIlr(out, function(err, dxf) {
      should.not.exist(err);
      orchestrations.length.should.be.exactly(1);
      orchestrations[0].name.should.be.exactly('Extract DXF from ILR');
      return done();
    });
  });

  it('should add basic auth if ilr auth config present', function(done) {
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7125/ILR/CSD';
    config.getConf()['ilr-to-dhis']['ilr-user'] = 'user';
    config.getConf()['ilr-to-dhis']['ilr-pass'] = 'pass';
    return server.fetchDXFFromIlr(out, function(err, dxf) {
      should.not.exist(err);
      authPresent.should.be.true();
      return done();
    });
  });

  it('should fetch last updated ts', function(done) {
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7125/ILR/CSD';
    return server.fetchDXFFromIlr(out, function(err, dxf) {
      should.not.exist(err);
      fetchTsCallled.should.be.true();
      return done();
    });
  });

  return it('should update last updated ts', function(done) {
    config.getConf()['ilr-to-dhis']['ilr-url'] = 'https://localhost:7125/ILR/CSD';
    return server.fetchDXFFromIlr(out, function(err, dxf) {
      should.not.exist(err);
      updateTsCallled.should.be.true();
      return done();
    });
  });
});
