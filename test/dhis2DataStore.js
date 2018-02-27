/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const should = require('should');
const fs = require('fs');
const https = require('https');

const config = require('../lib/config');
const server = require('../lib/server');

describe('DHIS2 DataStore tests', function() {

  const options = {
    key: fs.readFileSync('test/resources/server-key.pem'),
    cert: fs.readFileSync('test/resources/server-cert.pem'),
    ca: fs.readFileSync('test/resources/client-cert.pem'),
    requestCert: true,
    rejectUnauthorized: true,
    secureProtocol: 'TLSv1_method'
  };

  describe('.setDHISDataStore()', function() {

    it('should store a new data value', function(done) {
      config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://localhost:32001/dhis2";

      var mockServer = https.createServer(options, (req, res) =>
        req.on('data', function(data) {
          req.method.should.be.exactly('POST');
          req.url.should.be.exactly('/dhis2/api/dataStore/testns/key1');
          data.toString().should.be.exactly('{"test":"obj"}');
          req.headers['content-type'].should.be.exactly('application/json');
          res.writeHead(201);
          res.end();
          return mockServer.close();
        })
      );

      return mockServer.listen(32001, () =>
        server.setDHISDataStore('testns', 'key1', {test: 'obj'}, false, function(err) {
          if (err) { return done(err); }
          return done();
        })
      );
    });

    it('should store an updated data value', function(done) {
      config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://localhost:32001/dhis2";

      var mockServer = https.createServer(options, (req, res) =>
        req.on('data', function(data) {
          req.method.should.be.exactly('PUT');
          req.url.should.be.exactly('/dhis2/api/dataStore/testns/key1');
          data.toString().should.be.exactly('{"test":"updated"}');
          req.headers['content-type'].should.be.exactly('application/json');
          res.writeHead(200);
          res.end();
          return mockServer.close();
        })
      );

      return mockServer.listen(32001, () =>
        server.setDHISDataStore('testns', 'key1', {test: 'updated'}, true, function(err) {
          if (err) { return done(err); }
          return done();
        })
      );
    });

    return it('should return an error if there is a connection problem', function(done) {
      config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://noexist.dhis.org/dhis2";
      return server.setDHISDataStore('testns', 'key1', {test: 'obj'}, false, function(err) {
        err.should.be.ok();
        return done();
      });
    });
  });

  describe('.getDHISDataStore()', function() {

    it('should fetch a data value', function(done) {
      config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://localhost:32001/dhis2";

      var mockServer = https.createServer(options, function(req, res) {
        req.method.should.be.exactly('GET');
        req.url.should.be.exactly('/dhis2/api/dataStore/testns/key2');
        res.writeHead(200);
        res.end(JSON.stringify({test: 'obj'}));
        return mockServer.close();
      });

      return mockServer.listen(32001, () =>
        server.getDHISDataStore('testns', 'key2', function(err, data) {
          if (err) { return done(err); }
          data.should.deepEqual({test: 'obj'});
          return done();
        })
      );
    });

    return it('should return an error if there is a connection problem', function(done) {
      config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://noexist.dhis.org/dhis2";
      return server.getDHISDataStore('testns', 'key2', function(err, data) {
        err.should.be.ok();
        return done();
      });
    });
  });

  return describe('.fetchLastImportTs()', function() {

    it('should fetch a timestamp if one already exists', function(done) {
      config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://localhost:32001/dhis2";

      var mockServer = https.createServer(options, function(req, res) {
        res.writeHead(200);
        res.end(JSON.stringify({value: JSON.stringify(new Date('2016-10-06'))}));
        return mockServer.close();
      });

      return mockServer.listen(32001, () =>
        server.fetchLastImportTs(function(err, ts) {
          if (err) { return done(err); }
          ts.should.be.exactly(JSON.stringify(new Date('2016-10-06')));
          return done();
        })
      );
    });

    return it('should create a timestamp if one don\'t already exist', function(done) {
      config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://localhost:32001/dhis2";

      const mockServer = https.createServer(options, function(req, res) {
        if (req.method === 'GET') {
          res.writeHead(404);
          return res.end(JSON.stringify({value: JSON.stringify({httpStatus: "Not Found", httpStatusCode: 404, status:"ERROR", message: "The key 'test' was not found in the namespace 'CSD-Loader-Last-Import'."})}));
        } else if (req.method === 'POST') {
          res.writeHead(201);
          return res.end();
        } else {
          res.writeHead(500);
          return res.end();
        }
      });

      return mockServer.listen(32001, () =>
        server.fetchLastImportTs(function(err, ts) {
          if (err) { return done(err); }
          ts.should.be.exactly(new Date(0).toISOString());
          mockServer.close();
          return done();
        })
      );
    });
  });
});
