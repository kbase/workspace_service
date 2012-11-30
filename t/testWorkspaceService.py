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
        ws_name = "testworkspace_%s" % datetime.isoformat(datetime.utcnow()))

        conf = {"workspace": ws_name,"default_permission": "a", "auth": self.class.token }
        ws_meta = impl.create_workspace(conf)
        self.assertEquals(wsmeta[0], ws_name)
        self.assertEquals(wsmeta[1], 'kbasetest')
        self.assertEquals(wsmeta[3], 0)
        self.assertEquals(wsmeta[4], 'a')
        self.assertEquals(wsmeta[5], 'a')


        impl.delete_workspace({"workspace": ws_name, "auth": self.class.token})



if __name__ == '__main__':
    unittest.main()