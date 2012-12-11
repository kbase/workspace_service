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
	typedef string workspace_ref;
	typedef structure { 
       int version;
    } ObjectData;
    typedef structure { 
       int version;
    } WorkspaceData;
	typedef tuple<object_id id,object_type type,timestamp moddate,int instance,string command,username lastmodifier,username owner,workspace_id workspace,workspace_ref ref> object_metadata;
	typedef tuple<workspace_id id,username owner,timestamp moddate,int objects,permission user_permission,permission global_permission> workspace_metadata;
	
	/*Object management routines*/
    typedef structure { 
		object_id id;
		object_type type;
		ObjectData data;
		workspace_id workspace;
		string command;
		mapping<string,string> metadata;
		string auth;
		bool json;
		bool compressed;
		bool retrieveFromURL;
	} save_object_params;
    funcdef save_object(save_object_params params) returns (object_metadata metadata);
    
    typedef structure { 
		object_id id;
		object_type type;
		workspace_id workspace;
		string auth;
    } delete_object_params;
    funcdef delete_object(delete_object_params params) returns (object_metadata metadata);
    
    typedef structure { 
		object_id id;
		object_type type;
		workspace_id workspace;
		string auth;
    } delete_object_permanently_params;
    funcdef delete_object_permanently(delete_object_permanently_params params) returns (object_metadata metadata);
    
    typedef structure { 
		object_id id;
		object_type type;
		workspace_id workspace;
		int instance;
		string auth;
    } get_object_params;
    typedef structure { 
		ObjectData data;
		object_metadata metadata;
    } get_object_output;
    funcdef get_object(get_object_params params) returns (get_object_output output);    
    
    typedef structure { 
		object_id id;
		object_type type;
		workspace_id workspace;
		int instance;
		string auth;
    } get_objectmeta_params;
    funcdef get_objectmeta(get_objectmeta_params params) returns (object_metadata metadata); 
    
    typedef structure { 
		object_id id;
		object_type type;
		workspace_id workspace;
		int instance;
		string auth;
    } revert_object_params;
    funcdef revert_object(revert_object_params params) returns (object_metadata metadata);
      
    typedef structure { 
		object_id new_id;
		workspace_id new_workspace;
		object_id source_id;
		int instance;
		object_type type;
		workspace_id source_workspace;
		string auth;
    } copy_object_params;
    funcdef copy_object(copy_object_params params) returns (object_metadata metadata);
    
    typedef structure { 
		object_id new_id;
		workspace_id new_workspace;
		object_id source_id;
		object_type type;
		workspace_id source_workspace;
		string auth;
    } move_object_params;
    funcdef move_object(move_object_params params) returns (object_metadata metadata);
    
    typedef structure { 
		object_id id;
		int instance;
		object_type type;
		workspace_id workspace;
		string auth;
    } has_object_params;
    funcdef has_object(has_object_params params) returns (bool object_present);
    
    typedef structure { 
		object_id id;
		object_type type;
		workspace_id workspace;
		string auth;
    } object_history_params;
    funcdef object_history(object_history_params params) returns (list<object_metadata> metadatas);
    
    /*Workspace management routines*/ 
    typedef structure { 
		workspace_id workspace;
		permission default_permission;
		string auth;
    } create_workspace_params;
    funcdef create_workspace(create_workspace_params params) returns (workspace_metadata metadata);
    
    typedef structure { 
		workspace_id workspace;
		string auth;
    } get_workspacemeta_params;
    funcdef get_workspacemeta(get_workspacemeta_params params) returns (workspace_metadata metadata);
    
    typedef structure { 
		workspace_id workspace;
		string auth;
    } get_workspacepermissions_params;
    funcdef get_workspacepermissions(get_workspacepermissions_params params) returns (mapping<username,permission> user_permissions);
    
    typedef structure { 
		workspace_id workspace;
		string auth;
    } delete_workspace_params;
    funcdef delete_workspace(delete_workspace_params params) returns (workspace_metadata metadata);
    
    typedef structure { 
		workspace_id new_workspace;
		workspace_id current_workspace;
		permission default_permission;
		string auth;
    } clone_workspace_params;
    funcdef clone_workspace(clone_workspace_params params) returns (workspace_metadata metadata);
    
    typedef structure { 
		string auth;
    } list_workspaces_params;
    funcdef list_workspaces(list_workspaces_params params) returns (list<workspace_metadata> workspaces);
    
    typedef structure { 
       workspace_id workspace;
       string type;
       bool showDeletedObject;
       string auth;
    } list_workspace_objects_params;
    funcdef list_workspace_objects(list_workspace_objects_params params) returns (list<object_metadata> objects);

    typedef structure { 
       permission new_permission;
       workspace_id workspace;
       string auth;
    } set_global_workspace_permissions_params;
    funcdef set_global_workspace_permissions(set_global_workspace_permissions_params params) returns (workspace_metadata metadata);
    
    typedef structure { 
       list<username> users;
       permission new_permission;
       workspace_id workspace;
       string auth;
    } set_workspace_permissions_params;
    funcdef set_workspace_permissions(set_workspace_permissions_params params) returns (bool success);

	typedef structure {
		string jobid;
		string jobws;
    	string auth;
    } queue_job_params;
    funcdef queue_job(queue_job_params params) returns (bool success);

	typedef structure {
		string jobid;
		string jobws;
    	string status;
    	string auth;
    } set_job_status_params;
    funcdef set_job_status(set_job_status_params params) returns (bool success);
	
	typedef structure {
		string status;
    	string auth;
    } get_jobs_params;
    funcdef get_jobs(get_jobs_params params) returns (list<ObjectData> jobs);
};
