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
	my ($self,$id) = @_;
	$self->_mongodb()->workspaces->remove({});
}

=head3 _clearAllWorkspaceUsers

Definition:
	void  _clearAllWorkspaceUsers();
Description:
	Clears all workspace users from the database

=cut

sub _clearAllWorkspaceUsers {
	my ($self,$id) = @_;
	$self->_mongodb()->workspaceUsers->remove({});
}

=head3 _clearAllWorkspaceObjects

Definition:
	void  _clearAllWorkspaceObjects();
Description:
	Clears all workspace objects from the database

=cut

sub _clearAllWorkspaceObjects {
	my ($self,$id) = @_;
	$self->_mongodb()->workspaceObjects->remove({});
}

=head3 _clearAllWorkspaceDataObjects

Definition:
	void  _clearAllWorkspaceDataObjects();
Description:
	Clears all workspace data objects from the database

=cut

sub _clearAllWorkspaceDataObjects {
	my ($self,$id) = @_;
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
    	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Object not found with specified ".$id.", ".$type.", ".$workspace.", ".$instance."!",method_name => '_getObjectByID');
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
	my $types = {
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
        PROMModel => 1
	};
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Specified type not valid!",
		method_name => '_validateObjectType') if (!defined($types->{$type}));
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

sub _uncompressData {
	my ($self,$data) = @_;
	my $datastring;
	gunzip \$data => \$datastring;
	return JSON::XS->new->decode($datastring);
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
	print "Connected to:".$self->{_host}.".".$self->{_db}."\n";
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
	compressedjson has a value which is a bool
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
	compressedjson has a value which is a bool
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
    	compressedjson => 0
    });
    if ($params->{compressedjson} == 1) {
    	$params->{data} = $self->_uncompressData($params->{data});
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



=head2 WorkspaceData

=over 4



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

Object management routines


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
compressedjson has a value which is a bool

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
compressedjson has a value which is a bool


=end text

=back



=head2 delete_object_params

=over 4



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

Workspace management routines


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



=cut

1;
