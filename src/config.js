let ops;
const fs = require('fs');
const path = require('path');
const stdio = require('stdio');

let conf = {};
let mediatorConf = {};

if (process.env.NODE_ENV !== 'test') {
  ops = stdio.getopt({
    conf: {
      key: 'c',
      args: 1,
      description: 'The backend configuration to use. See config/default.json for an example.'
    },
    mediatorConf: {
      key: 'm',
      args: 1,
      description: 'The mediator configuration to use. See config/mediator.json for an example.'
    }
  });
}


let confFile = null;


// Update the conf map with updated values
const updateConf = config => (() => {
  const result = [];
  for (let param in config) {
    result.push(conf[param] = config[param]);
  }
  return result;
})() ;


const load = function() {
  // conf
  let mediatorConfFile;
  if ((ops != null ? ops.conf : undefined) != null) {
    confFile = ops.conf;
  } else if (process.env.NODE_ENV === 'development') {
    confFile = path.resolve(`${global.appRoot}/config`, 'development.json');
  } else if (process.env.NODE_ENV === 'test') {
    confFile = path.resolve(`${global.appRoot}/config`, 'test.json');
  } else {
    confFile = path.resolve(`${global.appRoot}/config`, 'default.json');
  }

  conf = JSON.parse(fs.readFileSync(confFile));

  // mediator conf
  if ((ops != null ? ops.mediatorConf : undefined) != null) {
    mediatorConfFile = ops.mediatorConf;
  } else {
    mediatorConfFile = path.resolve(`${global.appRoot}/config`, 'mediator.json');
  }

  mediatorConf = JSON.parse(fs.readFileSync(mediatorConfFile));
  if (mediatorConf.config != null) {
    return updateConf(mediatorConf.config);
  }
};


exports.getConf = () => conf;
exports.getConfName = () => confFile;
exports.getMediatorConf = () => mediatorConf;
exports.load = load;
exports.updateConf = updateConf;
