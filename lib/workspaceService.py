try:
    import json
except ImportError:
    import sys
    sys.path.append('simplejson-2.3.3')
    import simplejson as json
    
import urllib



class workspaceService:

    def __init__(self, url):
        if url != None:
            self.url = url

    def save_object(self, id, type, data, workspace, options):

        arg_hash = { 'method': 'workspaceService.save_object',
                     'params': [id, type, data, workspace, options],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def delete_object(self, id, type, workspace):

        arg_hash = { 'method': 'workspaceService.delete_object',
                     'params': [id, type, workspace],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def delete_object_permanently(self, id, type, workspace):

        arg_hash = { 'method': 'workspaceService.delete_object_permanently',
                     'params': [id, type, workspace],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def get_object(self, id, type, workspace):

        arg_hash = { 'method': 'workspaceService.get_object',
                     'params': [id, type, workspace],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result']
        else:
            return None

    def get_objectmeta(self, id, type, workspace):

        arg_hash = { 'method': 'workspaceService.get_objectmeta',
                     'params': [id, type, workspace],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def revert_object(self, id, type, workspace):

        arg_hash = { 'method': 'workspaceService.revert_object',
                     'params': [id, type, workspace],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def unrevert_object(self, id, type, workspace, options):

        arg_hash = { 'method': 'workspaceService.unrevert_object',
                     'params': [id, type, workspace, options],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def copy_object(self, new_id, new_workspace, source_id, type, source_workspace):

        arg_hash = { 'method': 'workspaceService.copy_object',
                     'params': [new_id, new_workspace, source_id, type, source_workspace],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def move_object(self, new_id, new_workspace, source_id, type, source_workspace):

        arg_hash = { 'method': 'workspaceService.move_object',
                     'params': [new_id, new_workspace, source_id, type, source_workspace],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def has_object(self, id, type, workspace):

        arg_hash = { 'method': 'workspaceService.has_object',
                     'params': [id, type, workspace],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def create_workspace(self, name, default_permission):

        arg_hash = { 'method': 'workspaceService.create_workspace',
                     'params': [name, default_permission],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def delete_workspace(self, name):

        arg_hash = { 'method': 'workspaceService.delete_workspace',
                     'params': [name],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def clone_workspace(self, new_workspace, current_workspace, default_permission):

        arg_hash = { 'method': 'workspaceService.clone_workspace',
                     'params': [new_workspace, current_workspace, default_permission],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def list_workspaces(self, ):

        arg_hash = { 'method': 'workspaceService.list_workspaces',
                     'params': [],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def list_workspace_objects(self, workspace, options):

        arg_hash = { 'method': 'workspaceService.list_workspace_objects',
                     'params': [workspace, options],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def set_global_workspace_permissions(self, new_permission, workspace):

        arg_hash = { 'method': 'workspaceService.set_global_workspace_permissions',
                     'params': [new_permission, workspace],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def set_workspace_permissions(self, users, new_permission, workspace):

        arg_hash = { 'method': 'workspaceService.set_workspace_permissions',
                     'params': [users, new_permission, workspace],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None




        
