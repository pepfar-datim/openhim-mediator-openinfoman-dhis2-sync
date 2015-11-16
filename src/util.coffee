logger = require 'winston'
config = require './config'

class BaseError extends Error
  constructor: (message) ->
    super @message = message
    Error.captureStackTrace @, arguments.callee

class BadRequestError extends BaseError
  name: 'BadRequestError'

class InternalServerError extends BaseError
  name: 'InternalServerError'

exports.BadRequestError = BadRequestError
exports.InternalServerError = InternalServerError

sendCoreErrorResponse = (res, status, err, orchestrations) ->
  res.set 'Content-Type', 'application/json+openhim'
  res.send {
    'x-mediator-urn': config.getMediatorConf().urn
    status: if status is 500 then 'Failed' else 'Completed'
    orchestrations: orchestrations
    response:
      status: status
      headers:
        'content-type': 'application/json'
      body: if err? then err else 'Internal Server Error'
      timestamp: new Date()
  }

exports.resErrHandler = resErrHandler = (res, orchestrations) -> (err) ->
  if err instanceof BadRequestError
    logger.info "Bad Request: #{err.message}"
    sendCoreErrorResponse res, 400, err.message, orchestrations

  else if err instanceof InternalServerError
    logger.error err
    sendCoreErrorResponse res, 500, err.message, orchestrations

  # else treat as internal server error
  else
    logger.error err
    sendCoreErrorResponse res, 500, err.message, orchestrations


exports.handleBadRequest = (res, message, orchestrations) -> resErrHandler(res, orchestrations)(new BadRequestError message)
exports.handleInternalServerError = (res, message, orchestrations) -> resErrHandler(res, orchestrations)(new InternalServerError message)
