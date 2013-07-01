#!/usr/bin/env python
'''
Created on Jul 1, 2013

@author: gaprice@lbl.gov
'''
import pymongo
import sys
import re
from collections import defaultdict

HOST = 'localhost:27017'
DB = 'workspace_service'
USERS = 'workspaceUsers'
WS = 'workspaces'
WSO = 'workspaceObjects'
TYPES = 'typeObjects'

PUBLIC = 'public'
ID = 'id'
OWNER = 'owner'

PER_NONE = 'n'
PER_READ = 'r'
PER_WRITE = 'w'
PER_ADMIN = 'a'

TYPE_BAD_CHARS = re.compile('[^\w]')

user = None
pwd = None
if len(sys.argv) > 2:
    user = sys.argv[1]
    pwd = sys.argv[2]

c = pymongo.Connection(HOST)
wsdb = c[DB]
if user and pwd:
    wsdb.authenticate(user, pwd)

del user, pwd

pubws = {w[ID] for w in wsdb[WS].find({OWNER: PUBLIC})}

publicuser = wsdb[USERS].find({ID: PUBLIC}).next()

for pws in publicuser[WS].keys():
    if pws not in pubws:
        del publicuser[WS][pws]
    else:
        publicuser[WS][pws] = PER_READ

wsdb[USERS].save(publicuser)

del publicuser

print 'Removing permissions for public workspaces:'
for u in wsdb[USERS].find({ID: {'$ne': PUBLIC}}):
    p = False
    workspaces = u[WS].keys()
    for ws in workspaces:
        if ws in pubws:
            if not p:
                print 'User {} workspaces:'.format(u[ID])
                p = True
            print '\t{}'.format(ws)
            del u[WS][ws]
    wsdb[USERS].save(u)

types = [t[ID] for t in wsdb[TYPES].find()]

newtype = {}
nts = set()
for t in types:
    tnew = TYPE_BAD_CHARS.sub('_', t)
    if tnew in nts:
        raise ValueError("Just subbing _ for bad chars in types isn't "
                         "enough - need more complex code")
    newtype[t] = tnew
    nts.add(tnew)
del nts
del types

for t in wsdb[TYPES].find():
    t[ID] = newtype[t[ID]]
    wsdb[TYPES].save(t)

ws_obj_ids = defaultdict(dict)

#for ws in wsdb[WS].find():
#    if ws in pubws:
#        ws['defaultPermissions'] = PER_READ



