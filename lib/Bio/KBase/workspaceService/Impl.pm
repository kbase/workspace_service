package Bio::KBase::workspaceService::Impl;
use strict;
use Bio::KBase::Exceptions;
# Use Semantic Versioning (2.0.0-rc.1)
# http://semver.org 
our $VERSION = "0.1.0";

=head1 NAME

workspaceService

=head1 DESCRIPTION

=head1 workspaceService

API for accessing and writing documents objects to a workspace.

=cut

#BEGIN_HEADER
use MongoDB;
use JSON::XS;
use Tie::IxHash;
use FileHandle;
use DateTime;
use Data::Dumper;
use Bio::KBase::AuthUser;
use Bio::KBase::AuthToken;
use Bio::KBase::workspaceService::Object;
use Bio::KBase::workspaceService::Workspace;
use Bio::KBase::workspaceService::WorkspaceUser;
use Bio::KBase::workspaceService::DataObject;
use Config::Simple;
use IO::Compress::Gzip qw(gzip);
use IO::Uncompress::Gunzip qw(gunzip);
use File::Temp qw(tempfile);
use LWP::Simple qw(getstore);

sub _args {
    my $mandatory = shift;
    my $optional  = shift;
    my $args      = shift;
    my @errors;
    foreach my $arg (@$mandatory) {
        push(@errors, $arg) unless defined($args->{$arg});
    }
    if (@errors) {
        my $missing = join("; ", @errors);
        Bio::KBase::Exceptions::KBaseException->throw(error => "Mandatory arguments $missing missing.",
							       method_name => '_args');
    }
    foreach my $arg (keys %$optional) {
        $args->{$arg} = $optional->{$arg} unless defined $args->{$arg};
    }
    return $args;
}

sub _getUsername {
	my ($self) = @_;
	if (!defined($self->{_currentUser})) {
		if (defined($self->{_testuser})) {
			$self->{_currentUser} = $self->{_testuser};
		} else {
			$self->{_currentUser} = "public";
		}
		
	}
	return $self->{_currentUser};
}

sub _getCurrentUserObj {
	my ($self) = @_;
	if (!defined($self->{_currentUserObj})) {
		$self->{_currentUserObj} = $self->_getWorkspaceUser($self->_getUsername());
	}
	return $self->{_currentUserObj};
}

sub _setContext {
	my ($self,$context,$params) = @_;
    if ( defined $params->{auth} ) {
        my $token = Bio::KBase::AuthToken->new(
            token => $params->{auth},
        );
        if ($token->validate()) {
            $self->{_currentUser} = $token->user_id;
        } else {
            Bio::KBase::Exceptions::KBaseException->throw(error => "Invalid authorization token!",
                method_name => 'workspaceDocument::_setContext');
        }
    }
	$self->{_authentication} = $params->{auth};
	$self->{_context} = $context;
}

sub _getContext {
	my ($self) = @_;
	return $self->{_context};
}

sub _clearContext {
	my ($self) = @_;
    delete $self->{_currentUserObj};
    delete $self->{_currentUser};
    delete $self->{_authentication};
	delete $self->{_context};
}

#####################################################################
#Database interaction routines
#####################################################################

=head3 _mongodb

Definition:
	MongoDB = _mongodb();
Description:
	Returns MongoDB object

=cut

sub _mongodb {
    my ($self) = @_;
    if (!defined($self->{_mongodb})) {
    	my $config = {
	        host => $self->{_host},
	        host => $self->{_host},
	        db_name        => $self->{_db},
	        auto_connect   => 1,
	        auto_reconnect => 1
	    };
	    my $conn = MongoDB::Connection->new(%$config);
    	Bio::KBase::Exceptions::KBaseException->throw(error => "Unable to connect: $@",
							       method_name => 'workspaceDocumentDB::_mongodb') if (!defined($conn));
    	my $db_name = $self->{_db};
    	$self->{_mongodb} = $conn->$db_name;
    }    
    return $self->{_mongodb};
}

=head3 _updateDB

Definition:
	void  _updateDB(string:name,{}:query,{}:update);
Description:
	Updates the database object with the specified query and update command

=cut

sub _updateDB {
    my ($self,$name,$query,$update) = @_;
    my $data = $self->_mongodb()->run_command({
    	findAndModify => $name,
    	query => $query,
    	update => $update
    });
    if (ref($data) ne "HASH" || !defined($data->{value})) {
    	return 0;
    }
    return 1;
}

#####################################################################
#Object creation methods
#####################################################################

=head3 _createWorkspace

Definition:
	Bio::KBase::workspaceService::Workspace =  _createWorkspace(string:id,string:permission);
Description:
	Creates specified workspace in database and returns workspace object

=cut

sub _createWorkspace {
	my ($self,$id,$defaultPermissions) = @_;
	my $ws = $self->_getWorkspace($id);
	if (defined($ws)) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Cannot create Workspace ".$id." because Workspace already exists!",
							       method_name => '_createWorkspace');
	}
	$ws = Bio::KBase::workspaceService::Workspace->new({
		parent => $self,
		moddate => DateTime->now()->datetime(),
		id => $id,
		owner => $self->_getUsername(),
		defaultPermissions => $defaultPermissions,
		objects => {}
	});
	$self->_mongodb()->workspaces->insert({
		moddate => $ws->moddate(),
		id => $ws->id(),
		owner => $ws->owner(),
		defaultPermissions => $ws->defaultPermissions(),
		objects => $ws->objects()
	});
	my $wu = $self->_getCurrentUserObj();
	if (!defined($wu)) {
		$wu = $self->_createWorkspaceUser($self->_getUsername());
	}
	$wu->setWorkspacePermission($ws->id(),"a");
	return $ws;
}

=head3 _createWorkspaceUser

Definition:
	Bio::KBase::workspaceService::WorkspaceUser =  _createWorkspaceUser(string:id);
Description:
	Creates specified WorkspaceUser in database and returns WorkspaceUser object

=cut

sub _createWorkspaceUser {
	my ($self,$id) = @_;
	my $user = $self->_getWorkspaceUser($id);
	if (defined($user)) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Cannot create WorkspaceUser ".$id." because WorkspaceUser already exists!",
							       method_name => '_createWorkspaceUser');
	}
	$user = Bio::KBase::workspaceService::WorkspaceUser->new({
		parent => $self,
		moddate => DateTime->now()->datetime(),
		id => $id,
		workspaces => {}
	});
	$self->_mongodb()->workspaceUsers->insert({
		moddate => $user->moddate(),
		id => $user->id(),
		workspaces => $user->workspaces()
	});
	return $user;
}

=head3 _createObject

Definition:
	Bio::KBase::workspaceService::Object =  _createObject(string:id);
Description:
	Creates specified Object in database and returns Object

=cut

sub _createObject {
	my ($self,$data) = @_;
	$data->{parent} = $self;
	my $obj = Bio::KBase::workspaceService::Object->new($data);
	$self->_mongodb()->workspaceObjects->insert({
		uuid => $obj->uuid(),
		id => $obj->id(),
		workspace => $obj->workspace(),
		type => $obj->type(),
		ancestor => $obj->ancestor(),
		revertAncestors => $obj->revertAncestors(),
		owner => $obj->owner(),
		lastModifiedBy => $obj->lastModifiedBy(),
		command => $obj->command(),
		instance => $obj->instance(),
		chsum => $obj->chsum(),
		meta => $obj->meta()
	});
	return $obj;
}

=head3 _createDataObject

Definition:
	Bio::KBase::workspaceService::DataObject =  _createDataObject({}|string:data);
Description:
	Creates specified DataObject from input data in database

=cut

sub _createDataObject {
	my ($self,$data) = @_;
	my $obj = Bio::KBase::workspaceService::DataObject->new({
		parent => $self,
		rawdata => $data	
	});
	#Checking if the data is already in the database
	my $dbobj = $self->_getDataObject($obj->chsum());
	if (defined($dbobj)) {
		return $dbobj;
	}
	$self->_mongodb()->workspaceDataObjects->insert({
		creationDate => $obj->creationDate(),
		chsum => $obj->chsum(),
		data => $obj->data(),
		compressed => $obj->compressed(),
		json => $obj->json()
	});
	return $obj;
}


#####################################################################
#Object deletion methods
#####################################################################

=head3 _deleteWorkspace

Definition:
	void  _deleteWorkspace(string:id);
Description:
	Deletes specified workspace in database

=cut

sub _deleteWorkspace {
	my ($self,$id) = @_;
	$self->_getWorkspace($id,{throwErrorIfMissing => 1});
	$self->_mongodb()->workspaces->remove({id => $id});
}

=head3 _deleteWorkspaceUser

Definition:
	void  _deleteWorkspaceUser(string:id);
Description:
	Deletes specified workspace user in database

=cut

sub _deleteWorkspaceUser {
	my ($self,$id) = @_;
	$self->_getWorkspaceUser($id,{throwErrorIfMissing => 1});
	$self->_mongodb()->workspaceUsers->remove({id => $id});
}

=head3 _deleteObject

Definition:
	void  _deleteObject(string:id);
Description:
	Deletes specified object in database

=cut

sub _deleteObject {
	my ($self,$uuid,$deleteRelatedData) = @_;
	my $obj = $self->_getObject($uuid,{throwErrorIfMissing => 1});
	$self->_mongodb()->workspaceObjects->remove({uuid => $uuid});
	if (defined($deleteRelatedData) && $deleteRelatedData == 1) {
		my $otherobj = $self->_getObjectByChsum($obj->chsum());
		if (!defined($otherobj)) {
			$self->_deleteDataObject($obj->chsum());
		}
	}
}

=head3 _deleteDataObject

Definition:
	void  _deleteDataObject(string:uuid);
Description:
	Deletes specified data object in database

=cut

sub _deleteDataObject {
	my ($self,$chsum) = @_;
	$self->_getDataObject($chsum,{throwErrorIfMissing => 1});
	$self->_mongodb()->workspaceDataObjects->remove({chsum => $chsum});
}

=head3 _clearAllWorkspaces

Definition:
	void  _clearAllWorkspaces();
Description:
	Clears all workspaces from the database

=cut

sub _clearAllWorkspaces {
	my ($self) = @_;
	$self->_mongodb()->workspaces->remove({});
}

=head3 _clearAllJobs

Definition:
	void  _clearAllJobs();
Description:
	Clears all jobs from the database

=cut

sub _clearAllJobs {
	my ($self) = @_;
	$self->_mongodb()->jobObjects->remove({});
}

=head3 _clearAllWorkspaceUsers

Definition:
	void  _clearAllWorkspaceUsers();
Description:
	Clears all workspace users from the database

=cut

sub _clearAllWorkspaceUsers {
	my ($self) = @_;
	$self->_mongodb()->workspaceUsers->remove({});
}

=head3 _clearAllWorkspaceObjects

Definition:
	void  _clearAllWorkspaceObjects();
Description:
	Clears all workspace objects from the database

=cut

sub _clearAllWorkspaceObjects {
	my ($self) = @_;
	$self->_mongodb()->workspaceObjects->remove({});
}

=head3 _clearAllWorkspaceDataObjects

Definition:
	void  _clearAllWorkspaceDataObjects();
Description:
	Clears all workspace data objects from the database

=cut

sub _clearAllWorkspaceDataObjects {
	my ($self) = @_;
	$self->_mongodb()->workspaceDataObjects->remove({});
}

#####################################################################
#Object retrieval methods
#####################################################################

=head3 _getWorkspaceUser

Definition:
	Bio::KBase::workspaceService::WorkspaceUser =  _getWorkspaceUser(string:id,{}:options);
Description:
	Retrieves specified WorkspaceUser in database

=cut

sub _getWorkspaceUser {
	my ($self,$id,$options) = @_;
	my $objs = $self->_getWorkspaceUsers([$id],$options);
	if (defined($objs->[0])) {
		return $objs->[0];
	}
	return undef;
}

=head3 _getWorkspaceUsers

Definition:
	[Bio::KBase::workspaceService::WorkspaceUser] =  _getWorkspaceUsers([string]:ids,{}:options);
Description:
	Returns list of requested workspace users

=cut

sub _getWorkspaceUsers {
	my ($self,$ids,$options) = @_;
    my $cursor = $self->_mongodb()->workspaceUsers->find({id => {'$in' => $ids} });
	my $objHash = {};
	while (my $object = $cursor->next) {
        my $newObject = Bio::KBase::workspaceService::WorkspaceUser->new({
			parent => $self,
			id => $object->{id},
			workspaces => $object->{workspaces},
			moddate => $object->{moddate},
		});
        $objHash->{$newObject->id()} = $newObject;
    }
    my $objects = [];
    for (my $i=0; $i < @{$ids}; $i++) {
    	if (defined($objHash->{$ids->[$i]})) {
    		push(@{$objects},$objHash->{$ids->[$i]});
    	} elsif ($options->{throwErrorIfMissing} == 1) {
    		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "WorkspaceUser ".$ids->[$i]." not found!",
							       method_name => '_getWorkspaceUsers');
    	} elsif ($options->{createIfMissing} == 1) {
    		push(@{$objects},$self->_createWorkspaceUser($ids->[$i]));
    	}
    }
	return $objects;
}

=head3 _getAllWorkspaceUsersByWorkspace

Definition:
	[Bio::KBase::workspaceService::WorkspaceUser] =  _getAllWorkspaceUsersByWorkspace(string:workspace);
Description:
	Returns list of all workspace users with specific permissions set for a workspace

=cut

sub _getAllWorkspaceUsersByWorkspace {
	my ($self,$id) = @_;
	my $key = "workspaces.".$id;
    my $cursor = $self->_mongodb()->workspaceUsers->find({$key => {'$in' => ["a","w","r","n"]} });
	my $objects = [];
	while (my $object = $cursor->next) {
        my $newObject = Bio::KBase::workspaceService::WorkspaceUser->new({
			parent => $self,
			id => $object->{id},
			workspaces => $object->{workspaces},
			moddate => $object->{moddate},
		});
        push(@{$objects},$newObject);
    }
	return $objects;
}

=head3 _getWorkspace

Definition:
	Bio::KBase::workspaceService::Workspace =  _getWorkspace(string:id,{}:options);
Description:
	Retrieves specified Workspace from database

=cut

sub _getWorkspace {
	my ($self,$id,$options) = @_;
	my $objs = $self->_getWorkspaces([$id],$options);
	if (defined($objs->[0])) {
		return $objs->[0];
	}
	return undef;
}

=head3 _getWorkspaces

Definition:
	[Bio::KBase::workspaceService::Workspace] =  _getWorkspaceUsers([string]:ids,{}:options);
Description:
	Retrieves specified Workspaces from database

=cut

sub _getWorkspaces {
	my ($self,$ids,$options) = @_;
	my $query = {id => {'$in' => $ids} };
	if (defined($options->{orQuery})) {
		my $list = [{id => {'$in' => $ids} }];
		push(@{$list},@{$options->{orQuery}});
		$query = { '$or' => $list };
	}
    my $cursor = $self->_mongodb()->workspaces->find($query);
	my $objHash = {};
	while (my $object = $cursor->next) {
        my $newObject = Bio::KBase::workspaceService::Workspace->new({
			parent => $self,
			id => $object->{id},
			owner => $object->{owner},
			defaultPermissions => $object->{defaultPermissions},
			objects => $object->{objects},
			moddate => $object->{moddate}
		}); 
        $objHash->{$newObject->id()} = $newObject;
    }
    my $objects = [];
    for (my $i=0; $i < @{$ids}; $i++) {
    	if (defined($objHash->{$ids->[$i]})) {
    		push(@{$objects},$objHash->{$ids->[$i]});
    		delete $objHash->{$ids->[$i]};
    	} elsif ($options->{throwErrorIfMissing} == 1) {
    		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Workspace ".$ids->[$i]." not found!",
							       method_name => '_getWorkspaces');
    	}
    }
    if (defined($options->{orQuery})) {
    	foreach my $key (keys(%{$objHash})) {
    		push(@{$objects},$objHash->{$key});
    	}
    } 
	return $objects;
}



=head3 _getObjectByChsum

Definition:
	Bio::KBase::workspaceService::Object =  _getObjectByChsum(string:chsum,{}:options);
Description:
	Retrieves specified Object from database

=cut

sub _getObjectByChsum {
	my ($self,$chsum,$options) = @_;
	my $objs = $self->_getObjectByChsums([$chsum],$options);
	if (defined($objs->[0])) {
		return $objs->[0];
	}
	return undef;
}

=head3 _getObjectByChsums

Definition:
	[Bio::KBase::workspaceService::Object] =  _getObjectByChsums([string]:chsums,{}:options);
Description:
	Retrieves specified DataObjects from database

=cut

sub _getObjectByChsums {
	my ($self,$chsums,$options) = @_;
    my $cursor = $self->_mongodb()->workspaceObjects->find({chsum => {'$in' => $chsums} });
	my $objHash = {};
	while (my $object = $cursor->next) {
        my $newObject = Bio::KBase::workspaceService::Object->new({
			parent => $self,
			uuid => $object->{uuid},
			id => $object->{id},
			workspace => $object->{workspace},
			type => $object->{type},
			ancestor => $object->{ancestor},
			revertAncestors => $object->{revertAncestors},
			owner => $object->{owner},
			lastModifiedBy => $object->{lastModifiedBy},
			command => $object->{command},
			instance => $object->{instance},
			chsum => $object->{chsum},
			meta => $object->{meta},
			moddate => $object->{moddate}
        });
        $objHash->{$newObject->chsum()} = $newObject;
    }
    my $objects = [];
    for (my $i=0; $i < @{$chsums}; $i++) {
    	if (defined($objHash->{$chsums->[$i]})) {
    		push(@{$objects},$objHash->{$chsums->[$i]});
    	} elsif ($options->{throwErrorIfMissing} == 1) {
    		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Object ".$chsums->[$i]." not found!",
							       method_name => '_getObjects');
    	}
    }
	return $objects;
}

=head3 _getObject

Definition:
	Bio::KBase::workspaceService::Object =  _getObject([string]:ids,{}:options);
Description:
	Retrieves specified Object from database

=cut

sub _getObject {
	my ($self,$id,$options) = @_;
	my $objs = $self->_getObjects([$id],$options);
	if (defined($objs->[0])) {
		return $objs->[0];
	}
	return undef;
}

=head3 _getObjects

Definition:
	[Bio::KBase::workspaceService::Object] =  _getObjects([string]:ids,{}:options);
Description:
	Retrieves specified Objects from database

=cut

sub _getObjects {
	my ($self,$ids,$options) = @_;
    my $cursor = $self->_mongodb()->workspaceObjects->find({uuid => {'$in' => $ids} });
	my $objHash = {};
	while (my $object = $cursor->next) {
        my $newObject = Bio::KBase::workspaceService::Object->new({
			parent => $self,
			uuid => $object->{uuid},
			id => $object->{id},
			workspace => $object->{workspace},
			type => $object->{type},
			ancestor => $object->{ancestor},
			revertAncestors => $object->{revertAncestors},
			owner => $object->{owner},
			lastModifiedBy => $object->{lastModifiedBy},
			command => $object->{command},
			instance => $object->{instance},
			chsum => $object->{chsum},
			meta => $object->{meta},
			moddate => $object->{moddate}
        });
        $objHash->{$newObject->uuid()} = $newObject;
    }
    my $objects = [];
    for (my $i=0; $i < @{$ids}; $i++) {
    	if (defined($objHash->{$ids->[$i]})) {
    		push(@{$objects},$objHash->{$ids->[$i]});
    	} elsif ($options->{throwErrorIfMissing} == 1) {
    		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Object ".$ids->[$i]." not found!",
							       method_name => '_getObjects');
    	}
    }
	return $objects;
}

=head3 _getObjectByID

Definition:
	Bio::KBase::workspaceService::Object = _getObjectByID(string:id,string:type,string:workspace,int:instance,{}:options);
Description:
	Retrieves specified Objects from database by ID, type, and instance

=cut

sub _getObjectByID {
	my ($self,$id,$type,$workspace,$instance,$options) = @_;
    my $cursor = $self->_mongodb()->workspaceObjects->find({
    	id => $id,
    	type => $type,
    	workspace => $workspace,
    	instance => $instance
    });
	while (my $object = $cursor->next) {
        my $newObject = Bio::KBase::workspaceService::Object->new({
			parent => $self,
			uuid => $object->{uuid},
			id => $object->{id},
			workspace => $object->{workspace},
			type => $object->{type},
			ancestor => $object->{ancestor},
			revertAncestors => $object->{revertAncestors},
			owner => $object->{owner},
			lastModifiedBy => $object->{lastModifiedBy},
			command => $object->{command},
			instance => $object->{instance},
			chsum => $object->{chsum},
			meta => $object->{meta},
			moddate => $object->{moddate}
        });
        return $newObject;
    }
    if ($options->{throwErrorIfMissing} == 1) {
    	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Object not found with specified ".$workspace."/".$type."/".$id.".V".$instance."!",method_name => '_getObjectByID');
    }
	return undef;
}

=head3 _getObjectsByID

Definition:
	[Bio::KBase::workspaceService::Object] = _getObjectsByID(string:id,string:type,string:workspace,{}:options);
Description:
	Retrieves objects from database by ID and type

=cut

sub _getObjectsByID {
	my ($self,$id,$type,$workspace,$options) = @_;
    my $cursor = $self->_mongodb()->workspaceObjects->find({
    	id => $id,
    	type => $type,
    	workspace => $workspace
    });
    my $objects = [];
	while (my $object = $cursor->next) {
        my $newObject = Bio::KBase::workspaceService::Object->new({
			parent => $self,
			uuid => $object->{uuid},
			id => $object->{id},
			workspace => $object->{workspace},
			type => $object->{type},
			ancestor => $object->{ancestor},
			revertAncestors => $object->{revertAncestors},
			owner => $object->{owner},
			lastModifiedBy => $object->{lastModifiedBy},
			command => $object->{command},
			instance => $object->{instance},
			chsum => $object->{chsum},
			meta => $object->{meta},
			moddate => $object->{moddate}
        });
        $objects->[$newObject->instance()] = $newObject;
    }
	return $objects;
}

=head3 _getDataObject

Definition:
	Bio::KBase::workspaceService::DataObject =  _getDataObject(string:chsum,{}:options);
Description:
	Retrieves specified DataObject from database

=cut

sub _getDataObject {
	my ($self,$chsum,$options) = @_;
	my $objs = $self->_getDataObjects([$chsum],$options);
	if (defined($objs->[0])) {
		return $objs->[0];
	}
	return undef;
}

=head3 _getDataObjects

Definition:
	[Bio::KBase::workspaceService::DataObject] =  _getObjects([string]:chsums,{}:options);
Description:
	Retrieves specified DataObjects from database

=cut

sub _getDataObjects {
	my ($self,$chsums,$options) = @_;
    my $cursor = $self->_mongodb()->workspaceDataObjects->find({chsum => {'$in' => $chsums} });
	my $objHash = {};
	while (my $object = $cursor->next) {
        my $newObject = Bio::KBase::workspaceService::DataObject->new({
        	parent => $self,
        	compressed => $object->{compressed},
			json => $object->{json},
			chsum => $object->{chsum},
			data => $object->{data},
			creationDate => $object->{creationDate}	
		});
        $objHash->{$newObject->chsum()} = $newObject;
    }
    my $objects = [];
    for (my $i=0; $i < @{$chsums}; $i++) {
    	if (defined($objHash->{$chsums->[$i]})) {
    		push(@{$objects},$objHash->{$chsums->[$i]});
    	} elsif ($options->{throwErrorIfMissing} == 1) {
    		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "DataObject ".$chsums->[$i]." not found!",
							       method_name => '_getDataObjects');
    	}
    }
	return $objects;
}

#####################################################################
#Data validation methods
#####################################################################

sub _validateWorkspaceID {
	my ($self,$id) = @_;
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Workspace name must contain only alphanumeric characters!",
		method_name => '_validateWorkspaceID') if ($id !~ m/^\w+$/);
}

sub _validateUserID {
	my ($self,$id) = @_;
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Username must contain only alphanumeric characters!",
		method_name => '_validateUserID') if ($id !~ m/^\w+$/);
}

sub _validateObjectID {
	my ($self,$id) = @_;
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Object ID failed validation!",
		method_name => '_validateUserID') if ($id !~ m/^.+$/);
}

sub _validatePermission {
	my ($self,$permission) = @_;
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Specified permission not valid!",
		method_name => '_validateWorkspaceID') if ($permission !~ m/^[awrn]$/);
}

sub _validateObjectType {
	my ($self,$type) = @_;
	my $types = $self->_permanentTypes();
	if (defined($types->{$type})) {
		return;
	}
	my $cursor = $self->_mongodb()->typeObjects->find({id => $type});
    if (my $object = $cursor->next) {
		return;
    }
    my $msg = "Specified type not valid!";
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => '_validateObjectType');
}

sub _permanentTypes {
	return {
		Genome => 1,
		Unspecified => 1,
		TestData => 1,
		Biochemistry => 1,
		Model => 1,
		Mapping => 1,
		Annotation => 1,
        FBA => 1,
        Media => 1,
        PhenotypeSet => 1,
        PhenotypeSimulationSet => 1,
        FBAJob => 1,
        GapFill => 1,
        GapGen => 1,
        PROMModel => 1,
        ProbAnno => 1
	};
}

sub _validateargs {
	my ($self,$args,$mandatoryArguments,$optionalArguments,$substitutions) = @_;
	if (!defined($args)) {
	    $args = {};
	}
	if (ref($args) ne "HASH") {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Arguments not hash",
		method_name => '_validateargs');	
	}
	if (defined($substitutions) && ref($substitutions) eq "HASH") {
		foreach my $original (keys(%{$substitutions})) {
			$args->{$original} = $args->{$substitutions->{$original}};
		}
	}
	if (defined($mandatoryArguments)) {
		for (my $i=0; $i < @{$mandatoryArguments}; $i++) {
			if (!defined($args->{$mandatoryArguments->[$i]})) {
				push(@{$args->{_error}},$mandatoryArguments->[$i]);
			}
		}
	}
	if (defined($args->{_error})) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Mandatory arguments ".join("; ",@{$args->{_error}})." missing.",
		method_name => '_validateargs');
	}
	if (defined($optionalArguments)) {
		foreach my $argument (keys(%{$optionalArguments})) {
			if (!defined($args->{$argument})) {
				$args->{$argument} = $optionalArguments->{$argument};
			}
		}	
	}
	return $args;
}

sub _retreiveDataFromURL {
	my ($self,$data) = @_;
	my ($fh, $uncompressed_filename) = tempfile();
	close($fh);
	my $status = getstore($data, $uncompressed_filename);
	die "Unable to fetch object from URL!\n" unless($status == 200);
	local $/;
	open($fh, "<", $uncompressed_filename) || die "$!: $@";
	my $string = <$fh>;
	close($fh);
	return $string;
}

sub _uncompress {
	my ($self,$data) = @_;
	my $datastring;
	gunzip \$data => \$datastring;
	return $datastring;
}

sub _decode {
	my ($self,$data) = @_;
	return JSON::XS->new->decode($data);	
} 

#END_HEADER

sub new
{
    my($class, @args) = @_;
    my $self = {
    };
    bless $self, $class;
    #BEGIN_CONSTRUCTOR
    my $options = $args[0];
    if (defined($options->{testuser})) {
    	$self->{_testuser} = $options->{testuser};
    }
    my $config = "sample.ini";
    if (defined($ENV{KB_DEPLOYMENT_CONFIG})) {
    	$config = $ENV{KB_DEPLOYMENT_CONFIG};
	} else {
		warn "No deployment config specified. Using 'sample.ini' by default!\n";
	}
	if (!-e $config) {
		warn "Deployment config file not found. Using default settings!\n";
		$self->{_host} = "localhost";
		$self->{_db} = "workspace_service";
	} else {
		my $c = new Config::Simple($config);
		$self->{_host} = $c->param("workspaceServices.mongodb-hostname");
		$self->{_db}   = $c->param("workspaceServices.mongodb-database");
	}
    #END_CONSTRUCTOR

    if ($self->can('_init_instance'))
    {
	$self->_init_instance();
    }
    return $self;
}

=head1 METHODS



=head2 save_object

  $metadata = $obj->save_object($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a save_object_params
$metadata is an object_metadata
save_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	data has a value which is an ObjectData
	workspace has a value which is a workspace_id
	command has a value which is a string
	metadata has a value which is a reference to a hash where the key is a string and the value is a string
	auth has a value which is a string
	json has a value which is a bool
	compressed has a value which is a bool
	retrieveFromURL has a value which is a bool
object_id is a string
object_type is a string
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a save_object_params
$metadata is an object_metadata
save_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	data has a value which is an ObjectData
	workspace has a value which is a workspace_id
	command has a value which is a string
	metadata has a value which is a reference to a hash where the key is a string and the value is a string
	auth has a value which is a string
	json has a value which is a bool
	compressed has a value which is a bool
	retrieveFromURL has a value which is a bool
object_id is a string
object_type is a string
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text



=item Description

Saves the input object data and metadata into the selected workspace, returning the object_metadata of the saved object

=back

=cut

sub save_object
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to save_object:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'save_object');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN save_object
    $self->_setContext($ctx,$params);
    $params = $self->_validateargs($params,["id","type","data","workspace"],{
    	command => undef,
    	metadata => {},
    	json => 0,
    	compressed => 0,
    	retrieveFromURL => 0
    });
    if ($params->{retrieveFromURL} == 1) {
    	$params->{data} = $self->_retreiveDataFromURL($params->{data});
    }
    if ($params->{compressed} == 1) {
    	$params->{data} = $self->_uncompress($params->{data});
    }
    if ($params->{json} == 1) {
    	$params->{data} = $self->_decode($params->{data});
    }
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    my $obj = $ws->saveObject($params->{type},$params->{id},$params->{data},$params->{command},$params->{metadata});
    $metadata = $obj->metadata();
	$self->_clearContext();
    #END save_object
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to save_object:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'save_object');
    }
    return($metadata);
}




=head2 delete_object

  $metadata = $obj->delete_object($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a delete_object_params
$metadata is an object_metadata
delete_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a delete_object_params
$metadata is an object_metadata
delete_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text



=item Description

Deletes the specified object from the specified workspace, returning the object_metadata of the deleted object.
Object is only temporarily deleted and can be recovered by using the revert command.

=back

=cut

sub delete_object
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to delete_object:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'delete_object');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN delete_object
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["id","type","workspace"],{});
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    my $obj = $ws->deleteObject($params->{type},$params->{id});
    $metadata = $obj->metadata();
    $self->_clearContext();
    #END delete_object
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to delete_object:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'delete_object');
    }
    return($metadata);
}




=head2 delete_object_permanently

  $metadata = $obj->delete_object_permanently($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a delete_object_permanently_params
$metadata is an object_metadata
delete_object_permanently_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a delete_object_permanently_params
$metadata is an object_metadata
delete_object_permanently_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text



=item Description

Permanently deletes the specified object from the specified workspace.
This permanently deletes the object and object history, and the data cannot be recovered.
Objects cannot be permanently deleted unless they've been deleted first.

=back

=cut

sub delete_object_permanently
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to delete_object_permanently:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'delete_object_permanently');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN delete_object_permanently
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["id","type","workspace"],{});
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    my $obj = $ws->deleteObjectPermanently($params->{type},$params->{id});
    $metadata = $obj->metadata();
    $self->_clearContext();
    #END delete_object_permanently
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to delete_object_permanently:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'delete_object_permanently');
    }
    return($metadata);
}




=head2 get_object

  $output = $obj->get_object($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_object_params
$output is a get_object_output
get_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	instance has a value which is an int
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
get_object_output is a reference to a hash where the following keys are defined:
	data has a value which is an ObjectData
	metadata has a value which is an object_metadata
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a get_object_params
$output is a get_object_output
get_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	instance has a value which is an int
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
get_object_output is a reference to a hash where the following keys are defined:
	data has a value which is an ObjectData
	metadata has a value which is an object_metadata
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text



=item Description

Retrieves the specified object from the specified workspace.
Both the object data and metadata are returned.
This commands provides access to all versions of the object via the instance parameter.

=back

=cut

sub get_object
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to get_object:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_object');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($output);
    #BEGIN get_object
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["id","type","workspace"],{
    	instance => undef
    });
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    my $obj = $ws->getObject($params->{type},$params->{id},{
    	throwErrorIfMissing => 1,
    	instance => $params->{instance}
    });
    $output = {
    	data => $obj->data(),
    	metadata => $obj->metadata()
    };
    $self->_clearContext();
    #END get_object
    my @_bad_returns;
    (ref($output) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_object:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_object');
    }
    return($output);
}




=head2 get_objectmeta

  $metadata = $obj->get_objectmeta($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_objectmeta_params
$metadata is an object_metadata
get_objectmeta_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	instance has a value which is an int
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a get_objectmeta_params
$metadata is an object_metadata
get_objectmeta_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	instance has a value which is an int
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text



=item Description

Retrieves the metadata for a specified object from the specified workspace.
This commands provides access to metadata for all versions of the object via the instance parameter.

=back

=cut

sub get_objectmeta
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to get_objectmeta:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_objectmeta');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN get_objectmeta
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["id","type","workspace"],{
    	instance => undef
    });
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    my $obj = $ws->getObject($params->{type},$params->{id},{
    	throwErrorIfMissing => 1,
    	instance => $params->{instance}
    });
    $metadata = $obj->metadata();
    $self->_clearContext();
    #END get_objectmeta
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_objectmeta:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_objectmeta');
    }
    return($metadata);
}




=head2 revert_object

  $metadata = $obj->revert_object($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a revert_object_params
$metadata is an object_metadata
revert_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	instance has a value which is an int
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a revert_object_params
$metadata is an object_metadata
revert_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	instance has a value which is an int
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text



=item Description

Reverts a specified object in a specifed workspace to a previous version of the object.
Returns the metadata of the newly reverted object.
This command still makes a new instance of the object, copying data related to the target instance to the new instance.
This ensures that the object instance always increases and no portion of the object history is ever lost.

=back

=cut

sub revert_object
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to revert_object:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'revert_object');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN revert_object
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["id","type","workspace"],{
    	instance => undef
    });
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    my $obj = $ws->revertObject($params->{type},$params->{id},$params->{instance});
    $metadata = $obj->metadata();
    $self->_clearContext();
    #END revert_object
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to revert_object:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'revert_object');
    }
    return($metadata);
}




=head2 copy_object

  $metadata = $obj->copy_object($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a copy_object_params
$metadata is an object_metadata
copy_object_params is a reference to a hash where the following keys are defined:
	new_id has a value which is an object_id
	new_workspace has a value which is a workspace_id
	source_id has a value which is an object_id
	instance has a value which is an int
	type has a value which is an object_type
	source_workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
workspace_id is a string
object_type is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a copy_object_params
$metadata is an object_metadata
copy_object_params is a reference to a hash where the following keys are defined:
	new_id has a value which is an object_id
	new_workspace has a value which is a workspace_id
	source_id has a value which is an object_id
	instance has a value which is an int
	type has a value which is an object_type
	source_workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
workspace_id is a string
object_type is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text



=item Description

Copies a specified object in a specifed workspace to a new ID and/or workspace.
Returns the metadata of the newly copied object.
It is possible to use the version parameter to copy any version of a workspace object.

=back

=cut

sub copy_object
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to copy_object:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'copy_object');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN copy_object
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["new_id","new_workspace","source_id","type","source_workspace"],{
    	instance => undef
    });
    my $ws = $self->_getWorkspace($params->{source_workspace},{throwErrorIfMissing => 1});
    my $obj = $ws->getObject($params->{type},$params->{source_id},{
    	throwErrorIfMissing => 1,
    	instance => $params->{instance}
    });
    if ($params->{new_workspace} ne $params->{source_workspace}) {
    	$ws = $self->_getWorkspace($params->{new_workspace},{throwErrorIfMissing => 1});
    	$obj = $ws->saveObject($params->{type},$params->{new_id},$obj->data(),"copy_object",$obj->meta());
    	$metadata = $obj->metadata();
    } elsif ($params->{new_id} eq $params->{source_id}) {
    	$metadata = $obj->metadata();
    } else {
    	$obj = $ws->saveObject($params->{type},$params->{new_id},$obj->data(),"copy_object",$obj->meta());
    	$metadata = $obj->metadata();
    }
    $self->_clearContext();
    #END copy_object
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to copy_object:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'copy_object');
    }
    return($metadata);
}




=head2 move_object

  $metadata = $obj->move_object($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a move_object_params
$metadata is an object_metadata
move_object_params is a reference to a hash where the following keys are defined:
	new_id has a value which is an object_id
	new_workspace has a value which is a workspace_id
	source_id has a value which is an object_id
	type has a value which is an object_type
	source_workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
workspace_id is a string
object_type is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a move_object_params
$metadata is an object_metadata
move_object_params is a reference to a hash where the following keys are defined:
	new_id has a value which is an object_id
	new_workspace has a value which is a workspace_id
	source_id has a value which is an object_id
	type has a value which is an object_type
	source_workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
workspace_id is a string
object_type is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text



=item Description

Moves a specified object in a specifed workspace to a new ID and/or workspace.
Returns the metadata of the newly moved object.

=back

=cut

sub move_object
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to move_object:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'move_object');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN move_object
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["new_id","new_workspace","source_id","type","source_workspace"],{});
    my $ws = $self->_getWorkspace($params->{source_workspace},{throwErrorIfMissing => 1});
    my $obj = $ws->getObject($params->{type},$params->{source_id},{
    	throwErrorIfMissing => 1
    });
    if ($params->{new_workspace} ne $params->{source_workspace}) {
    	$ws->deleteObject($params->{type},$params->{source_id});
    	$ws = $self->_getWorkspace($params->{new_workspace},{throwErrorIfMissing => 1});
    	$obj = $ws->saveObject($params->{type},$params->{new_id},$obj->data(),"move_object",$obj->meta());
    	$metadata = $obj->metadata();
    } elsif ($params->{new_id} eq $params->{source_id}) {
    	$metadata = $obj->metadata();
    } else {
    	$ws->deleteObject($params->{type},$params->{source_id});
    	$obj = $ws->saveObject($params->{type},$params->{new_id},$obj->data(),"move_object",$obj->meta());
    	$metadata = $obj->metadata();
    }
    $self->_clearContext();
    #END move_object
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to move_object:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'move_object');
    }
    return($metadata);
}




=head2 has_object

  $object_present = $obj->has_object($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a has_object_params
$object_present is a bool
has_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	instance has a value which is an int
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
bool is an int

</pre>

=end html

=begin text

$params is a has_object_params
$object_present is a bool
has_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	instance has a value which is an int
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
bool is an int


=end text



=item Description

Checks if a specified object in a specifed workspace exists.
Returns "1" if the object exists, "0" if not

=back

=cut

sub has_object
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to has_object:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'has_object');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($object_present);
    #BEGIN has_object
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["id","type","workspace"],{
    	instance => undef
    });
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    my $obj = $ws->getObject($params->{type},$params->{id},{
    	throwErrorIfMissing => 0,
    	instance => $params->{instance}
    });
    $object_present = 1;
    if (!defined($obj)) {
    	$object_present = 0;
    }
    $self->_clearContext();
    #END has_object
    my @_bad_returns;
    (!ref($object_present)) or push(@_bad_returns, "Invalid type for return variable \"object_present\" (value was \"$object_present\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to has_object:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'has_object');
    }
    return($object_present);
}




=head2 object_history

  $metadatas = $obj->object_history($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is an object_history_params
$metadatas is a reference to a list where each element is an object_metadata
object_history_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is an object_history_params
$metadatas is a reference to a list where each element is an object_metadata
object_history_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text



=item Description

Returns the metadata associated with every version of a specified object in a specified workspace.

=back

=cut

sub object_history
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to object_history:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'object_history');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadatas);
    #BEGIN object_history
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["id","type","workspace"],{});
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    my $history = $ws->getObjectHistory($params->{type},$params->{id});
    for (my $i=0; $i < @{$history}; $i++) {
    	$metadatas->[$history->[$i]->instance()] = $history->[$i]->metadata();
    }
    $self->_clearContext();
    #END object_history
    my @_bad_returns;
    (ref($metadatas) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadatas\" (value was \"$metadatas\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to object_history:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'object_history');
    }
    return($metadatas);
}




=head2 create_workspace

  $metadata = $obj->create_workspace($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a create_workspace_params
$metadata is a workspace_metadata
create_workspace_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	default_permission has a value which is a permission
	auth has a value which is a string
workspace_id is a string
permission is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string

</pre>

=end html

=begin text

$params is a create_workspace_params
$metadata is a workspace_metadata
create_workspace_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	default_permission has a value which is a permission
	auth has a value which is a string
workspace_id is a string
permission is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string


=end text



=item Description

Creates a new workspace with the specified name and default permissions.

=back

=cut

sub create_workspace
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to create_workspace:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'create_workspace');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN create_workspace
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["workspace"],{
    	default_permission => "n"
    });
    my $ws = $self->_getWorkspace($params->{workspace});
    if (defined($ws)) {
    	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Cannot create workspace because workspace already exists!",
		method_name => 'create_workspace');
    }
    $ws = $self->_createWorkspace($params->{workspace},$params->{default_permission});
    $metadata = $ws->metadata();
    $self->_clearContext();
    #END create_workspace
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to create_workspace:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'create_workspace');
    }
    return($metadata);
}




=head2 get_workspacemeta

  $metadata = $obj->get_workspacemeta($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_workspacemeta_params
$metadata is a workspace_metadata
get_workspacemeta_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	auth has a value which is a string
workspace_id is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string
permission is a string

</pre>

=end html

=begin text

$params is a get_workspacemeta_params
$metadata is a workspace_metadata
get_workspacemeta_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	auth has a value which is a string
workspace_id is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string
permission is a string


=end text



=item Description

Retreives the metadata associated with the specified workspace.

=back

=cut

sub get_workspacemeta
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to get_workspacemeta:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_workspacemeta');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN get_workspacemeta
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["workspace"],{});
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
	$metadata = $ws->metadata();
    $self->_clearContext();
    #END get_workspacemeta
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_workspacemeta:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_workspacemeta');
    }
    return($metadata);
}




=head2 get_workspacepermissions

  $user_permissions = $obj->get_workspacepermissions($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_workspacepermissions_params
$user_permissions is a reference to a hash where the key is a username and the value is a permission
get_workspacepermissions_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	auth has a value which is a string
workspace_id is a string
username is a string
permission is a string

</pre>

=end html

=begin text

$params is a get_workspacepermissions_params
$user_permissions is a reference to a hash where the key is a username and the value is a permission
get_workspacepermissions_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	auth has a value which is a string
workspace_id is a string
username is a string
permission is a string


=end text



=item Description

Retreives a list of all users with custom permissions to the workspace.

=back

=cut

sub get_workspacepermissions
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to get_workspacepermissions:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_workspacepermissions');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($user_permissions);
    #BEGIN get_workspacepermissions
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["workspace"],{});
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
	$user_permissions = $ws->getWorkspaceUserPermissions();
    $self->_clearContext();
    #END get_workspacepermissions
    my @_bad_returns;
    (ref($user_permissions) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"user_permissions\" (value was \"$user_permissions\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_workspacepermissions:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_workspacepermissions');
    }
    return($user_permissions);
}




=head2 delete_workspace

  $metadata = $obj->delete_workspace($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a delete_workspace_params
$metadata is a workspace_metadata
delete_workspace_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	auth has a value which is a string
workspace_id is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string
permission is a string

</pre>

=end html

=begin text

$params is a delete_workspace_params
$metadata is a workspace_metadata
delete_workspace_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	auth has a value which is a string
workspace_id is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string
permission is a string


=end text



=item Description

Deletes a specified workspace with all objects.

=back

=cut

sub delete_workspace
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to delete_workspace:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'delete_workspace');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN delete_workspace
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["workspace"],{});
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    $ws->permanentDelete();
    $metadata = $ws->metadata();
    $self->_clearContext();
    #END delete_workspace
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to delete_workspace:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'delete_workspace');
    }
    return($metadata);
}




=head2 clone_workspace

  $metadata = $obj->clone_workspace($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a clone_workspace_params
$metadata is a workspace_metadata
clone_workspace_params is a reference to a hash where the following keys are defined:
	new_workspace has a value which is a workspace_id
	current_workspace has a value which is a workspace_id
	default_permission has a value which is a permission
	auth has a value which is a string
workspace_id is a string
permission is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string

</pre>

=end html

=begin text

$params is a clone_workspace_params
$metadata is a workspace_metadata
clone_workspace_params is a reference to a hash where the following keys are defined:
	new_workspace has a value which is a workspace_id
	current_workspace has a value which is a workspace_id
	default_permission has a value which is a permission
	auth has a value which is a string
workspace_id is a string
permission is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string


=end text



=item Description

Copies a specified workspace with all objects.

=back

=cut

sub clone_workspace
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to clone_workspace:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'clone_workspace');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN clone_workspace
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["new_workspace","current_workspace"],{
    	default_permissions => "n"
    });
    my $ws = $self->_getWorkspace($params->{current_workspace},{throwErrorIfMissing => 1});
    my $objs = $ws->getAllObjects();
    $ws = $self->_getWorkspace($params->{new_workspace});
    if (!defined($ws)) {
    	$ws = $self->_createWorkspace($params->{new_workspace},$params->{default_permission});
    }
    for (my $i=0; $i < @{$objs}; $i++) {
    	my $obj = $objs->[$i];
    	$ws->saveObject($obj->type(),$obj->id(),"CHSUM:".$obj->chsum(),$obj->command(),$obj->meta());
    }
    $metadata = $ws->metadata();
    $self->_clearContext();
    #END clone_workspace
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to clone_workspace:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'clone_workspace');
    }
    return($metadata);
}




=head2 list_workspaces

  $workspaces = $obj->list_workspaces($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a list_workspaces_params
$workspaces is a reference to a list where each element is a workspace_metadata
list_workspaces_params is a reference to a hash where the following keys are defined:
	auth has a value which is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
workspace_id is a string
username is a string
timestamp is a string
permission is a string

</pre>

=end html

=begin text

$params is a list_workspaces_params
$workspaces is a reference to a list where each element is a workspace_metadata
list_workspaces_params is a reference to a hash where the following keys are defined:
	auth has a value which is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
workspace_id is a string
username is a string
timestamp is a string
permission is a string


=end text



=item Description

Lists the metadata of all workspaces a user has access to.

=back

=cut

sub list_workspaces
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_workspaces:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_workspaces');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($workspaces);
    #BEGIN list_workspaces
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,[],{});
    #Getting user-specific permissions
    my $wsu = $self->_getWorkspaceUser($self->_getUsername());
    if (!defined($wsu)) {
    	$wsu = $self->_createWorkspaceUser($self->_getUsername());
    }
    my $wss = $wsu->getUserWorkspaces();
    $workspaces = [];
    for (my $i=0; $i < @{$wss}; $i++) {
    	push(@{$workspaces},$wss->[$i]->metadata());
    }
    $self->_clearContext();
    #END list_workspaces
    my @_bad_returns;
    (ref($workspaces) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"workspaces\" (value was \"$workspaces\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_workspaces:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_workspaces');
    }
    return($workspaces);
}




=head2 list_workspace_objects

  $objects = $obj->list_workspace_objects($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a list_workspace_objects_params
$objects is a reference to a list where each element is an object_metadata
list_workspace_objects_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	type has a value which is a string
	showDeletedObject has a value which is a bool
	auth has a value which is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
object_id is a string
object_type is a string
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a list_workspace_objects_params
$objects is a reference to a list where each element is an object_metadata
list_workspace_objects_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	type has a value which is a string
	showDeletedObject has a value which is a bool
	auth has a value which is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
object_id is a string
object_type is a string
timestamp is a string
username is a string
workspace_ref is a string


=end text



=item Description

Lists the metadata of all objects in the specified workspace with the specified type (or with any type).

=back

=cut

sub list_workspace_objects
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_workspace_objects:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_workspace_objects');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($objects);
    #BEGIN list_workspace_objects
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["workspace"],{
    	type => undef,
    	showDeletedObject => 0
    });
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
	$objects = [];
	my $objs = $ws->getAllObjects($params->{type});    
	foreach my $obj (@{$objs}) {
		if ($obj->command() ne "delete" || $params->{showDeletedObject} == 1) {
			push(@{$objects},$obj->metadata());
		}
	}
	$self->_clearContext();
    #END list_workspace_objects
    my @_bad_returns;
    (ref($objects) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"objects\" (value was \"$objects\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_workspace_objects:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_workspace_objects');
    }
    return($objects);
}




=head2 set_global_workspace_permissions

  $metadata = $obj->set_global_workspace_permissions($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a set_global_workspace_permissions_params
$metadata is a workspace_metadata
set_global_workspace_permissions_params is a reference to a hash where the following keys are defined:
	new_permission has a value which is a permission
	workspace has a value which is a workspace_id
	auth has a value which is a string
permission is a string
workspace_id is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string

</pre>

=end html

=begin text

$params is a set_global_workspace_permissions_params
$metadata is a workspace_metadata
set_global_workspace_permissions_params is a reference to a hash where the following keys are defined:
	new_permission has a value which is a permission
	workspace has a value which is a workspace_id
	auth has a value which is a string
permission is a string
workspace_id is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string


=end text



=item Description

Sets the default permissions for accessing a specified workspace for all users.
Must have admin privelages to change workspace global permissions.

=back

=cut

sub set_global_workspace_permissions
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to set_global_workspace_permissions:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'set_global_workspace_permissions');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN set_global_workspace_permissions
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["new_permission","workspace"],{});
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    $ws->setDefaultPermissions($params->{new_permission});
    $metadata = $ws->metadata();
    $self->_clearContext();
    #END set_global_workspace_permissions
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to set_global_workspace_permissions:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'set_global_workspace_permissions');
    }
    return($metadata);
}




=head2 set_workspace_permissions

  $success = $obj->set_workspace_permissions($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a set_workspace_permissions_params
$success is a bool
set_workspace_permissions_params is a reference to a hash where the following keys are defined:
	users has a value which is a reference to a list where each element is a username
	new_permission has a value which is a permission
	workspace has a value which is a workspace_id
	auth has a value which is a string
username is a string
permission is a string
workspace_id is a string
bool is an int

</pre>

=end html

=begin text

$params is a set_workspace_permissions_params
$success is a bool
set_workspace_permissions_params is a reference to a hash where the following keys are defined:
	users has a value which is a reference to a list where each element is a username
	new_permission has a value which is a permission
	workspace has a value which is a workspace_id
	auth has a value which is a string
username is a string
permission is a string
workspace_id is a string
bool is an int


=end text



=item Description

Sets the permissions for a list of users for accessing a specified workspace.
Must have admin privelages to change workspace permissions.

=back

=cut

sub set_workspace_permissions
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to set_workspace_permissions:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'set_workspace_permissions');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($success);
    #BEGIN set_workspace_permissions
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["users","new_permission","workspace"],{});
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    $ws->setUserPermissions($params->{users},$params->{new_permission});
	$success = 1;
	$self->_clearContext();  
    #END set_workspace_permissions
    my @_bad_returns;
    (!ref($success)) or push(@_bad_returns, "Invalid type for return variable \"success\" (value was \"$success\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to set_workspace_permissions:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'set_workspace_permissions');
    }
    return($success);
}




=head2 queue_job

  $success = $obj->queue_job($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a queue_job_params
$success is a bool
queue_job_params is a reference to a hash where the following keys are defined:
	jobid has a value which is a string
	jobws has a value which is a string
	auth has a value which is a string
bool is an int

</pre>

=end html

=begin text

$params is a queue_job_params
$success is a bool
queue_job_params is a reference to a hash where the following keys are defined:
	jobid has a value which is a string
	jobws has a value which is a string
	auth has a value which is a string
bool is an int


=end text



=item Description

Queues a new job in the workspace.
Workspace job queues handles jobs that don't get submitted to large clusters.

=back

=cut

sub queue_job
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to queue_job:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'queue_job');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($success);
    #BEGIN queue_job
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["jobid","jobws"],{});
    #Checking that job doesn't already exist
    my $cursor = $self->_mongodb()->jobObjects->find({id => $params->{jobid},ws => $params->{jobws}});
    if (my $object = $cursor->next) {
    	my $msg = "Trying to queue job that already exists!";
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => 'queue_job');
    }
    #Inserting jobs in database
    $self->_mongodb()->jobObjects->insert({
		id => $params->{jobid},
		ws => $params->{jobws},
		auth => $params->{auth},
		status => "queued",
		queuetime => time(),
		owner => $self->_getUsername()
    });
    $success = 1;
	$self->_clearContext();  
    #END queue_job
    my @_bad_returns;
    (!ref($success)) or push(@_bad_returns, "Invalid type for return variable \"success\" (value was \"$success\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to queue_job:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'queue_job');
    }
    return($success);
}




=head2 set_job_status

  $success = $obj->set_job_status($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a set_job_status_params
$success is a bool
set_job_status_params is a reference to a hash where the following keys are defined:
	jobid has a value which is a string
	jobws has a value which is a string
	status has a value which is a string
	auth has a value which is a string
bool is an int

</pre>

=end html

=begin text

$params is a set_job_status_params
$success is a bool
set_job_status_params is a reference to a hash where the following keys are defined:
	jobid has a value which is a string
	jobws has a value which is a string
	status has a value which is a string
	auth has a value which is a string
bool is an int


=end text



=item Description

Changes the current status of a currently queued jobs 
Used to manage jobs by ensuring multiple server don't claim the same job.

=back

=cut

sub set_job_status
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to set_job_status:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'set_job_status');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($success);
    #BEGIN set_job_status
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["jobid","jobws","status"],{});
    my $peviousStatus;
    my $timevar = "requeuetime";
    #Checking status validity
    if ($params->{status} eq "queued") {
    	$peviousStatus = "none";
    	$timevar = "queuetime";
    } elsif ($params->{status} eq "running") {
    	$timevar = "starttime";
    	$peviousStatus = "queued";
    } elsif ($params->{status} eq "done") {
    	$peviousStatus = "running";
    	$timevar = "completetime";
    } else {
    	my $msg = "Input status not valid!";
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => 'set_job_status');
    }
    #Checking that job doesn't already exist
    my $cursor = $self->_mongodb()->jobObjects->find({id => $params->{jobid},ws => $params->{jobws}});
    my $object = $cursor->next;
    if (!defined($object)) {
    	my $msg = "Job not found!";
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => 'set_job_status');
    }
    #Updating job
    my $success = $self->_updateDB("jobObjects",{status => $peviousStatus,id => $params->{jobid},ws => $params->{jobws}},{'$set' => {'status' => $params->{status},$timevar => time()}});
	$self->_clearContext();
    #END set_job_status
    my @_bad_returns;
    (!ref($success)) or push(@_bad_returns, "Invalid type for return variable \"success\" (value was \"$success\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to set_job_status:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'set_job_status');
    }
    return($success);
}




=head2 get_jobs

  $jobs = $obj->get_jobs($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_jobs_params
$jobs is a reference to a list where each element is an ObjectData
get_jobs_params is a reference to a hash where the following keys are defined:
	status has a value which is a string
	auth has a value which is a string
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int

</pre>

=end html

=begin text

$params is a get_jobs_params
$jobs is a reference to a list where each element is an ObjectData
get_jobs_params is a reference to a hash where the following keys are defined:
	status has a value which is a string
	auth has a value which is a string
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int


=end text



=item Description



=back

=cut

sub get_jobs
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to get_jobs:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_jobs');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($jobs);
    #BEGIN get_jobs
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,[],{
    	status => undef
    });
    my $query = {};
    if (defined($params->{status})) {
    	$query->{status} = $params->{status};
    }
    if ($self->_getUsername() ne "cshenry") {
    	$query->{owner} = $self->_getUsername();
    }
    my $cursor = $self->_mongodb()->jobObjects->find($query);
	$jobs = [];
	while (my $object = $cursor->next) {
        push(@{$jobs},$object);
    }
   	$self->_clearContext();
    #END get_jobs
    my @_bad_returns;
    (ref($jobs) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"jobs\" (value was \"$jobs\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_jobs:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_jobs');
    }
    return($jobs);
}




=head2 get_types

  $types = $obj->get_types()

=over 4

=item Parameter and return types

=begin html

<pre>
$types is a reference to a list where each element is a string

</pre>

=end html

=begin text

$types is a reference to a list where each element is a string


=end text



=item Description

Returns a list of all permanent and optional types currently accepted by the workspace service.
An object cannot be saved in any workspace if it's type is not on this list.

=back

=cut

sub get_types
{
    my $self = shift;

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($types);
    #BEGIN get_types
    my $types = [keys(%{$self->_permanentTypes()})];
    my $cursor = $self->_mongodb()->typeObjects->find({});
    while (my $object = $cursor->next) {
    	push(@{$types},$object->{id});
    }
    #END get_types
    my @_bad_returns;
    (ref($types) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"types\" (value was \"$types\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_types:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_types');
    }
    return($types);
}




=head2 add_type

  $success = $obj->add_type($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is an add_type_params
$success is a bool
add_type_params is a reference to a hash where the following keys are defined:
	type has a value which is a string
	auth has a value which is a string
bool is an int

</pre>

=end html

=begin text

$params is an add_type_params
$success is a bool
add_type_params is a reference to a hash where the following keys are defined:
	type has a value which is a string
	auth has a value which is a string
bool is an int


=end text



=item Description

Adds a new custom type to the workspace service, so that objects of this type may be retreived.
Cannot add a type that already exists.

=back

=cut

sub add_type
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to add_type:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'add_type');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($success);
    #BEGIN add_type
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["type"],{});
    if ($self->_getUsername() eq "public") {
    	my $msg = "Must be authenticated to add new types!";
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => 'add_type');
    }
    if (defined($self->_permanentTypes()->{$params->{type}})) {
    	my $msg = "Trying to add a type that already exists!";
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => 'queue_job');
    }
    my $cursor = $self->_mongodb()->typeObjects->find({id => $params->{type}});
    if (my $object = $cursor->next) {
    	my $msg = "Trying to add a type that already exists!";
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => 'queue_job');
    }
    $self->_mongodb()->typeObjects->insert({
		id => $params->{type},
		owner => $self->_getUsername(),
		moddate => time(),
		permanent => 0
    });
    $success = 1;
   	$self->_clearContext();
    #END add_type
    my @_bad_returns;
    (!ref($success)) or push(@_bad_returns, "Invalid type for return variable \"success\" (value was \"$success\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to add_type:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'add_type');
    }
    return($success);
}




=head2 remove_type

  $success = $obj->remove_type($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a remove_type_params
$success is a bool
remove_type_params is a reference to a hash where the following keys are defined:
	type has a value which is a string
	auth has a value which is a string
bool is an int

</pre>

=end html

=begin text

$params is a remove_type_params
$success is a bool
remove_type_params is a reference to a hash where the following keys are defined:
	type has a value which is a string
	auth has a value which is a string
bool is an int


=end text



=item Description

Removes a custom type from the workspace service.
Permanent types cannot be removed.

=back

=cut

sub remove_type
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to remove_type:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'remove_type');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($success);
    #BEGIN remove_type
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["type"],{});
    if ($self->_getUsername() eq "public") {
    	my $msg = "Must be authenticated to remove types!";
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => 'add_type');
    }
    my $cursor = $self->_mongodb()->typeObjects->find({id => $params->{type},permanent => 0});
    if (my $object = $cursor->next) {
    	$self->_mongodb()->typeObjects->remove({id => $params->{type}});
    } else {
    	my $msg = "Trying to remove a type that doesn't exist  or a permanent type!";
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => 'queue_job');
    }
   	$self->_clearContext();
   	$success = 1;
    #END remove_type
    my @_bad_returns;
    (!ref($success)) or push(@_bad_returns, "Invalid type for return variable \"success\" (value was \"$success\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to remove_type:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'remove_type');
    }
    return($success);
}




=head2 version 

  $return = $obj->version()

=over 4

=item Parameter and return types

=begin html

<pre>
$return is a string
</pre>

=end html

=begin text

$return is a string

=end text

=item Description

Return the module version. This is a Semantic Versioning number.

=back

=cut

sub version {
    return $VERSION;
}

=head1 TYPES



=head2 bool

=over 4



=item Description

indicates true or false values, false <= 0, true >=1


=item Definition

=begin html

<pre>
an int
</pre>

=end html

=begin text

an int

=end text

=back



=head2 workspace_id

=over 4



=item Description

A string used as an ID for a workspace. Any string consisting of alphanumeric characters and "-" is acceptable


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 object_type

=over 4



=item Description

A string indicating the "type" of an object stored in a workspace. Acceptable types are returned by the "get_types()" command


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 object_id

=over 4



=item Description

ID of an object stored in the workspace. Any string consisting of alphanumeric characters and "-" is acceptable


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 permission

=over 4



=item Description

Single letter indicating permissions on access to workspace. Options are: 'a' for administative access, 'w' for read/write access, 'r' for read access, and 'n' for no access.


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 username

=over 4



=item Description

Login name of KBase useraccount to which permissions for workspaces are mapped


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 timestamp

=over 4



=item Description

Exact time for workspace operations. e.g. 2012-12-17T23:24:06


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 workspace_ref

=over 4



=item Description

A 36 character string referring to a particular instance of an object in a workspace that lasts forever. Objects should always be retreivable using this ID


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 ObjectData

=over 4



=item Description

Generic definition for object data stored in the workspace

Data objects stored in the workspace could be either a string or a reference to a complex perl data structure. So we can't really formulate a strict type definition for this data.

version - for complex data structures, the datastructure should include a version number to enable tracking of changes that may occur to the structure of the data over time


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
version has a value which is an int

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
version has a value which is an int


=end text

=back



=head2 object_metadata

=over 4



=item Description

Meta data associated with an object stored in a workspace.

        object_id id - ID of the object assigned by the user or retreived from the IDserver (e.g. kb|g.0)
        object_type type - type of the object (e.g. Genome)
        timestamp moddate - date when the object was modified by the user (e.g. 2012-12-17T23:24:06)
        int instance - instance of the object, which is equal to the number of times the user has overwritten the object
        timestamp date_created - time at which the alignment was built/loaded in seconds since the epoch
        string command - name of the command last used to modify or create the object
        username lastmodifier - name of the user who last modified the object
        username owner - name of the user who owns (who created) this object
        workspace_id workspace - ID of the workspace in which the object is currently stored
        workspace_ref ref - a 36 character ID that provides permanent undeniable access to this specific instance of this object


=item Definition

=begin html

<pre>
a reference to a list containing 9 items:
0: an object_id
1: an object_type
2: a timestamp
3: an int
4: a string
5: a username
6: a username
7: a workspace_id
8: a workspace_ref

</pre>

=end html

=begin text

a reference to a list containing 9 items:
0: an object_id
1: an object_type
2: a timestamp
3: an int
4: a string
5: a username
6: a username
7: a workspace_id
8: a workspace_ref


=end text

=back



=head2 workspace_metadata

=over 4



=item Description

Meta data associated with a workspace.

        workspace_id id - ID of the object assigned by the user or retreived from the IDserver (e.g. kb|g.0)
        username owner - name of the user who owns (who created) this object
        timestamp moddate - date when the workspace was last modified
        int objects - number of objects currently stored in the workspace
        permission user_permission - permissions for the currently logged user for the workspace
        permission global_permission - default permissions for the workspace for all KBase users


=item Definition

=begin html

<pre>
a reference to a list containing 6 items:
0: a workspace_id
1: a username
2: a timestamp
3: an int
4: a permission
5: a permission

</pre>

=end html

=begin text

a reference to a list containing 6 items:
0: a workspace_id
1: a username
2: a timestamp
3: an int
4: a permission
5: a permission


=end text

=back



=head2 save_object_params

=over 4



=item Description

Input parameters for the "save_objects function.

        object_type type - type of the object to be saved (an essential argument)
        workspace_id workspace - ID of the workspace where the object is to be saved (an essential argument)
        object_id id - ID behind which the object will be saved in the workspace (an essential argument)
        ObjectData data - string or reference to complex datastructure to be saved in the workspace (an essential argument)
        string command - the name of the KBase command that is calling the "save_object" function (an optional argument with default "unknown")
        mapping<string,string> metadata - a hash of metadata to be associated with the object (an optional argument with default "{}")
        string auth - the authentication token of the KBase account to associate this save command (an optional argument, user is "public" if auth is not provided)
        bool retrieveFromURL - a flag indicating that the "data" argument contains a URL from which the actual data should be downloaded (an optional argument with default "0")
        bool json - a flag indicating if the input data is encoded as a JSON string (an optional argument with default "0")
        bool compressed - a flag indicating if the input data in zipped (an optional argument with default "0")


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
data has a value which is an ObjectData
workspace has a value which is a workspace_id
command has a value which is a string
metadata has a value which is a reference to a hash where the key is a string and the value is a string
auth has a value which is a string
json has a value which is a bool
compressed has a value which is a bool
retrieveFromURL has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
data has a value which is an ObjectData
workspace has a value which is a workspace_id
command has a value which is a string
metadata has a value which is a reference to a hash where the key is a string and the value is a string
auth has a value which is a string
json has a value which is a bool
compressed has a value which is a bool
retrieveFromURL has a value which is a bool


=end text

=back



=head2 delete_object_params

=over 4



=item Description

Input parameters for the "delete_object" function.

        object_type type - type of the object to be deleted (an essential argument)
        workspace_id workspace - ID of the workspace where the object is to be deleted (an essential argument)
        object_id id - ID of the object to be deleted (an essential argument)
        string auth - the authentication token of the KBase account to associate this deletion command (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 delete_object_permanently_params

=over 4



=item Description

Input parameters for the "delete_object_permanently" function.

        object_type type - type of the object to be permanently deleted (an essential argument)
        workspace_id workspace - ID of the workspace where the object is to be permanently deleted (an essential argument)
        object_id id - ID of the object to be permanently deleted (an essential argument)
        string auth - the authentication token of the KBase account to associate with this permanent deletion command (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 get_object_params

=over 4



=item Description

Input parameters for the "get_object" function.

        object_type type - type of the object to be retrieved (an essential argument)
        workspace_id workspace - ID of the workspace containing the object to be retrieved (an essential argument)
        object_id id - ID of the object to be retrieved (an essential argument)
        int instance - Version of the object to be retrieved, enabling retrieval of any previous version of an object (an optional argument; the current version is retrieved if no version is provides)
        string auth - the authentication token of the KBase account to associate with this object retrieval command (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string


=end text

=back



=head2 get_object_output

=over 4



=item Description

Output generated by the "get_object" function.

        ObjectData data - data for object retrieved (an essential argument)
        object_metadata metadata - metadata for object retrieved (an essential argument)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
data has a value which is an ObjectData
metadata has a value which is an object_metadata

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
data has a value which is an ObjectData
metadata has a value which is an object_metadata


=end text

=back



=head2 get_objectmeta_params

=over 4



=item Description

Input parameters for the "get_objectmeta" function.

        object_type type - type of the object for which metadata is to be retrieved (an essential argument)
        workspace_id workspace - ID of the workspace containing the object for which metadata is to be retrieved (an essential argument)
        object_id id - ID of the object for which metadata is to be retrieved (an essential argument)
        int instance - Version of the object for which metadata is to be retrieved, enabling retrieval of any previous version of an object (an optional argument; the current metadata is retrieved if no version is provides)
        string auth - the authentication token of the KBase account to associate with this object metadata retrieval command (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string


=end text

=back



=head2 revert_object_params

=over 4



=item Description

Input parameters for the "revert_object" function.

        object_type type - type of the object to be reverted (an essential argument)
        workspace_id workspace - ID of the workspace containing the object to be reverted (an essential argument)
        object_id id - ID of the object to be reverted (an essential argument)
        int instance - Previous version of the object to which the object should be reset (an essential argument)
        string auth - the authentication token of the KBase account to associate with this object reversion command (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string


=end text

=back



=head2 copy_object_params

=over 4



=item Description

Input parameters for the "copy_object" function.

        object_type type - type of the object to be copied (an essential argument)
        workspace_id source_workspace - ID of the workspace containing the object to be copied (an essential argument)
        object_id source_id - ID of the object to be copied (an essential argument)
        int instance - Version of the object to be copied, enabling retrieval of any previous version of an object (an optional argument; the current object is copied if no version is provides)
        workspace_id new_workspace - ID of the workspace the object to be copied to (an essential argument)
        object_id new_id - ID the object is to be copied to (an essential argument)
        string auth - the authentication token of the KBase account to associate with this object copy command (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_id has a value which is an object_id
new_workspace has a value which is a workspace_id
source_id has a value which is an object_id
instance has a value which is an int
type has a value which is an object_type
source_workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_id has a value which is an object_id
new_workspace has a value which is a workspace_id
source_id has a value which is an object_id
instance has a value which is an int
type has a value which is an object_type
source_workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 move_object_params

=over 4



=item Description

Input parameters for the "move_object" function.

        object_type type - type of the object to be moved (an essential argument)
        workspace_id source_workspace - ID of the workspace containing the object to be moved (an essential argument)
        object_id source_id - ID of the object to be moved (an essential argument)
         workspace_id new_workspace - ID of the workspace the object to be moved to (an essential argument)
        object_id new_id - ID the object is to be moved to (an essential argument)
        string auth - the authentication token of the KBase account to associate with this object move command (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_id has a value which is an object_id
new_workspace has a value which is a workspace_id
source_id has a value which is an object_id
type has a value which is an object_type
source_workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_id has a value which is an object_id
new_workspace has a value which is a workspace_id
source_id has a value which is an object_id
type has a value which is an object_type
source_workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 has_object_params

=over 4



=item Description

Input parameters for the "has_object" function.

        object_type type - type of the object to be checked for existance (an essential argument)
        workspace_id workspace - ID of the workspace containing the object to be checked for existance (an essential argument)
        object_id id - ID of the object to be checked for existance (an essential argument)
        int instance - Version of the object to be checked for existance (an optional argument; the current object is checked if no version is provided)
        string auth - the authentication token of the KBase account to associate with this object check command (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
instance has a value which is an int
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
instance has a value which is an int
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 object_history_params

=over 4



=item Description

Input parameters for the "object_history" function.

        object_type type - type of the object to have history printed (an essential argument)
        workspace_id workspace - ID of the workspace containing the object to have history printed (an essential argument)
        object_id id - ID of the object to have history printed (an essential argument)
        string auth - the authentication token of the KBase account to associate with this object history command (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 create_workspace_params

=over 4



=item Description

Input parameters for the "create_workspace" function.

        workspace_id workspace - ID of the workspace to be created (an essential argument)
        permission default_permission - Default permissions of the workspace to be created. Accepted values are 'a' => admin, 'w' => write, 'r' => read, 'n' => none (an essential argument)
        string auth - the authentication token of the KBase account that will own the created workspace (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
default_permission has a value which is a permission
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
default_permission has a value which is a permission
auth has a value which is a string


=end text

=back



=head2 get_workspacemeta_params

=over 4



=item Description

Input parameters for the "get_workspacemeta" function.

        workspace_id workspace - ID of the workspace for which metadata should be returned (an essential argument)
        string auth - the authentication token of the KBase account accessing workspace metadata (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 get_workspacepermissions_params

=over 4



=item Description

Input parameters for the "get_workspacepermissions" function.

        workspace_id workspace - ID of the workspace for which custom user permissions should be returned (an essential argument)
        string auth - the authentication token of the KBase account accessing workspace permissions; must have admin privelages to workspace (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 delete_workspace_params

=over 4



=item Description

Input parameters for the "delete_workspace" function.

        workspace_id workspace - ID of the workspace to be deleted (an essential argument)
        string auth - the authentication token of the KBase account deleting the workspace; must be the workspace owner (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 clone_workspace_params

=over 4



=item Description

Input parameters for the "clone_workspace" function.

        workspace_id current_workspace - ID of the workspace to be cloned (an essential argument)
        workspace_id new_workspace - ID of the workspace to which the cloned workspace will be copied (an essential argument)
        permission default_permission - Default permissions of the workspace created by the cloning process. Accepted values are 'a' => admin, 'w' => write, 'r' => read, 'n' => none (an essential argument)
        string auth - the authentication token of the KBase account that will own the cloned workspace (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_workspace has a value which is a workspace_id
current_workspace has a value which is a workspace_id
default_permission has a value which is a permission
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_workspace has a value which is a workspace_id
current_workspace has a value which is a workspace_id
default_permission has a value which is a permission
auth has a value which is a string


=end text

=back



=head2 list_workspaces_params

=over 4



=item Description

Input parameters for the "list_workspaces" function.

        string auth - the authentication token of the KBase account accessing the list of workspaces (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
auth has a value which is a string


=end text

=back



=head2 list_workspace_objects_params

=over 4



=item Description

Input parameters for the "list_workspace_objects" function.

        workspace_id workspace - ID of the workspace for which objects should be listed (an essential argument)
        string type - type of the objects to be listed (an optional argument; all object types will be listed if left unspecified)
        bool showDeletedObject - a flag that, if set to '1', causes any deleted objects to be included in the output (an optional argument; default is '0')
        string auth - the authentication token of the KBase account listing workspace objects; must have at least 'read' privelages (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
type has a value which is a string
showDeletedObject has a value which is a bool
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
type has a value which is a string
showDeletedObject has a value which is a bool
auth has a value which is a string


=end text

=back



=head2 set_global_workspace_permissions_params

=over 4



=item Description

Input parameters for the "set_global_workspace_permissions" function.

        workspace_id workspace - ID of the workspace for which permissions will be set (an essential argument)
        permission new_permission - New default permissions to which the workspace should be set. Accepted values are 'a' => admin, 'w' => write, 'r' => read, 'n' => none (an essential argument)
        string auth - the authentication token of the KBase account changing workspace default permissions; must have 'admin' privelages to workspace (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_permission has a value which is a permission
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_permission has a value which is a permission
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 set_workspace_permissions_params

=over 4



=item Description

Input parameters for the "set_workspace_permissions" function.

        workspace_id workspace - ID of the workspace for which permissions will be set (an essential argument)
        list<username> users - list of users for which workspace privaleges are to be reset (an essential argument)
        permission new_permission - New permissions to which all users in the user list will be set for the workspace. Accepted values are 'a' => admin, 'w' => write, 'r' => read, 'n' => none (an essential argument)
        string auth - the authentication token of the KBase account changing workspace permissions; must have 'admin' privelages to workspace (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
users has a value which is a reference to a list where each element is a username
new_permission has a value which is a permission
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
users has a value which is a reference to a list where each element is a username
new_permission has a value which is a permission
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 queue_job_params

=over 4



=item Description

Input parameters for the "queue_job" function.

        string jobid - ID of the job to be queued (an essential argument)
        string jobws - Workspace containing the job to be queued (an essential argument)
        string auth - the authentication token of the KBase account queuing the job; must have access to the job being queued (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
jobid has a value which is a string
jobws has a value which is a string
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
jobid has a value which is a string
jobws has a value which is a string
auth has a value which is a string


=end text

=back



=head2 set_job_status_params

=over 4



=item Description

Input parameters for the "set_job_status" function.

        string jobid - ID of the job to be have status changed (an essential argument)
        string jobws - Workspace containing the job to have status changed (an essential argument)
        string status - Status to which job should be changed; accepted values are 'queued', 'running', and 'done' (an essential argument)
        string auth - the authentication token of the KBase account requesting job status; only status for owned jobs can be retrieved (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
jobid has a value which is a string
jobws has a value which is a string
status has a value which is a string
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
jobid has a value which is a string
jobws has a value which is a string
status has a value which is a string
auth has a value which is a string


=end text

=back



=head2 get_jobs_params

=over 4



=item Description

Input parameters for the "get_jobs" function.

        string status - Status of all jobs to be retrieved; accepted values are 'queued', 'running', and 'done' (an essential argument)
        string auth - the authentication token of the KBase account accessing job list; only owned jobs will be returned (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
status has a value which is a string
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
status has a value which is a string
auth has a value which is a string


=end text

=back



=head2 add_type_params

=over 4



=item Description

Input parameters for the "add_type" function.

        string type - Name of type being added (an essential argument)
        string auth - the authentication token of the KBase account adding a type (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
type has a value which is a string
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
type has a value which is a string
auth has a value which is a string


=end text

=back



=head2 remove_type_params

=over 4



=item Description

Input parameters for the "remove_type" function.

        string type - name of custom type to be removed from workspace service (an essential argument)
        string auth - the authentication token of the KBase account removing a custom type (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
type has a value which is a string
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
type has a value which is a string
auth has a value which is a string


=end text

=back



=cut

1;
