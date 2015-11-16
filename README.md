[![OpenHIM Core](https://img.shields.io/badge/openhim--core-1.4%2B-brightgreen.svg)](http://openhim.readthedocs.org/en/latest/user-guide/versioning.html)

# openhim-mediator-openinfoman-dhis2-sync
An OpenHIM mediator for syncing DHIS2 organisations to OpenInfoMan. The mediator will register a polling channel with the OpenHIM Core that is by default scheduled to run daily at midnight.

Note that the [DHIS2 library](https://github.com/openhie/openinfoman-dhis) needs to be installed into OpenInfoMan.

## Usage
Checkout and build
```
git clone https://github.com/jembi/openhim-mediator-openinfoman-dhis2-sync.git
npm install
```
and to run the mediator
```
node lib/server.js -c myConfig.json
```

See `config/default.json` for a config example. This config only contains the basic mediator settings - all other settings can be configured on the OpenHIM Console via the Mediators page.

## See also
* http://openhim.org/
* https://github.com/openhie/openinfoman
* https://github.com/openhie/openinfoman-dhis
* https://www.dhis2.org/
