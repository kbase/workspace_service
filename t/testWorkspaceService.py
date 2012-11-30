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
        test_dir = os.path.dirname(os.path.abspath(__file__))
        cleanup_file = os.path.join(test_dir, 'cleanup.pl')
        subprocess.call(['perl', cleanup_file])


    def setUp(self):
        self.impl = workspaceService('http://localhost:7058')
        # FIXME: Right now you can't delete so we'll create a new one each time.
        self.ws_name = "testWS_%s" % datetime.utcnow().strftime('%s%f')
        self.conf = {"workspace": self.ws_name,"default_permission": "a", "auth": self.__class__.token }
        self.ws_meta = self.impl.create_workspace(self.conf)
    
    def testCreate(self):
        """
        Test Workspace Creation
        """
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
        """
        Test Workspace Cloning
        """
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
        """
        Test Workspace Delete
        """
        impl = self.impl
        ws_name = self.ws_name
        conf = self.conf
        ws_meta = self.ws_meta

        impl.delete_workspace({"workspace": ws_name, "auth": self.__class__.token})

        # assert true as long as we didn't throw an exception
        self.assert_(True)

    def testListWorkspaces(self):
        """
        Test Workspace List
        """
        impl = self.impl
        ws_name = self.ws_name
        conf = self.conf
        ws_meta = self.ws_meta

        ws_name2 = "testWS_%s" % datetime.utcnow().strftime('%s')
        conf2 = {"workspace": ws_name2,"default_permission": "a", "auth": self.__class__.token }
        ws_meta2 = self.impl.create_workspace(conf2)

        ws_list = impl.list_workspaces({ "auth": self.__class__.token })
        ws_names = [ w[0] for w in ws_list ]

        self.assertIn(ws_name, ws_names)
        self.assertIn(ws_name2, ws_names)

        impl.delete_workspace({"workspace": ws_name, "auth": self.__class__.token})
        impl.delete_workspace({"workspace": ws_name2, "auth": self.__class__.token})


    def testListWorkspaceObjects(self):
        impl = self.impl
        ws_name = self.ws_name
        conf = self.conf
        ws_meta = self.ws_meta

        test_object1 = {
            "id": "test_object_id1",
            "type": "Genome",
            "data": {"name":"testgenome1", "string":"ACACGATTACA"},
            "workspace": ws_name,
            "command": "something",
            "metadata": {"origin":"shreyas"},
            "auth": self.__class__.token
        }

        test_object2 = {
            "id": "test_object_id2",
            "type": "Genome",
            "data": {"name":"testgenome2", "string":"ACAAAAGGATTACA"},
            "workspace": ws_name,
            "command": "noop",
            "metadata": {"origin":"shreyas"},
            "auth": self.__class__.token
        }

        obj_meta1 = impl.save_object(test_object1)
        obj_meta2 = impl.save_object(test_object2)

        self.assertEquals(obj_meta1[0], "test_object_id1")
        self.assertEquals(obj_meta2[0], "test_object_id2")

        ws_objects = impl.list_workspace_objects({"workspace": ws_name, "auth": self.__class__.token })
        self.assertEquals(len(ws_objects),2)

        # get names of objects
        obj_list = [ o[0] for o in ws_objects ]
        self.assertIn("test_object_id1", obj_list)
        self.assertIn("test_object_id2", obj_list)

        impl.delete_workspace({"workspace": ws_name, "auth": self.__class__.token})

    def testSaveObject(self):
        impl = self.impl
        ws_name = self.ws_name
        conf = self.conf
        ws_meta = self.ws_meta

        test_object1 = {
            "id": "test_object_id1",
            "type": "Genome",
            "data": {"name":"testgenome1", "string":"ACACGATTACA"},
            "workspace": ws_name,
            "command": "something",
            "metadata": {"origin":"shreyas"},
            "auth": self.__class__.token
        }
        obj_meta1 = impl.save_object(test_object1)

        self.assertEquals(obj_meta1[0], "test_object_id1")
        self.assertEquals(obj_meta1[1], "Genome")
        self.assertRegexpMatches(obj_meta1[2], '\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d')
        self.assertEquals(obj_meta1[3], 0)
        self.assertEquals(obj_meta1[4], 'something')
        self.assertEquals(obj_meta1[5], 'kbasetest')
        self.assertEquals(obj_meta1[6], 'kbasetest')


    @classmethod
    def tearDownClass(self):
        test_dir = os.path.dirname(os.path.abspath(__file__))
        cleanup_file = os.path.join(test_dir, 'cleanup.pl')
        subprocess.call(['perl', cleanup_file])




if __name__ == '__main__':
    unittest.main()
