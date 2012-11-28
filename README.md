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

    mkdir -p /data/db

On Magellan instances it is advisable to have this on the
`/mnt` partition for performance reasons:

    mkdir -p /mnt/db
    ln -s /mnt/db /data/db

Start the MongoDB service:

    mongod --dbpath /data/db 1>/var/log/mongod.log 2>&1 &

### Deployment ###

Run `make deploy`.


### Configure the Service ###

Copy the sample configuration file, modifying the location of the
MongoDB and altering the database used.

    cp config/sample.ini ~/config.ini
    vi config.ini
    export KB_DEPLOYMENT_CONFIG=$HOME/config.ini
    export KB_SERVICE_NAME=workspaceServices

### Start the Service ###

    cd /kb/deployment/services/workspaceService
    ./start_service

### Run Tests

    prove -r t
