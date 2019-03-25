
require('./init');

const logger = require('winston');
const config = require('./config');
const url = require('url');

const express = require('express');
const bodyParser = require('body-parser');
const mediatorUtils = require('openhim-mediator-utils');
const util = require('./util');
const fs = require('fs');
const { spawn } = require('child_process');
const request = require('request');

const falseIfEmpty = function(s) { if ((s != null) && (s.trim().length>0)) { return s; } else { return false; } };
const nullIfFileNotFound = function(file) {
  try {
    return fs.readFileSync(file);
  } catch (err) {
    return null;
  }
};

const cfg = (clientMap) => `\
########################################################################
# Configuration Options for publish_to_ilr.sh
########################################################################

ILR_URL='${clientMap.dhis_to_ilr_ilr_url}'
ILR_USER=${falseIfEmpty(clientMap.dhis_to_ilr_ilr_user)}
ILR_PASS=${falseIfEmpty(clientMap.dhis_to_ilr_ilr_pass)}
ILR_DOC='${clientMap.dhis_to_ilr_ilr_doc}'
DHIS2_URL='${clientMap.dhis_to_ilr_dhis2_url}'
DHIS2_EXT_URL=$DHIS2_URL
DHIS2_USER="${falseIfEmpty(clientMap.dhis_to_ilr_dhis2_user)}"
DHIS2_PASS="${falseIfEmpty(clientMap.dhis_to_ilr_dhis2_pass)}"
DOUSERS=${clientMap.dhis_to_ilr_dousers}
DOSERVICES=${clientMap.dhis_to_ilr_dousers}
IGNORECERTS=${clientMap.dhis_to_ilr_ignorecerts}
LEVELS=${clientMap.dhis_to_ilr_levels}
GROUPCODES=${clientMap.dhis_to_ilr_groupcodes}\
` ;

const saveConfigToFile = function() {
 const mapping = config.getConf().mapping;
  mapping.forEach((map) => {
    const cfgStr = cfg(map);
    logger.debug(`Config to save:\n${cfgStr}`);
   const tmpCfg = `${appRoot}` + '/openhim-mediator-openinfoman-dhis2-sync-' + map.clientID + '.cfg';
     fs.writeFile(tmpCfg, cfgStr, function(err) {
      if (err) {
        logger.error(err);
        return process.exit(1);
      } else {
         logger.debug(`Saved config to ${tmpCfg}`);
      }
    });
});
}

const buildArgs = function(clientMap, tmpCfg) {
  const args = [];
  args.push(`${appRoot}/resources/publish_to_ilr.sh`);
  args.push(`-c ${tmpCfg}`);
  if (clientMap.dhis_to_ilr_reset) { args.push('-r'); }
  if (clientMap.dhis_to_ilr_publishfull) { args.push('-f'); }
  if (clientMap.dhis_to_ilr_debug) { args.push('-d'); }
  if (clientMap.dhis_to_ilr_empty) { args.push('-e'); }
  return args;
};

const dhisToIlr = function(out, clientMap, tmpCfg, callback) {
  out.info("Running dhis-to-ilr ...");
  const args = buildArgs(clientMap, tmpCfg);
  const beforeTimestamp = new Date();
  const script = spawn('bash', args);
  out.info(`Executing bash script ${args.join(' ')}`);

  let logs = "";
  script.stdout.on('data', out.info);
  script.stdout.on('data', data => logs += data.toString() + '\n');
  script.stderr.on('data', out.error);
  script.stderr.on('data', data => logs += data.toString() + '\n');

  return script.on('close', function(code) {
    out.info(`Script exited with status ${code}`);
    logs += `Script exited with status ${code}`;

    out.pushOrchestration({
      name: 'Execute Publish_to_ilr.sh',
      request: {
        timestamp: beforeTimestamp
      },
      response: {
        status: code,
        body: logs,
        timestamp: new Date()
      }
    });

    if (code === 0) {
      return callback();
    } else {
      return callback(new Error(`Script failed with code ${code}`));
    }
  });
};


const bothTrigger = function(clientMap, out, callback) {
  const options = {
    url: clientMap.sync_type_both_trigger_url,
    cert: nullIfFileNotFound('tls/cert.pem'),
    key: nullIfFileNotFound('tls/key.pem'),
    ca: nullIfFileNotFound('tls/ca.pem'),
    timeout: 0
  };

  out.info(`Triggering ${options.url} ...`);

  const beforeTimestamp = new Date();
  return request.get(options, function(err, res, body) {
    if (err) {
      out.error(`Trigger failed: ${err}`);
      return callback(new Error(`Trigger failed: ${err}`));
    }

    out.pushOrchestration({
      name: 'Trigger',
      request: {
        path: options.url,
        method: 'GET',
        timestamp: beforeTimestamp
      },
      response: {
        status: res.statusCode,
        headers: res.headers,
        body,
        timestamp: new Date()
      }
    });

    out.info(`Response: [${res.statusCode}] ${body}`);
    if (200 <= res.statusCode && res.statusCode <= 399) {
      return callback();
    } else {
      out.error(`Trigger failed with status code ${res.statusCode}`);
      return callback(new Error(`Trigger failed with status code ${res.statusCode}`));
    }
  });
};

const setDHISDataStore = function(namespace, data, update, clientMap, callback) {
  let query;
  if (clientMap.instanceID){
    query = {instanceid: clientMap.instanceID};
    }
  const options = {
    url: clientMap.ilr_to_dhis_ilr_dhis2_url + `/api/dataStore/${namespace}/${clientMap.ilr_to_dhis_ilr_doc}`,
    body: data,
    auth: {
      username: clientMap.ilr_to_dhis_ilr_dhis2_user,
      password: clientMap.ilr_to_dhis_ilr_dhis2_pass
    },
    cert: nullIfFileNotFound('tls/cert.pem'),
    key: nullIfFileNotFound('tls/key.pem'),
    ca: nullIfFileNotFound('tls/ca.pem'),
    qs: query,
    json: true
  };

  if (update) {
    options.method = 'PUT';
  } else {
    options.method = 'POST';
  }

  return request(options, function(err, res, body) {
    if (err) {
      return callback(err);
    } else if (((res.statusCode !== 201) && !update) || ((res.statusCode !== 200) && update)) {
      return callback(new Error(`Set value in datastore failed: [status ${res.statusCode}] ${JSON.stringify(body)}`));
    } else {
      return callback(null, body);
    }
  });
};


const getDHISDataStore = function(namespace, clientMap, callback) {
  let query;
  if (clientMap.instanceID){
    query = {instanceid: clientMap.instanceID};
    }
  const options = {
    url: clientMap.ilr_to_dhis_ilr_dhis2_url + `/api/dataStore/${namespace}/${clientMap.ilr_to_dhis_ilr_doc}`,
    auth: {
      username: clientMap.ilr_to_dhis_ilr_dhis2_user,
      password: clientMap.ilr_to_dhis_ilr_dhis2_pass
    },
    cert: nullIfFileNotFound('tls/cert.pem'),
    key: nullIfFileNotFound('tls/key.pem'),
    ca: nullIfFileNotFound('tls/ca.pem'),
    qs: query,
    json: true
  };

  return request.get(options, function(err, res, body) {
    if (err) {
      return callback(err);
    } else if (res.statusCode !== 200) {
      return callback(new Error(`Get value in datastore failed: [status ${res.statusCode}] ${JSON.stringify(body)}`));
    } else {
      return callback(null, body);
    }
  });
};

// Fetch last import timestamp and create if it doesn't exist
const fetchLastImportTs = function(clientMap, callback) {
  getDHISDataStore('CSD-Loader-Last-Import', clientMap, function(err, data) {
    if (err) {
      logger.info('Could not find last updated timestamp, creating one.');
      const date = new Date(0);
      return setDHISDataStore('CSD-Loader-Last-Import', {value: date}, false, clientMap, function(err) {
        if (err) { return callback(new Error(`Could not write last export to DHIS2 datastore ${err.stack}`)); }
        return callback(null, date.toISOString());
      });
    } else {
      return callback(null, data.value);
    }
  })
}
;

// Fetch DXF from ILR (openinfoman)
const fetchDXFFromIlr = function(clientMap, out, callback){
  fetchLastImportTs(clientMap, function(err, lastImport) {
    let ilrReq;
    if (err) { return callback(err); }

    const ilrOptions = {
      url: `${clientMap.ilr_to_dhis_ilr_url}/csr/${clientMap.ilr_to_dhis_ilr_doc}/careServicesRequest/urn:dhis.org:transform_to_dxf:${clientMap.ilr_to_dhis_ilr_dhis2_version}`,
      body: `<csd:requestParams xmlns:csd='urn:ihe:iti:csd:2013'>
  <processUsers value='0'/>
  <preserveUUIDs value='1'/>
                <zip value='0'/>
                <onlyDirectChildren value='0'/>
                <csd:record updated='${lastImport}'/>
</csd:requestParams>`,
      headers: {
        'Content-Type': 'text/xml'
},
      cert: nullIfFileNotFound('tls/cert.pem'),
      key: nullIfFileNotFound('tls/key.pem'),
      ca: nullIfFileNotFound('tls/ca.pem'),
      timeout: 0
};

    if (clientMap.ilr_to_dhis_ilr_dhis2_user && clientMap.ilr_to_dhis_ilr_dhis2_pass) {
      ilrOptions.auth = {
        user: clientMap.ilr_to_dhis_ilr_dhis2_user,
        pass: clientMap.ilr_to_dhis_ilr_dhis2_pass
      };
    }

    out.info(`Fetching DXF from ILR ${ilrOptions.url} ...`);
    out.info(`with body: ${ilrOptions.body}`);
    const beforeTimestamp = new Date();
    return ilrReq = request.post(ilrOptions, function(err, res, body) {
      if (err) {
        out.error(`POST to ILR failed: ${err.stack}`);
        return callback(err);
      }
      if (res.statusCode !== 200) {
        out.error(`ILR stored query failed with response code ${res.statusCode} and body: ${body}`);
        return callback(new Error(`Returned non-200 response code: ${body}`));
      }

      out.pushOrchestration({
        name: 'Extract DXF from ILR',
        request: {
          path: ilrOptions.url,
          method: 'POST',
          body: ilrOptions.body,
          timestamp: beforeTimestamp
        },
        response: {
          status: res.statusCode,
          headers: res.headers,
          body,
          timestamp: new Date()
        }
      });

      setDHISDataStore('CSD-Loader-Last-Import', {value: beforeTimestamp}, true, 
     clientMap, function(err) {
        if (err) { return logger.error(`Failed to set last import date in DHIS2 datastore ${err}`); }
      });
      return callback(null, body);
    });
  })
};

const sendAsyncDhisImportResponseToReceiver = function(out, res, clientMap, callback) {
  const options = {
    url: clientMap.ilr_to_dhis_ilr_dhis2_async_receiver_url,
    body: res.body,
    headers: {
      'content-type': res.headers['content-type']
    },
    method: 'PUT',
    cert: nullIfFileNotFound('tls/cert.pem'),
    key: nullIfFileNotFound('tls/key.pem'),
    ca: nullIfFileNotFound('tls/ca.pem')
  };
  if (out.adxAdapterID) {
    options.url += `/${out.adxAdapterID}`;
  } else {
    out.error('No ADX Adapter ID present, unable to forward response to ADX Adapter');
    const err = new Error('No ADX Adapter ID present, unable to forward response to ADX Adapter');
    err.status = 400;
    return callback(err);
  }

  const beforeTimestamp = new Date();
  return request.put(options, function(err, res, body) {
    if (err) {
      out.error(`Send to Async Receiver failed: ${err}`);
      return callback(new Error(`Send to Async Receiver failed: ${err}`));
    }

    if (!(200 <= res.statusCode && res.statusCode <= 399)) {
      out.error(`Send to Async Receiver responded with non 2/3xx statusCode ${res.statusCode}`);
      return callback(new Error(`Send to Async Receiver responded with non 2/3xx statusCode ${res.statusCode}`));
    }

    out.pushOrchestration({
      name: 'Send to Async Receiver',
      request: {
        path: options.url,
        method: options.method,
        body: options.body,
        timestamp: beforeTimestamp
      },
      response: {
        status: res.statusCode,
        headers: res.headers,
        body,
        timestamp: new Date()
      }
    });

    return callback();
  });
};

// post DXF data to DHIS2 api
const postToDhis = function(out, dxfData, clientMap, callback) {
  if (!dxfData) {
    out.info("No DXF body supplied");
    return callback(new Error("No DXF body supplied"));
  }
  let query = "";
  if (clientMap.instanceID){
    query = "&instanceid=" + clientMap.instanceID;
    }
  const options = {
    url: clientMap.ilr_to_dhis_ilr_dhis2_url + '/api/metadata?preheatCache=false' + query,
    body: dxfData,
    method: 'POST',
    auth: {
      username: clientMap.ilr_to_dhis_ilr_dhis2_user,
      password: clientMap.ilr_to_dhis_ilr_dhis2_pass
    },
    cert: nullIfFileNotFound('tls/cert.pem'),
    key: nullIfFileNotFound('tls/key.pem'),
    ca: nullIfFileNotFound('tls/ca.pem'),
    timeout: 0,
    headers: { 'content-type': 'application/xml', 'accept': 'application/json' }
  };
  if (clientMap.ilr_to_dhis_ilr_dhis2_async) {
    options.qs = {async: true};
  }

  const beforeTimestamp = new Date();
  return request.post(options, function(err, res, body) {
    const resBody = JSON.parse(body);
    const processId = resBody['response']['id'];

    if (err) {
      out.error(`Post to DHIS2 failed: ${err}`);
      return callback(new Error(`Post to DHIS2 failed: ${err}`));
    }

    out.pushOrchestration({
      name: 'DHIS2 Import',
      request: {
        path: options.url,
        method: options.method,
        body: options.body,
        timestamp: beforeTimestamp
      },
      response: {
        status: res.statusCode,
        headers: res.headers,
        body,
        timestamp: new Date()
      }
    });

    out.info(`Response: [${res.statusCode}] ${body}`);

    if (200 <= res.statusCode && res.statusCode <= 399) {
      if (clientMap.ilr_to_dhis_ilr_dhis2_async) {
        const period = clientMap.ilr_to_dhis_ilr_dhis2_poll_period;
        const timeout = clientMap.ilr_to_dhis_ilr_dhis2_poll_timeout;
        // send out async polling request
        return pollTask(out, 'sites import', 'METADATA_IMPORT/' + processId, period, timeout, clientMap, function(err) {
          if (err) { return callback(err); }

          return sendAsyncDhisImportResponseToReceiver(out, res, clientMap, callback);
        });
      } else {
        return callback();
      }
    } else {
      out.error(`Post to DHIS2 failed with status code ${res.statusCode}`);
      return callback(new Error(`Post to DHIS2 failed with status code ${res.statusCode}`));
    }
  });
};

// Poll DHIS2 task, period and timeout are in ms
var pollTask = function(out, orchName, task, period, timeout, clientMap, callback) {
  let interval;
  let pollNum = 0;
  const beforeTimestamp = new Date();
  let query;
  if (clientMap.instanceID){
    query = {instanceid: clientMap.instanceID};
    }
  return interval = setInterval(function() {
    const options = {
      url: clientMap.ilr_to_dhis_ilr_dhis2_url + '/api/system/tasks/' + task,
      auth: {
        username: clientMap.ilr_to_dhis_ilr_dhis2_user,
        password: clientMap.ilr_to_dhis_ilr_dhis2_pass
      },
      cert: nullIfFileNotFound('tls/cert.pem'),
      key: nullIfFileNotFound('tls/key.pem'),
      ca: nullIfFileNotFound('tls/ca.pem'),
      qs: query,
      json: true
    };
    return request.get(options, function(err, res, tasks) {
      if (err) {
        clearInterval(interval);
        return callback(err);
      }
      if (res.statusCode !== 200) {
        clearInterval(interval);
        return callback(new Error(`Incorrect status code received, ${res.statusCode}`));
      }
      pollNum++;
      if (((tasks[0] != null ? tasks[0].completed : undefined) == null)) {
        return callback(new Error('No tasks returned or bad tasks response received'));
      }
      if ((tasks[0] != null ? tasks[0].completed : undefined) === true) {
        clearInterval(interval);

        out.pushOrchestration({
          name: `Polled DHIS ${orchName} task ${pollNum} times`,
          request: {
            path: options.url,
            method: options.method,
            body: options.body,
            timestamp: beforeTimestamp
          },
          response: {
            status: res.statusCode,
            headers: res.headers,
            body: JSON.stringify(tasks),
            timestamp: new Date()
          }
        });
        return callback();
      }
      if ((pollNum * period) >= timeout) {
        clearInterval(interval);
        return callback(new Error(`Polled tasks endpoint ${pollNum} time and still not completed, timing out...`));
      }
    });
  }
  , period);
};

// initiate a resource table rebuild task on DHIS and wait for the task to complete
const rebuildDHIS2resourceTable = function(out, clientMap, callback) {
  let query;
  if (clientMap.instanceID){
    query = {instanceid: clientMap.instanceID};
    }
  const options = {
    url: clientMap.ilr_to_dhis_ilr_dhis2_url + '/api/resourceTables',
    method: 'POST',
    auth: {
      username: clientMap.ilr_to_dhis_ilr_dhis2_user,
      password: clientMap.ilr_to_dhis_ilr_dhis2_pass
    },
    cert: nullIfFileNotFound('tls/cert.pem'),
    key: nullIfFileNotFound('tls/key.pem'),
    ca: nullIfFileNotFound('tls/ca.pem'),
    qs: query
  };

  const beforeTimestamp = new Date();
  return request.post(options, function(err, res, body) {
    if (err) {
      out.error(`Resource tables refresh in DHIS2 failed: ${err}`);
      return callback(err);
    }

    out.pushOrchestration({
      name: 'DHIS2 resource table refresh',
      request: {
        path: options.url,
        method: options.method,
        body: options.body,
        timestamp: beforeTimestamp
      },
      response: {
        status: res.statusCode,
        headers: res.headers,
        body,
        timestamp: new Date()
      }
    });

    out.info(`Response: [${res.statusCode}] ${body}`);
    if (res.statusCode === 200) {
      const period = clientMap.ilr_to_dhis_ilr_dhis2_poll_period;
      const timeout = clientMap.ilr_to_dhis_ilr_dhis2_poll_timeout;
      return pollTask(out, 'resource rebuild', 'RESOURCETABLE_UPDATE', period, timeout, clientMap, function(err) {
        if (err) { return callback(err); }

        return callback();
      });
    } else {
      out.error(`Resource tables refresh in DHIS2 failed, statusCode: ${res.statusCode}`);
      return callback(new Error(`Resource tables refresh in DHIS2 failed, statusCode: ${res.statusCode}`));
    }
  });
};


const ilrToDhis = (out, clientMap, callback) =>
  fetchDXFFromIlr(clientMap, out, function(err, dxf) {
    if (err) { return callback(err); }
    return postToDhis(out, dxf, clientMap, function(err) {
      if (!err) {
        if (clientMap.ilr_to_dhis_ilr_dhis2_rebuild_resources) {
          return rebuildDHIS2resourceTable(out, clientMap, function(err) {
            if (err) { return callback(err); }
            return callback();
          });
        } else {
          return callback();
        }
      } else {
        return callback(err);
      }
    });
  })
;


const handler = function(req, res) {
  const openhimTransactionID = req.headers['x-openhim-transactionid'];

  const clientId = req.headers['x-openhim-clientid'];
let clientTmpCfg = `${appRoot}` + '/openhim-mediator-openinfoman-dhis2-sync-' + clientId + '.cfg';
const mapping = config.getConf().mapping;
let clientMap = {};
if (mapping) {
  mapping.forEach((map) => {
    if (map.clientID === clientId) {
      clientMap = map
    }
  })
}


  const { query } = url.parse(req.url, true);
  let adxAdapterID = null;
  if (query.adxAdapterID) {
    ({ adxAdapterID } = query);
    delete query.adxAdapterID;
  }

  const _out = function() {
    let body = "";
    const orchestrations = [];

    const append = function(level, data) {
      logger[level](`[${openhimTransactionID}] ${data}`);
      if (data.slice(-1) !== '\n') {
        return body = `${body}${data}\n`;
      } else {
        return body = `${body}${data}`;
      }
    };

    return {
      body() { return body; },
      info(data) { return append('info', data); },
      error(data) { return append('error', data); },
      pushOrchestration(o) { return orchestrations.push(o); },
      orchestrations() { return orchestrations; },
      adxAdapterID
    };
  };
  const out = _out();

  out.info(`Running sync with mode ${clientMap.sync_type_mode} ...`);

  const end = function(err) {
    if (err && !err.status) {
      err.status = 500;
    }

    res.set('Content-Type', 'application/json+openhim');
    return res.send({
      'x-mediator-urn': config.getMediatorConf().urn,
      status: err ? 'Failed' : 'Successful',
      response: {
        status: err ? err.status : 200,
        headers: {
          'content-type': 'application/json'
        },
        body: err ? err.message + '\n\n' + out.body() : out.body(),
        timestamp: new Date()
      },
      orchestrations: out.orchestrations()
    });
  };

  if (clientMap.sync_type_mode === 'DHIS2 to ILR') {
    return dhisToIlr(out, clientMap, clientTmpCfg, end);
  } else if (clientMap.sync_type_mode === 'ILR to DHIS2') {
    return ilrToDhis(out, clientMap ,end);
  } else {
    return dhisToIlr(out, clientMap, clientTmpCfg, function(err) {
      if (err) { return end(err); }

      const next = () => ilrToDhis(out, clientMap, end);
      if (clientMap.sync_type_both_trigger_enabled) {
        return bothTrigger(clientMap, out, function(err) {
          if (err) { return end(err); }
          return next();
        });
      } else {
        return next();
      }
    });
  }
};


// Setup express
const app = express();

app.use(bodyParser.json());

app.get('/trigger', handler);

let server = null;
exports.start = function(callback) {
  server = app.listen(config.getConf().server.port, config.getConf().server.hostname, function() {
    logger.info(`[${process.env.NODE_ENV}] ${config.getMediatorConf().name} running on port ${server.address().address}:${server.address().port}`);
    if (callback) { return callback(null, server); }
  });
  server.on('error', function(err) {
    if (callback) { return callback(err); }
  });
  server.timeout = 0;

  if (process.env.NODE_ENV !== 'test') {
    logger.info('Attempting to register mediator with core ...');
    config.getConf().openhim.api.urn = config.getMediatorConf().urn;

    return mediatorUtils.registerMediator(config.getConf().openhim.api, config.getMediatorConf(), function(err) {
      if (err) {
        logger.error(err);
        process.exit(1);
      }
      logger.info('Mediator has been successfully registered');

      const configEmitter = mediatorUtils.activateHeartbeat(config.getConf().openhim.api);

      configEmitter.on('config', function(newConfig) {
        logger.info('Received updated config from core');
        config.updateConf(newConfig);
        return saveConfigToFile();
      });

      configEmitter.on('error', err => logger.error(err));

      return mediatorUtils.fetchConfig(config.getConf().openhim.api, function(err, newConfig) {
        if (err) { return logger.error(err); }
        logger.info('Received initial config from core');
        config.updateConf(newConfig);
        return saveConfigToFile();
      });

    });
  }
};


exports.stop = callback =>
  server.close(function() {
    if (callback) { return callback(); }
  })
;

if (!module.parent) { exports.start(); }

if (process.env.NODE_ENV === 'test') {
  exports.app = app;
  exports.bothTrigger = bothTrigger;
  exports.postToDhis = postToDhis;
  exports.fetchDXFFromIlr = fetchDXFFromIlr;
  exports.pollTask = pollTask;
  exports.rebuildDHIS2resourceTable = rebuildDHIS2resourceTable;
  exports.setDHISDataStore = setDHISDataStore;
  exports.getDHISDataStore = getDHISDataStore;
  exports.fetchLastImportTs = fetchLastImportTs;
}

