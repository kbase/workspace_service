

function workspaceService(url, auth, auth_cb) {

    var _url = url;
    var deprecationWarningSent = false;
    
    function deprecationWarning() {
        if (!deprecationWarningSent) {
            deprecationWarningSent = true;
            if (!window.console) return;
            console.log(
                "DEPRECATION WARNING: '*_async' method names will be removed",
                "in a future version. Please use the identical methods without",
                "the'_async' suffix.");
        }
    }

    var _auth = auth ? auth : { 'token' : '', 'user_id' : ''};
    var _auth_cb = auth_cb;


    this.load_media_from_bio = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.load_media_from_bio",
        [params], 1, _callback, _errorCallback);
};

    this.load_media_from_bio_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.load_media_from_bio", [params], 1, _callback, _error_callback);
    };

    this.import_bio = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.import_bio",
        [params], 1, _callback, _errorCallback);
};

    this.import_bio_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.import_bio", [params], 1, _callback, _error_callback);
    };

    this.import_map = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.import_map",
        [params], 1, _callback, _errorCallback);
};

    this.import_map_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.import_map", [params], 1, _callback, _error_callback);
    };

    this.save_object = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.save_object",
        [params], 1, _callback, _errorCallback);
};

    this.save_object_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.save_object", [params], 1, _callback, _error_callback);
    };

    this.delete_object = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.delete_object",
        [params], 1, _callback, _errorCallback);
};

    this.delete_object_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.delete_object", [params], 1, _callback, _error_callback);
    };

    this.delete_object_permanently = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.delete_object_permanently",
        [params], 1, _callback, _errorCallback);
};

    this.delete_object_permanently_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.delete_object_permanently", [params], 1, _callback, _error_callback);
    };

    this.get_object = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.get_object",
        [params], 1, _callback, _errorCallback);
};

    this.get_object_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.get_object", [params], 1, _callback, _error_callback);
    };

    this.get_objects = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.get_objects",
        [params], 1, _callback, _errorCallback);
};

    this.get_objects_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.get_objects", [params], 1, _callback, _error_callback);
    };

    this.get_object_by_ref = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.get_object_by_ref",
        [params], 1, _callback, _errorCallback);
};

    this.get_object_by_ref_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.get_object_by_ref", [params], 1, _callback, _error_callback);
    };

    this.save_object_by_ref = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.save_object_by_ref",
        [params], 1, _callback, _errorCallback);
};

    this.save_object_by_ref_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.save_object_by_ref", [params], 1, _callback, _error_callback);
    };

    this.get_objectmeta = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.get_objectmeta",
        [params], 1, _callback, _errorCallback);
};

    this.get_objectmeta_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.get_objectmeta", [params], 1, _callback, _error_callback);
    };

    this.get_objectmeta_by_ref = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.get_objectmeta_by_ref",
        [params], 1, _callback, _errorCallback);
};

    this.get_objectmeta_by_ref_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.get_objectmeta_by_ref", [params], 1, _callback, _error_callback);
    };

    this.revert_object = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.revert_object",
        [params], 1, _callback, _errorCallback);
};

    this.revert_object_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.revert_object", [params], 1, _callback, _error_callback);
    };

    this.copy_object = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.copy_object",
        [params], 1, _callback, _errorCallback);
};

    this.copy_object_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.copy_object", [params], 1, _callback, _error_callback);
    };

    this.move_object = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.move_object",
        [params], 1, _callback, _errorCallback);
};

    this.move_object_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.move_object", [params], 1, _callback, _error_callback);
    };

    this.has_object = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.has_object",
        [params], 1, _callback, _errorCallback);
};

    this.has_object_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.has_object", [params], 1, _callback, _error_callback);
    };

    this.object_history = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.object_history",
        [params], 1, _callback, _errorCallback);
};

    this.object_history_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.object_history", [params], 1, _callback, _error_callback);
    };

    this.create_workspace = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.create_workspace",
        [params], 1, _callback, _errorCallback);
};

    this.create_workspace_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.create_workspace", [params], 1, _callback, _error_callback);
    };

    this.get_workspacemeta = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.get_workspacemeta",
        [params], 1, _callback, _errorCallback);
};

    this.get_workspacemeta_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.get_workspacemeta", [params], 1, _callback, _error_callback);
    };

    this.get_workspacepermissions = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.get_workspacepermissions",
        [params], 1, _callback, _errorCallback);
};

    this.get_workspacepermissions_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.get_workspacepermissions", [params], 1, _callback, _error_callback);
    };

    this.delete_workspace = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.delete_workspace",
        [params], 1, _callback, _errorCallback);
};

    this.delete_workspace_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.delete_workspace", [params], 1, _callback, _error_callback);
    };

    this.clone_workspace = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.clone_workspace",
        [params], 1, _callback, _errorCallback);
};

    this.clone_workspace_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.clone_workspace", [params], 1, _callback, _error_callback);
    };

    this.list_workspaces = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.list_workspaces",
        [params], 1, _callback, _errorCallback);
};

    this.list_workspaces_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.list_workspaces", [params], 1, _callback, _error_callback);
    };

    this.list_workspace_objects = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.list_workspace_objects",
        [params], 1, _callback, _errorCallback);
};

    this.list_workspace_objects_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.list_workspace_objects", [params], 1, _callback, _error_callback);
    };

    this.set_global_workspace_permissions = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.set_global_workspace_permissions",
        [params], 1, _callback, _errorCallback);
};

    this.set_global_workspace_permissions_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.set_global_workspace_permissions", [params], 1, _callback, _error_callback);
    };

    this.set_workspace_permissions = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.set_workspace_permissions",
        [params], 1, _callback, _errorCallback);
};

    this.set_workspace_permissions_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.set_workspace_permissions", [params], 1, _callback, _error_callback);
    };

    this.get_user_settings = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.get_user_settings",
        [params], 1, _callback, _errorCallback);
};

    this.get_user_settings_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.get_user_settings", [params], 1, _callback, _error_callback);
    };

    this.set_user_settings = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.set_user_settings",
        [params], 1, _callback, _errorCallback);
};

    this.set_user_settings_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.set_user_settings", [params], 1, _callback, _error_callback);
    };

    this.queue_job = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.queue_job",
        [params], 1, _callback, _errorCallback);
};

    this.queue_job_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.queue_job", [params], 1, _callback, _error_callback);
    };

    this.set_job_status = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.set_job_status",
        [params], 1, _callback, _errorCallback);
};

    this.set_job_status_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.set_job_status", [params], 1, _callback, _error_callback);
    };

    this.get_jobs = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.get_jobs",
        [params], 1, _callback, _errorCallback);
};

    this.get_jobs_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.get_jobs", [params], 1, _callback, _error_callback);
    };

    this.get_types = function (_callback, _errorCallback) {
    return json_call_ajax("workspaceService.get_types",
        [], 1, _callback, _errorCallback);
};

    this.get_types_async = function (_callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.get_types", [], 1, _callback, _error_callback);
    };

    this.add_type = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.add_type",
        [params], 1, _callback, _errorCallback);
};

    this.add_type_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.add_type", [params], 1, _callback, _error_callback);
    };

    this.remove_type = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.remove_type",
        [params], 1, _callback, _errorCallback);
};

    this.remove_type_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.remove_type", [params], 1, _callback, _error_callback);
    };

    this.patch = function (params, _callback, _errorCallback) {
    return json_call_ajax("workspaceService.patch",
        [params], 1, _callback, _errorCallback);
};

    this.patch_async = function (params, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("workspaceService.patch", [params], 1, _callback, _error_callback);
    };
 

    /*
     * JSON call using jQuery method.
     */
    function json_call_ajax(method, params, numRets, callback, errorCallback) {
        var deferred = $.Deferred();

        if (typeof callback === 'function') {
           deferred.done(callback);
        }

        if (typeof errorCallback === 'function') {
           deferred.fail(errorCallback);
        }

        var rpc = {
            params : params,
            method : method,
            version: "1.1",
            id: String(Math.random()).slice(2),
        };
        
        var beforeSend = null;
        var token = (_auth_cb && typeof _auth_cb === 'function') ? _auth_cb()
            : (_auth.token ? _auth.token : null);
        if (token != null) {
            beforeSend = function (xhr) {
                xhr.setRequestHeader("Authorization", token);
            }
        }

        jQuery.ajax({
            url: _url,
            dataType: "text",
            type: 'POST',
            processData: false,
            data: JSON.stringify(rpc),
            beforeSend: beforeSend,
            success: function (data, status, xhr) {
                var result;
                try {
                    var resp = JSON.parse(data);
                    result = (numRets === 1 ? resp.result[0] : resp.result);
                } catch (err) {
                    deferred.reject({
                        status: 503,
                        error: err,
                        url: _url,
                        resp: data
                    });
                    return;
                }
                deferred.resolve(result);
            },
            error: function (xhr, textStatus, errorThrown) {
                var error;
                if (xhr.responseText) {
                    try {
                        var resp = JSON.parse(xhr.responseText);
                        error = resp.error;
                    } catch (err) { // Not JSON
                        error = "Unknown error - " + xhr.responseText;
                    }
                } else {
                    error = "Unknown Error";
                }
                deferred.reject({
                    status: 500,
                    error: error
                });
            }
        });
        return deferred.promise();
    }
}


