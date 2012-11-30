import unittest
from biokbase.auth.auth_token import get_token
from biokbase.workspaceService.Client import workspaceService
from datetime import datetime


class TestWorkspaces(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        token_obj = get_token(username ='kbasetest', password ='@Suite525')
        cls.token = token_obj['access_token']
    
    def testCreate(self):
        impl = workspaceService('http://localhost:7058')

        # FIXME: Right now you can't delete so we'll create a new one each time.
        # FIXME: The following is too long "testworkspace_1354258955.274313". Document the limits.
        ws_name = "testWS_%s" % datetime.utcnow().strftime('%s')

        conf = {"workspace": ws_name,"default_permission": "a", "auth": self.__class__.token }
        ws_meta = impl.create_workspace(conf)
        self.assertEquals(ws_meta[0], ws_name)
        self.assertEquals(ws_meta[1], 'kbasetest')
        self.assertEquals(ws_meta[3], 0)
        self.assertEquals(ws_meta[4], 'a')
        self.assertEquals(ws_meta[5], 'a')


        impl.delete_workspace({"workspace": ws_name, "auth": self.__class__.token})



if __name__ == '__main__':
    unittest.main()