

function workspaceService(url) {

    var _url = url;


    this.save_object = function(id, type, data, workspace, options)
    {
	var resp = json_call_ajax_sync("workspaceService.save_object", [id, type, data, workspace, options]);
//	var resp = json_call_sync("workspaceService.save_object", [id, type, data, workspace, options]);
        return resp[0];
    }

    this.save_object_async = function(id, type, data, workspace, options, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.save_object", [id, type, data, workspace, options], 1, _callback, _error_callback)
    }

    this.delete_object = function(id, type, workspace)
    {
	var resp = json_call_ajax_sync("workspaceService.delete_object", [id, type, workspace]);
//	var resp = json_call_sync("workspaceService.delete_object", [id, type, workspace]);
        return resp[0];
    }

    this.delete_object_async = function(id, type, workspace, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.delete_object", [id, type, workspace], 1, _callback, _error_callback)
    }

    this.delete_object_permanently = function(id, type, workspace)
    {
	var resp = json_call_ajax_sync("workspaceService.delete_object_permanently", [id, type, workspace]);
//	var resp = json_call_sync("workspaceService.delete_object_permanently", [id, type, workspace]);
        return resp[0];
    }

    this.delete_object_permanently_async = function(id, type, workspace, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.delete_object_permanently", [id, type, workspace], 1, _callback, _error_callback)
    }

    this.get_object = function(id, type, workspace)
    {
	var resp = json_call_ajax_sync("workspaceService.get_object", [id, type, workspace]);
//	var resp = json_call_sync("workspaceService.get_object", [id, type, workspace]);
        return resp;
    }

    this.get_object_async = function(id, type, workspace, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.get_object", [id, type, workspace], 2, _callback, _error_callback)
    }

    this.get_objectmeta = function(id, type, workspace)
    {
	var resp = json_call_ajax_sync("workspaceService.get_objectmeta", [id, type, workspace]);
//	var resp = json_call_sync("workspaceService.get_objectmeta", [id, type, workspace]);
        return resp[0];
    }

    this.get_objectmeta_async = function(id, type, workspace, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.get_objectmeta", [id, type, workspace], 1, _callback, _error_callback)
    }

    this.revert_object = function(id, type, workspace)
    {
	var resp = json_call_ajax_sync("workspaceService.revert_object", [id, type, workspace]);
//	var resp = json_call_sync("workspaceService.revert_object", [id, type, workspace]);
        return resp[0];
    }

    this.revert_object_async = function(id, type, workspace, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.revert_object", [id, type, workspace], 1, _callback, _error_callback)
    }

    this.unrevert_object = function(id, type, workspace, options)
    {
	var resp = json_call_ajax_sync("workspaceService.unrevert_object", [id, type, workspace, options]);
//	var resp = json_call_sync("workspaceService.unrevert_object", [id, type, workspace, options]);
        return resp[0];
    }

    this.unrevert_object_async = function(id, type, workspace, options, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.unrevert_object", [id, type, workspace, options], 1, _callback, _error_callback)
    }

    this.copy_object = function(new_id, new_workspace, source_id, type, source_workspace)
    {
	var resp = json_call_ajax_sync("workspaceService.copy_object", [new_id, new_workspace, source_id, type, source_workspace]);
//	var resp = json_call_sync("workspaceService.copy_object", [new_id, new_workspace, source_id, type, source_workspace]);
        return resp[0];
    }

    this.copy_object_async = function(new_id, new_workspace, source_id, type, source_workspace, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.copy_object", [new_id, new_workspace, source_id, type, source_workspace], 1, _callback, _error_callback)
    }

    this.move_object = function(new_id, new_workspace, source_id, type, source_workspace)
    {
	var resp = json_call_ajax_sync("workspaceService.move_object", [new_id, new_workspace, source_id, type, source_workspace]);
//	var resp = json_call_sync("workspaceService.move_object", [new_id, new_workspace, source_id, type, source_workspace]);
        return resp[0];
    }

    this.move_object_async = function(new_id, new_workspace, source_id, type, source_workspace, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.move_object", [new_id, new_workspace, source_id, type, source_workspace], 1, _callback, _error_callback)
    }

    this.has_object = function(id, type, workspace)
    {
	var resp = json_call_ajax_sync("workspaceService.has_object", [id, type, workspace]);
//	var resp = json_call_sync("workspaceService.has_object", [id, type, workspace]);
        return resp[0];
    }

    this.has_object_async = function(id, type, workspace, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.has_object", [id, type, workspace], 1, _callback, _error_callback)
    }

    this.create_workspace = function(name, default_permission)
    {
	var resp = json_call_ajax_sync("workspaceService.create_workspace", [name, default_permission]);
//	var resp = json_call_sync("workspaceService.create_workspace", [name, default_permission]);
        return resp[0];
    }

    this.create_workspace_async = function(name, default_permission, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.create_workspace", [name, default_permission], 1, _callback, _error_callback)
    }

    this.delete_workspace = function(name)
    {
	var resp = json_call_ajax_sync("workspaceService.delete_workspace", [name]);
//	var resp = json_call_sync("workspaceService.delete_workspace", [name]);
        return resp[0];
    }

    this.delete_workspace_async = function(name, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.delete_workspace", [name], 1, _callback, _error_callback)
    }

    this.clone_workspace = function(new_workspace, current_workspace, default_permission)
    {
	var resp = json_call_ajax_sync("workspaceService.clone_workspace", [new_workspace, current_workspace, default_permission]);
//	var resp = json_call_sync("workspaceService.clone_workspace", [new_workspace, current_workspace, default_permission]);
        return resp[0];
    }

    this.clone_workspace_async = function(new_workspace, current_workspace, default_permission, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.clone_workspace", [new_workspace, current_workspace, default_permission], 1, _callback, _error_callback)
    }

    this.list_workspaces = function()
    {
	var resp = json_call_ajax_sync("workspaceService.list_workspaces", []);
//	var resp = json_call_sync("workspaceService.list_workspaces", []);
        return resp[0];
    }

    this.list_workspaces_async = function(_callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.list_workspaces", [], 1, _callback, _error_callback)
    }

    this.list_workspace_objects = function(workspace, options)
    {
	var resp = json_call_ajax_sync("workspaceService.list_workspace_objects", [workspace, options]);
//	var resp = json_call_sync("workspaceService.list_workspace_objects", [workspace, options]);
        return resp[0];
    }

    this.list_workspace_objects_async = function(workspace, options, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.list_workspace_objects", [workspace, options], 1, _callback, _error_callback)
    }

    this.set_global_workspace_permissions = function(new_permission, workspace)
    {
	var resp = json_call_ajax_sync("workspaceService.set_global_workspace_permissions", [new_permission, workspace]);
//	var resp = json_call_sync("workspaceService.set_global_workspace_permissions", [new_permission, workspace]);
        return resp[0];
    }

    this.set_global_workspace_permissions_async = function(new_permission, workspace, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.set_global_workspace_permissions", [new_permission, workspace], 1, _callback, _error_callback)
    }

    this.set_workspace_permissions = function(users, new_permission, workspace)
    {
	var resp = json_call_ajax_sync("workspaceService.set_workspace_permissions", [users, new_permission, workspace]);
//	var resp = json_call_sync("workspaceService.set_workspace_permissions", [users, new_permission, workspace]);
        return resp[0];
    }

    this.set_workspace_permissions_async = function(users, new_permission, workspace, _callback, _error_callback)
    {
	json_call_ajax_async("workspaceService.set_workspace_permissions", [users, new_permission, workspace], 1, _callback, _error_callback)
    }

    function _json_call_prepare(url, method, params, async_flag)
    {
	var rpc = { 'params' : params,
		    'method' : method,
		    'version': "1.1",
	};
	
	var body = JSON.stringify(rpc);
	
	var http = new XMLHttpRequest();
	
	http.open("POST", url, async_flag);
	
	//Send the proper header information along with the request
	http.setRequestHeader("Content-type", "application/json");
	//http.setRequestHeader("Content-length", body.length);
	//http.setRequestHeader("Connection", "close");
	return [http, body];
    }

    /*
     * JSON call using jQuery method.
     */

    function json_call_ajax_sync(method, params)
    {
        var rpc = { 'params' : params,
                    'method' : method,
                    'version': "1.1",
        };
        
        var body = JSON.stringify(rpc);
        var resp_txt;
	var code;
        
        var x = jQuery.ajax({       "async": false,
                                    dataType: "text",
                                    url: _url,
                                    success: function (data, status, xhr) { resp_txt = data; code = xhr.status },
				    error: function(xhr, textStatus, errorThrown) { resp_txt = xhr.responseText, code = xhr.status },
                                    data: body,
                                    processData: false,
                                    type: 'POST',
				    });

        var result;

        if (resp_txt)
        {
	    var resp = JSON.parse(resp_txt);
	    
	    if (code >= 500)
	    {
		throw resp.error;
	    }
	    else
	    {
		return resp.result;
	    }
        }
	else
	{
	    return null;
	}
    }

    function json_call_ajax_async(method, params, num_rets, callback, error_callback)
    {
        var rpc = { 'params' : params,
                    'method' : method,
                    'version': "1.1",
        };
        
        var body = JSON.stringify(rpc);
        var resp_txt;
	var code;
        
        var x = jQuery.ajax({       "async": true,
                                    dataType: "text",
                                    url: _url,
                                    success: function (data, status, xhr)
				{
				    resp = JSON.parse(data);
				    var result = resp["result"];
				    if (num_rets == 1)
				    {
					callback(result[0]);
				    }
				    else
				    {
					callback(result);
				    }
				    
				},
				    error: function(xhr, textStatus, errorThrown)
				{
				    if (xhr.responseText)
				    {
					resp = JSON.parse(xhr.responseText);
					if (error_callback)
					{
					    error_callback(resp.error);
					}
					else
					{
					    throw resp.error;
					}
				    }
				},
                                    data: body,
                                    processData: false,
                                    type: 'POST',
				    });

    }

    function json_call_async(method, params, num_rets, callback)
    {
	var tup = _json_call_prepare(_url, method, params, true);
	var http = tup[0];
	var body = tup[1];
	
	http.onreadystatechange = function() {
	    if (http.readyState == 4 && http.status == 200) {
		var resp_txt = http.responseText;
		var resp = JSON.parse(resp_txt);
		var result = resp["result"];
		if (num_rets == 1)
		{
		    callback(result[0]);
		}
		else
		{
		    callback(result);
		}
	    }
	}
	
	http.send(body);
	
    }
    
    function json_call_sync(method, params)
    {
	var tup = _json_call_prepare(url, method, params, false);
	var http = tup[0];
	var body = tup[1];
	
	http.send(body);
	
	var resp_txt = http.responseText;
	
	var resp = JSON.parse(resp_txt);
	var result = resp["result"];
	    
	return result;
    }
}

