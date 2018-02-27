/*
 * decaffeinate suggestions:
 * DS001: Remove Babel/TypeScript constructor workaround
 * DS102: Remove unnecessary code created because of implicit returns
 * DS206: Consider reworking classes to avoid initClass
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
let resErrHandler;
const logger = require('winston');
const config = require('./config');

class BaseError extends Error {
  constructor(message) {
    {
      // Hack: trick Babel/TypeScript into allowing this before super.
      if (false) { super(); }
      let thisFn = (() => { this; }).toString();
      let thisName = thisFn.slice(thisFn.indexOf('{') + 1, thisFn.indexOf(';')).trim();
      eval(`${thisName} = this;`);
    }
    super(this.message = message);
    Error.captureStackTrace(this, arguments.callee);
  }
}

class BadRequestError extends BaseError {
  static initClass() {
    this.prototype.name = 'BadRequestError';
  }
}
BadRequestError.initClass();

class InternalServerError extends BaseError {
  static initClass() {
    this.prototype.name = 'InternalServerError';
  }
}
InternalServerError.initClass();

exports.BadRequestError = BadRequestError;
exports.InternalServerError = InternalServerError;

const sendCoreErrorResponse = function(res, status, err, orchestrations) {
  res.set('Content-Type', 'application/json+openhim');
  return res.send({
    'x-mediator-urn': config.getMediatorConf().urn,
    status: status === 500 ? 'Failed' : 'Completed',
    orchestrations,
    response: {
      status,
      headers: {
        'content-type': 'application/json'
      },
      body: (err != null) ? err : 'Internal Server Error',
      timestamp: new Date()
    }
  });
};

exports.resErrHandler = (resErrHandler = (res, orchestrations) => function(err) {
  if (err instanceof BadRequestError) {
    logger.info(`Bad Request: ${err.message}`);
    return sendCoreErrorResponse(res, 400, err.message, orchestrations);

  } else if (err instanceof InternalServerError) {
    logger.error(err);
    return sendCoreErrorResponse(res, 500, err.message, orchestrations);

  // else treat as internal server error
  } else {
    logger.error(err);
    return sendCoreErrorResponse(res, 500, err.message, orchestrations);
  }
} );


exports.handleBadRequest = (res, message, orchestrations) => resErrHandler(res, orchestrations)(new BadRequestError(message));
exports.handleInternalServerError = (res, message, orchestrations) => resErrHandler(res, orchestrations)(new InternalServerError(message));
