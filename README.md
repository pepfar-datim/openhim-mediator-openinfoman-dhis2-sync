[![OpenHIM Core](https://img.shields.io/badge/openhim--core-1.4%2B-brightgreen.svg)](http://openhim.readthedocs.org/en/latest/user-guide/versioning.html) [![Build Status](https://travis-ci.org/jembi/openhim-mediator-openinfoman-dhis2-sync.svg?branch=master)](https://travis-ci.org/jembi/openhim-mediator-openinfoman-dhis2-sync)

# openhim-mediator-openinfoman-dhis2-sync
An OpenHIM mediator for syncing DHIS2 organisations with the OpenInfoMan. The mediator will register a default polling channel with the OpenHIM Core that is by default scheduled to run daily at midnight.

Note that the [DHIS2 library](https://github.com/openhie/openinfoman-dhis) needs to be installed into OpenInfoMan.

## Usage
Checkout and build
```
git clone https://github.com/jembi/openhim-mediator-openinfoman-dhis2-sync.git
npm install
```

Replace the default certificate files in the `tls/` folder with those that you you want to use. Skipping this step would make your installation insecure, ensure you set these in production.

and to run the mediator
```
node start -- -c myConfig.json
```

See `config/default.json` for a config example. This config only contains the basic mediator settings - all other settings can be configured on the OpenHIM Console via the Mediators page.

## Development
To run in development mode
```
grunt serve
```

## See also
* http://openhim.org/
* https://github.com/openhie/openinfoman
* https://github.com/openhie/openinfoman-dhis
* https://www.dhis2.org/
