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

    def save_object(self, params):

        arg_hash = { 'method': 'workspaceService.save_object',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def delete_object(self, params):

        arg_hash = { 'method': 'workspaceService.delete_object',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def delete_object_permanently(self, params):

        arg_hash = { 'method': 'workspaceService.delete_object_permanently',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def get_object(self, params):

        arg_hash = { 'method': 'workspaceService.get_object',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result']
        else:
            return None

    def get_objectmeta(self, params):

        arg_hash = { 'method': 'workspaceService.get_objectmeta',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def revert_object(self, params):

        arg_hash = { 'method': 'workspaceService.revert_object',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def unrevert_object(self, params):

        arg_hash = { 'method': 'workspaceService.unrevert_object',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def copy_object(self, params):

        arg_hash = { 'method': 'workspaceService.copy_object',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def move_object(self, params):

        arg_hash = { 'method': 'workspaceService.move_object',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def has_object(self, params):

        arg_hash = { 'method': 'workspaceService.has_object',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def object_history(self, params):

        arg_hash = { 'method': 'workspaceService.object_history',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def create_workspace(self, params):

        arg_hash = { 'method': 'workspaceService.create_workspace',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def get_workspacemeta(self, params):

        arg_hash = { 'method': 'workspaceService.get_workspacemeta',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def get_workspacepermissions(self, params):

        arg_hash = { 'method': 'workspaceService.get_workspacepermissions',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def delete_workspace(self, params):

        arg_hash = { 'method': 'workspaceService.delete_workspace',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def clone_workspace(self, params):

        arg_hash = { 'method': 'workspaceService.clone_workspace',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def list_workspaces(self, params):

        arg_hash = { 'method': 'workspaceService.list_workspaces',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def list_workspace_objects(self, params):

        arg_hash = { 'method': 'workspaceService.list_workspace_objects',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def set_global_workspace_permissions(self, params):

        arg_hash = { 'method': 'workspaceService.set_global_workspace_permissions',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None

    def set_workspace_permissions(self, params):

        arg_hash = { 'method': 'workspaceService.set_workspace_permissions',
                     'params': [params],
                     'version': '1.1'
                     }

        body = json.dumps(arg_hash)
        resp_str = urllib.urlopen(self.url, body).read()
        resp = json.loads(resp_str)

        if 'result' in resp:
            return resp['result'][0]
        else:
            return None




        
