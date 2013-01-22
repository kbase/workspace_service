Workspace Services
==================

This is the repository for managing the workspace
service. The workspace represents a scientific team's
data as a collection of objects with a standard set of
permissions over all objects within a workspace. The
workspace also implements revert and restore functionality
on each object in a workspace.

Development / Testing Deployment
--------------------------------

This module requires a working MongoDB instance.
By default this is assumed to run on `localhost`.

### Setup MongoDB ###

Create the `/data` directory if it doesn't already exist.

    # don't do this on Magellan instances
    mkdir -p /data/db 

On Magellan instances it is advisable to have this on the
`/mnt` partition for performance reasons:

    mkdir /data
    mkdir -p /mnt/db
    ln -s /mnt/db /data/db

Start the MongoDB service:

    mongod --dbpath /data/db 1>/var/log/mongod.log 2>&1 &

### Deployment ###

Run `make deploy` to deploy the service and the client.
Run 'make deploy-client' to deploy just the client.


### Configure the Service ###

The contents of deploy.cfg should be copied into /kb/deployment/deployment.cfg.
Otherwise the service will default to running against mongodb on localhost.

### Start the Service ###

    cd /kb/deployment/services/workspaceService
    ./start_service

NOTE: service writes stderr to ./error.log

### Run Tests

server-tests: hardcoded to read /kb/deployment/deployment/cfg and instantiate a Server Impl
client-tests: hardcoded to run against http://localhost:7058
script-tests: hardcoded to run against http://localhost:7058
