#!/usr/bin/env python
'''
Created on Jul 1, 2013

@author: gaprice@lbl.gov
'''
import pymongo
import sys
import re
from collections import defaultdict

DRY_RUN = True
SUPPRESS_NO_WORKSPACE_ID_CHANGE_OUTPUT = True

HOST = 'localhost:27017'
DB = 'workspace_service'
USERS = 'workspaceUsers'
WS = 'workspaces'
WSO = 'workspaceObjects'
TYPES = 'typeObjects'

PUBLIC = 'public'
ID = 'id'
OWNER = 'owner'
TYPE = 'type'
OBJS = 'objects'

PER_DEF = 'defaultPermissions'
PER_NONE = 'n'
PER_READ = 'r'
PER_WRITE = 'w'
PER_ADMIN = 'a'
PER_READABLE = set([PER_READ, PER_WRITE, PER_ADMIN])

TYPE_BAD_CHARS = re.compile('[^\w]')
OBJ_BAD_CHARS = re.compile('[^\w\|.-]')

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

# find all the public workspace names
pubws = {w[ID] for w in wsdb[WS].find({OWNER: PUBLIC})}

# get the public user and set all perms to read only
publicuser = wsdb[USERS].find({ID: PUBLIC}).next()

for pws in publicuser[WS].keys():
    if pws not in pubws:
        del publicuser[WS][pws]
    else:
        publicuser[WS][pws] = PER_READ

if not DRY_RUN:
    wsdb[USERS].save(publicuser)
del publicuser

# remove all permissions to public workspaces from all users except public
print 'Removing permissions for public workspaces...'
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
    if not DRY_RUN:
        wsdb[USERS].save(u)
print '...done.'

# fix type names
types = set([t[ID] for t in wsdb[TYPES].find()])
types |= set([t[TYPE] for t in wsdb[WSO].find({}, {TYPE: True})])

newtype = {}
nts = set()
for t in types:
    tnew = TYPE_BAD_CHARS.sub('_', t)
    if tnew in nts:
        raise ValueError("Just subbing _ for bad chars in types isn't "
                         "enough - need more complex code")
    newtype[t] = tnew
    if t != tnew:
        print 'Renaming type {}->{}'.format(t, tnew)
    nts.add(tnew)
del nts
del types

for t in wsdb[TYPES].find():
    t[ID] = newtype[t[ID]]
    if not DRY_RUN:
        wsdb[TYPES].save(t)

# run through workspaces and fix
ws_obj_ids = defaultdict(lambda: defaultdict(dict))
#            workspace->id->type->(new_id, uuid)

for ws in wsdb[WS].find():
    # if it's public make it read only
    oldperm = ws[PER_DEF]
    if ws[ID] in pubws:
        ws[PER_DEF] = PER_READ
    # otherwise make it read only unless it's currently 'n'
    elif ws[PER_DEF] in PER_READABLE:
        ws[PER_DEF] = PER_READ
    if oldperm != ws[PER_DEF]:
        print 'Set default permissions on {}/{} {}->{}'.format(
            ws[OWNER], ws[ID], oldperm, ws[PER_DEF])
    # nab all the IDs, their types, and UUIDs
    obj_types = defaultdict(dict)
    for type_ in ws[OBJS]:
        if type_ not in newtype:
            print "Missing type, database is corrupted"
            print type_
            print newtype
            sys.exit(1)
        type_ = newtype[type_]  # fix type names
        for id_ in ws[OBJS][type_]:
            fixedid = id_.replace('_DOT_', '.')
            obj_types[fixedid][type_] = ws[OBJS][type_][id_]
    ws[OBJS] = {}  # delete the ws subdoc
    # fix the id names
    id_to_fix = {}
    allids = set()
    for id_ in obj_types:
        if OBJ_BAD_CHARS.search(id_):
            baseid = OBJ_BAD_CHARS.sub('_', id_)
            if baseid in allids:
                count = 1
                while True:
                    newid = baseid + '_' + count
                    if newid not in allids:
                        break
                    count += 1
            else:
                newid = baseid
            id_to_fix[id_] = newid
            allids.add(newid)
            print 'Renaming {}/{}/{}->{}'.format(ws[OWNER], ws[ID], id_, newid)
        else:
            allids.add(id_)
    # fix duplicate IDs
    for id_ in obj_types:
        if len(obj_types[id_]) > 1:  # duplicate
            fixedid = id_to_fix.get(id_, id_)
            print 'Duplicate ID {}/{}/{}. Renaming to:'.format(
                ws[OWNER], ws[ID], fixedid)
            for type_ in obj_types[id_]:
                newid = fixedid + '_' + type_
                print '\t{}'.format(newid)
                uuid = obj_types[id_][type_]
                ws_obj_ids[ws[ID]][id_][type_] = (newid, uuid)
                ws[OBJS][newid.replace('.', '_DOT_')] = uuid
        else:
            type_ = obj_types[id_].keys()[0]
            uuid = obj_types[id_][type_]
            if id_ in id_to_fix:
                ws_obj_ids[ws[ID]][id_][type_] = (id_to_fix[id_], uuid)
                id_ = id_to_fix[id_]
            ws[OBJS][id_.replace('.', '_DOT_')] = uuid
    # Save. Must have every single one, schema changed
    if not DRY_RUN:
        wsdb[WS].save(ws)

for wso in wsdb[WSO].find():
    oldtype = wso[TYPE]
    oldid = wso[ID]
    wso[TYPE] = newtype[wso[TYPE]]
    if wso[TYPE] in ws_obj_ids[wso['workspace']][wso[ID]]:
        newid, uuid = ws_obj_ids[wso['workspace']][wso[ID]][wso[TYPE]]
        # note instances earlier than current won't match on UUIDs
        wso[ID] = newid
    changeUUID = False
    if wso['workspace'] == 'NO_WORKSPACE':
        wso[ID] = wso['uuid']
        changeUUID = True
    if (not (changeUUID and SUPPRESS_NO_WORKSPACE_ID_CHANGE_OUTPUT) and
            (oldtype != wso[TYPE] or oldid != wso[ID])):
        print "Updating object {}/{}/{}->{} {}->{}".format(
            wso[OWNER], wso['workspace'], oldid, wso[ID], oldtype, wso[TYPE])
        if not DRY_RUN:
            wsdb[WSO].save(wso)
