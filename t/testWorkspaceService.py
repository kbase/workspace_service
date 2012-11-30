import unittest
from biokbase.auth.auth_token import get_token
from biokbase.workspaceService.Client import workspaceService
from datetime import datetime
import os
import subprocess

class TestWorkspaces(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        token_obj = get_token(username ='kbasetest', password ='@Suite525')
        cls.token = token_obj['access_token']


    def setUp(self):
        self.impl = workspaceService('http://localhost:7058')
        # FIXME: Right now you can't delete so we'll create a new one each time.
        self.ws_name = "testWS_%s" % datetime.utcnow().strftime('%s%f')
        self.conf = {"workspace": self.ws_name,"default_permission": "a", "auth": self.__class__.token }
        self.ws_meta = self.impl.create_workspace(self.conf)
    
    def testCreate(self):
        impl = self.impl
        ws_name = self.ws_name
        conf = self.conf
        ws_meta = self.ws_meta

        self.assertEquals(ws_meta[0], ws_name)
        self.assertEquals(ws_meta[1], 'kbasetest')
        self.assertEquals(ws_meta[3], 0)
        self.assertEquals(ws_meta[4], 'a')
        self.assertEquals(ws_meta[5], 'a')


        impl.delete_workspace({"workspace": ws_name, "auth": self.__class__.token})

    def testClone(self):
        impl = self.impl
        ws_name = self.ws_name
        conf = self.conf
        ws_meta = self.ws_meta

        clone_ws_name = "clone_%s" % ws_name

        clone = impl.clone_workspace({
            "new_workspace": clone_ws_name,
            "current_workspace": ws_name,
            "default_permission": "n",
            "auth": self.__class__.token 
        })

        self.assertEquals(clone[0], clone_ws_name)

        impl.delete_workspace({"workspace": ws_name, "auth": self.__class__.token})
        impl.delete_workspace({"workspace": clone_ws_name, "auth": self.__class__.token})


    def testDelete(self):
        impl = self.impl
        ws_name = self.ws_name
        conf = self.conf
        ws_meta = self.ws_meta

        impl.delete_workspace({"workspace": ws_name, "auth": self.__class__.token})

        self.assert_(True)

    def testListWorkspaces(self):
        impl = self.impl
        ws_name = self.ws_name
        conf = self.conf
        ws_meta = self.ws_meta

        ws_name2 = "testWS_%s" % datetime.utcnow().strftime('%s')
        conf2 = {"workspace": ws_name2,"default_permission": "a", "auth": self.__class__.token }
        ws_meta2 = self.impl.create_workspace(conf2)

        ws_list = impl.listWorkspaces({ "auth": self.__class__.token })

        ws_names = [ w[0][0] for w in ws_list ]

        self.assertIn(ws_name, ws_names)
        self.assertIn(ws_name2, ws_names)


    @classmethod
    def tearDownClass(self):
        test_dir = os.path.dirname(__file__)
        cleanup_file = os.path.join(test_dir, 'cleanup.pl')
        subprocess.call([cleanup_file])



if __name__ == '__main__':
    unittest.main()