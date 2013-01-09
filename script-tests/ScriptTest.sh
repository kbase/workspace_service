#!/bin/bash

kbws-list -e
kbws-url "http://localhost:7058"
kbws-login kbasetest -p "@Suite525"
kbws-whoami
kbws-createws scriptTestWorkspace n -e
kbws-workspace scriptTestWorkspace
kbws-setglobalperm r -e
kbws-meta -e
kbws-setglobalperm n -e
kbws-setuserperm public w -e
kbws-perm -e
kbws-logout
kbws-login kbasetest -p "@Suite525"
kbws-addtype temptype -e
kbws-types -e
kbws-load temptype testobject "test object string data" -s -e
kbws-copy temptype testobject testobjectcopy -e
kbws-move temptype testobjectcopy testobjectcopymoved -e
kbws-listobj temptype -e
kbws-exists temptype testobject -e
kbws-clone scriptTestClone n -e
kbws-getmeta temptype testobject -w scriptTestClone -e
kbws-get temptype testobject -w scriptTestClone -e
kbws-load temptype testobject "test object string data version 2" -s -e
kbws-get temptype testobject -e
kbws-revert temptype testobject -i 0 -e
kbws-get temptype testobject -e
kbws-history temptype testobject -e
kbws-delete temptype testobject -e
kbws-removetype temptype -e
kbws-workspace none
kbws-deletews scriptTestWorkspace -e
kbws-deletews scriptTestClone -e
