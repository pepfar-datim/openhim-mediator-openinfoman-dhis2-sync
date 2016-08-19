fs = require 'fs'
path = require 'path'
stdio = require 'stdio'

conf = {}
mediatorConf = {}

if process.env.NODE_ENV isnt 'test'
  ops = stdio.getopt
    conf:
      key: 'c'
      args: 1
      description: 'The backend configuration to use. See config/default.json for an example.'
    mediatorConf:
      key: 'm'
      args: 1
      description: 'The mediator configuration to use. See config/mediator.json for an example.'


confFile = null


# Update the conf map with updated values
updateConf = (config) -> conf[param] = config[param] for param of config


load = () ->
  # conf
  if ops?.conf?
    confFile = ops.conf
  else if process.env.NODE_ENV is 'development'
    confFile = path.resolve "#{global.appRoot}/config", 'development.json'
  else if process.env.NODE_ENV is 'test'
    confFile = path.resolve "#{global.appRoot}/config", 'test.json'
  else
    confFile = path.resolve "#{global.appRoot}/config", 'default.json'

  conf = JSON.parse fs.readFileSync confFile

  # mediator conf
  if ops?.mediatorConf?
    mediatorConfFile = ops.mediatorConf
  else
    mediatorConfFile = path.resolve "#{global.appRoot}/config", 'mediator.json'

  mediatorConf = JSON.parse fs.readFileSync mediatorConfFile
  if mediatorConf.config?
    updateConf mediatorConf.config


exports.getConf = -> conf
exports.getConfName = -> confFile
exports.getMediatorConf = -> mediatorConf
exports.load = load
exports.updateConf = updateConf
