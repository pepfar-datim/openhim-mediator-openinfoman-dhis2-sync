should = require 'should'
fs = require 'fs'
https = require 'https'

config = require '../lib/config'
server = require '../lib/server'

describe 'DHIS2 DataStore tests', ->

  options =
    key: fs.readFileSync 'test/resources/server-key.pem'
    cert: fs.readFileSync 'test/resources/server-cert.pem'
    ca: fs.readFileSync 'test/resources/client-cert.pem'
    requestCert: true
    rejectUnauthorized: true
    secureProtocol: 'TLSv1_method'

  describe '.setDHISDataStore()', ->

    it 'should store a new data value', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://localhost:32001/dhis2"

      mockServer = https.createServer options, (req, res) ->
        req.on 'data', (data) ->
          req.method.should.be.exactly 'POST'
          req.url.should.be.exactly '/dhis2/api/dataStore/testns/key1'
          data.toString().should.be.exactly '{"test":"obj"}'
          req.headers['content-type'].should.be.exactly 'application/json'
          res.writeHead(201)
          res.end()
          mockServer.close()

      mockServer.listen 32001, ->
        server.setDHISDataStore 'testns', 'key1', test: 'obj', false, (err) ->
          if err then return done err
          done()

    it 'should store an updated data value', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://localhost:32001/dhis2"

      mockServer = https.createServer options, (req, res) ->
        req.on 'data', (data) ->
          req.method.should.be.exactly 'PUT'
          req.url.should.be.exactly '/dhis2/api/dataStore/testns/key1'
          data.toString().should.be.exactly '{"test":"updated"}'
          req.headers['content-type'].should.be.exactly 'application/json'
          res.writeHead(200)
          res.end()
          mockServer.close()

      mockServer.listen 32001, ->
        server.setDHISDataStore 'testns', 'key1', test: 'updated', true, (err) ->
          if err then return done err
          done()

    it 'should return an error if there is a connection problem', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://noexist.dhis.org/dhis2"
      server.setDHISDataStore 'testns', 'key1', test: 'obj', false, (err) ->
        err.should.be.ok()
        done()

  describe '.getDHISDataStore()', ->

    it 'should fetch a data value', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://localhost:32001/dhis2"

      mockServer = https.createServer options, (req, res) ->
        req.method.should.be.exactly 'GET'
        req.url.should.be.exactly '/dhis2/api/dataStore/testns/key2'
        res.writeHead(200)
        res.end(JSON.stringify(test: 'obj'))
        mockServer.close()

      mockServer.listen 32001, ->
        server.getDHISDataStore 'testns', 'key2', (err, data) ->
          if err then return done err
          data.should.deepEqual test: 'obj'
          done()

    it 'should return an error if there is a connection problem', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://noexist.dhis.org/dhis2"
      server.getDHISDataStore 'testns', 'key2', (err, data) ->
        err.should.be.ok()
        done()

  describe '.fetchLastImportTs()', ->

    it 'should fetch a timestamp if one already exists', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://localhost:32001/dhis2"

      mockServer = https.createServer options, (req, res) ->
        res.writeHead(200)
        res.end(JSON.stringify(value: JSON.stringify(new Date('2016-10-06'))))
        mockServer.close()

      mockServer.listen 32001, ->
        server.fetchLastImportTs (err, ts) ->
          if err then return done err
          ts.should.be.exactly JSON.stringify(new Date('2016-10-06'))
          done()

    it 'should create a timestamp if one don\'t already exist', (done) ->
      config.getConf()['ilr-to-dhis']['dhis2-url'] = "https://localhost:32001/dhis2"

      mockServer = https.createServer options, (req, res) ->
        if req.method is 'GET'
          res.writeHead(404)
          res.end(JSON.stringify(value: JSON.stringify(httpStatus: "Not Found", httpStatusCode: 404, status:"ERROR", message: "The key 'test' was not found in the namespace 'CSD-Loader-Last-Import'.")))
        else if req.method is 'POST'
          res.writeHead(201)
          res.end()
        else
          res.writeHead(500)
          res.end()

      mockServer.listen 32001, ->
        server.fetchLastImportTs (err, ts) ->
          if err then return done err
          ts.should.be.exactly new Date(0).toISOString()
          mockServer.close()
          done()
