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

NOTE: MongoDB must be running on localhost for server-tests,
unless configs/test.cfg is edited to point to another host.

### Setup MongoDB ###

Create the `/data` directory if it doesn't already exist.

    # DON'T DO THIS ON MAGELLAN INSTANCES
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
If the mongod server requires authentication, add the user and password to the
mongodb-user and mongodb-pwd params.

### Start the Service ###

    cd /kb/deployment/services/workspaceService
    ./start_service

NOTE: service writes stderr to /kb/deployment/services/workspaceService/error.log

NOTE: If the file /kb/deployment/deployment.cfg is not created, the workspace
service will not be able to run. error.log will show the following message:

Error while loading /kb/deployment/lib/workspaceService.psgi: $ENV{KB_DEPLOYMENT_CONFIG} points 
to an unreadable file: /kb/deployment/deployment.cfg at /kb/deployment/lib/Bio/KBase/Auth.pm line 18.

You will need to stop the workspace service (./stop_service), create the deployment.cfg, e.g.,:

cp /kb/dev_container/modules/workspace_service/deploy.cfg /kb/deployment/deployment.cfg

then restart the service (./start_service).

### Run Tests

server-tests: hardcoded to read /kb/deployment/deployment/cfg and instantiate a Server Impl
client-tests: hardcoded to run against http://localhost:7058
script-tests: hardcoded to run against http://localhost:7058
