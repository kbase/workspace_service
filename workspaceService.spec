/*
=head1 workspaceService

API for accessing and writing documents objects to a workspace.

*/
module workspaceService {
	typedef int bool;
	typedef string workspace_id;
	typedef string object_type;
	typedef string object_id;
	typedef string permission;
	typedef string username;
	typedef string timestamp;
	typedef structure { 
       int version;
    } ObjectData;
    typedef structure { 
       int version;
    } WorkspaceData;
	typedef tuple<object_id id,object_type type,timestamp moddate,int instance,string command,username lastmodifier,username owner> object_metadata;
	typedef tuple<workspace_id id,username owner,timestamp moddate,int objects,permission user_permission,permission global_permission> workspace_metadata;
	
	/*Object management routines*/
	typedef structure { 
       string command;
       mapping<string,string> metadata;
    } save_object_options;
    funcdef save_object(object_id id,object_type type,ObjectData data,workspace_id workspace,save_object_options options) returns (object_metadata metadata);
    funcdef delete_object(object_id id,object_type type,workspace_id workspace) returns (object_metadata metadata);
    funcdef delete_object_permanently(object_id id,object_type type,workspace_id workspace) returns (object_metadata metadata);
    funcdef get_object(object_id id,object_type type,workspace_id workspace) returns (ObjectData data,object_metadata metadata);    
    funcdef get_objectmeta(object_id id,object_type type,workspace_id workspace) returns (object_metadata metadata); 
    funcdef revert_object(object_id id,object_type type,workspace_id workspace) returns (object_metadata metadata);
    typedef structure { 
       int index;
    } unrevert_object_options;
    funcdef unrevert_object(object_id id,object_type type,workspace_id workspace,unrevert_object_options options) returns (object_metadata metadata);
    funcdef copy_object(object_id new_id,workspace_id new_workspace,object_id source_id,object_type type,workspace_id source_workspace) returns (object_metadata metadata);
    funcdef move_object(object_id new_id,workspace_id new_workspace,object_id source_id,object_type type,workspace_id source_workspace) returns (object_metadata metadata);
    funcdef has_object(object_id id,object_type type,workspace_id workspace) returns (bool object_present);
    
    /*Workspace management routines*/
    funcdef create_workspace(workspace_id name,permission default_permission) returns (workspace_metadata metadata);
    funcdef delete_workspace(workspace_id name) returns (workspace_metadata metadata);
    funcdef clone_workspace(workspace_id new_workspace,workspace_id current_workspace,permission default_permission) returns (workspace_metadata metadata);
    funcdef list_workspaces() returns (list<workspace_metadata> workspaces);
    typedef structure { 
       string type;
    } list_workspace_objects_options;
    funcdef list_workspace_objects(workspace_id workspace,list_workspace_objects_options options) returns (list<object_metadata> objects);
    funcdef set_global_workspace_permissions(permission new_permission,workspace_id workspace) returns (workspace_metadata metadata);
    funcdef set_workspace_permissions(list<username> users,permission new_permission,workspace_id workspace) returns (bool success);

};
