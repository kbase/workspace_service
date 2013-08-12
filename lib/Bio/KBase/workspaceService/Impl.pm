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

=head2 SYNOPSIS

Workspaces are used in KBase to provide an online location for all data, models, and
analysis results. Workspaces are a powerful tool for managing private data, tracking 
workflow provenance, storing and sharing large datasets, and tracking work history. They
have a number of useful characteristics which you will learn about over the course of the
workspace tutorials:

1.) Multiple users can read and write from the same workspace at the same time, 
facilitating collaboration

2.) When an object is overwritten in a workspace, the previous version is preserved and
easily accessible at any time, enabling the use of workspaces to track object provenance

3.) Workspaces have default permissions and user-specific permissions, providing total 
control over the sharing and access of workspace contents

=head2 EXAMPLE OF API USE IN PERL

To use the API, first you need to instantiate a workspace client object:

my $client = Bio::KBase::workspaceService::Client->new;
   
Next, you can run API commands on the client object:
   
my $ws = $client->create_workspace({
        workspace => "foo",
        default_permission => "n"
});
my $objs = $client->list_workspace_objects({
        workspace => "foo"
});
print map { $_->[0] } @$objs;

=head2 AUTHENTICATION

Each and every function in this service takes a hash reference as
its single argument. This hash reference may contain a key
C<auth> whose value is a bearer token for the user making
the request. If this is not provided a default user "public" is assumed.

=head2 WORKSPACE

A workspace is a named collection of objects owned by a specific
user, that may be viewable or editable by other users.Functions that operate
on workspaces take a C<workspace_id>, which is an alphanumeric string that
uniquely identifies a workspace among all workspaces.

=cut

#BEGIN_HEADER
use MongoDB;
use MongoDB::GridFS;
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
	if (!defined($self->_getContext->{_override}->{_currentUser})) {
		if (defined($self->{_testuser})) {
			$self->_getContext->{_override}->{_currentUser} = $self->{_testuser};
		} else {
			$self->_getContext->{_override}->{_currentUser} = "public";
		}
		
	}
	return $self->_getContext->{_override}->{_currentUser};
}

sub _getCurrentUserObj {
	my ($self) = @_;
	if (!defined($self->_getContext->{_override}->{_currentUserObj})) {
		$self->_getContext->{_override}->{_currentUserObj} = $self->_getWorkspaceUser($self->_getUsername());
	}
	return $self->_getContext->{_override}->{_currentUserObj};
}

sub _accountType {
	my ($self) = @_;
	if (!defined($self->{_accounttype})) {
		$self->{_accounttype} = "kbase";
	}
	return $self->{_accounttype};	
}

sub _authenticate {
	my ($self,$auth) = @_;
	if ($self->{_accounttype} eq "kbase") {
		if ($auth =~ m/^IRIS-/) {
			return {
				authentication => $auth,
				user => $auth
			};
		} else {
			my $token = Bio::KBase::AuthToken->new(
				token => $auth,
			);
			if ($token->validate()) {
				return {
					authentication => $auth,
					user => $token->user_id
				};
			} else {
				Bio::KBase::Exceptions::KBaseException->throw(error => "Invalid authorization token:".$auth,
				method_name => '_setContext');
			}
		}
	} elsif ($self->{_accounttype} eq "seed") {
		require "Bio/ModelSEED/MSSeedSupportServer/Client.pm";
		$auth =~ s/\s/\t/;
		my $split = [split(/\t/,$auth)];
		my $svr = $self->_mssServer();
		my $token = $svr->authenticate({
			username => $split->[0],
			password => $split->[1]
		});
		if (!defined($token) || $token =~ m/ERROR:/) {
			Bio::KBase::Exceptions::KBaseException->throw(error => $token,
			method_name => '_setContext');
		}
		$token =~ s/\s/\t/;
		$split = [split(/\t/,$token)];
		return {
			authentication => $token,
			user => $split->[0]
		};
	} elsif ($self->{_accounttype} eq "modelseed") {
		require "ModelSEED/utilities.pm";
		my $config = ModelSEED::utilities::config();
		my $username = $config->authenticate({
			token => $auth
		});
		return {
			authentication => $auth,
			user => $username
		};
	}
}

sub _setContext {
	my ($self,$context,$params) = @_;
    if (defined($params->{auth}) && length($params->{auth}) > 0) {
		if (!defined($self->_getContext()->{_override}) || $self->_getContext()->{_override}->{_authentication} ne $params->{auth}) {
			my $output = $self->_authenticate($params->{auth});
			$self->_getContext()->{_override}->{_authentication} = $output->{authentication};
			$self->_getContext()->{_override}->{_currentUser} = $output->{user};
			
		}
    }
}

sub _getContext {
	my ($self) = @_;
	if (!defined($Bio::KBase::workspaceService::Server::CallContext)) {
		$Bio::KBase::workspaceService::Server::CallContext = {};
	}
	return $Bio::KBase::workspaceService::Server::CallContext;
}

sub _clearContext {
	my ($self) = @_;
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
    return $self->{_mongodb};
}

sub _mssServer {
	my $self = shift;
	if (!defined($self->{_mssServer})) {
		$self->{_mssServer} = Bio::ModelSEED::MSSeedSupportServer::Client->new($self->{'_mssserver-url'});
	}
    return $self->{_mssServer};
}

=head3 _idServer

Definition:
	Bio::KBase::IDServer::Client = _idServer();
Description:
	Returns ID server client

=cut
sub _idServer {
	my $self = shift;
	if (!defined($self->{_idserver})) {
		$self->{_idserver} = Bio::KBase::IDServer::Client->new($self->{'_idserver-url'});
	}
    return $self->{_idserver};
}

=head3 _get_new_id

Definition:
	string id = _get_new_id(string prefix);
Description:
	Returns ID with given prefix

=cut
sub _get_new_id {
	my ($self,$prefix) = @_;
	my $id;
	eval {
		$id = $self->_idServer()->allocate_id_range( $prefix, 1 );
	};
    if (!defined($id) || $id eq "") {
    	$id = "0";
    }
    $id = $prefix.$id;
	return $id;
};

=head3 _gridfs

Definition:
	MongoDB = _gridfs();
Description:
	Returns MongoDB::GridFS object

=cut

sub _gridfs {
    my ($self) = @_;
    if (!defined($self->{_gridfs})) {
    	$self->{_gridfs} = $self->_mongodb()->get_gridfs;
    }    
    return $self->{_gridfs};
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
=head3 _saveObjectByRef

Definition:
	Bio::KBase::workspaceService::Object =  _saveObjectByRef(string:id,string:permission);
Description:
	Creates an object that is saved by reference only and not stored in any workspace.
	There are no permissions, but you must have the object's uuid in order to access it.

=cut

sub _saveObjectByRef {
	my ($self,$type,$id,$data,$command,$meta,$ref,$replace) = @_;
	$self->_validateObjectType($type);
	if (!defined($ref)) {
		$ref = Data::UUID->new()->create_str();
	} else {
		my $obj = $self->_getObject($ref);
		if (defined($obj)) {
	    	if ($replace == 0) {
		    	my $msg = "Object with reference already exist, and replace not specified!";
				Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => '_saveObjectByRef');
	    	} else {
				my $obj = Bio::KBase::workspaceService::Object->new({
					parent => $self,
					uuid => $ref,
					workspace => "NO_WORKSPACE",
					type => $type,
					id => $id,
					owner => $self->_getUsername(),
					lastModifiedBy => $self->_getUsername(),
					command => $command,
					instance => 0,
					rawdata => $data,
					meta => $meta,
				});
				$obj->setDefaultMetadata();
				$self->_updateDB("workspaceObjects",{id => $ref},{'$set' => {
					uuid => $ref,
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
					meta => $obj->meta(),
					refdeps => $obj->refDependencies(),
					iddeps => $obj->idDependencies(),
				}});
				return $obj;
	    	}
    	}
	}
	return $self->_createObject({
		uuid => $ref,
		type => $type,
		workspace => "NO_WORKSPACE",
		parent => $self,
		ancestor => undef,
		owner => $self->_getUsername(),
		lastModifiedBy => $self->_getUsername(),
		command => $command,
		id => $id,
		instance => 0,
		rawdata => $data,
		meta => $meta
	});
}

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
	$self->_mongodb()->get_collection('workspaces')->insert({
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
		workspaces => {},
		settings => {workspace => "default"}
	});
	$self->_mongodb()->get_collection('workspaceUsers')->insert({
		moddate => $user->moddate(),
		id => $user->id(),
		workspaces => $user->workspaces(),
		settings => $user->settings()
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
	$obj->setDefaultMetadata();
	$self->_mongodb()->get_collection( 'workspaceObjects' )->insert({
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
		meta => $obj->meta(),
		refdeps => $obj->refDependencies(),
		iddeps => $obj->idDependencies(),
		moddate => $obj->moddate()
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
	#Inserting data using gridfs
	my $dataString = $obj->data();
    open(my $basic_fh, "<", \$dataString);
    my $fh = FileHandle->new;
    $fh->fdopen($basic_fh, 'r');
    $self->_gridfs()->insert($fh, {
    	creationDate => $obj->creationDate(),
		chsum => $obj->chsum(),
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
	$self->_mongodb()->get_collection('workspaces')->remove({id => $id});
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
	$self->_mongodb()->get_collection('workspaceUsers')->remove({id => $id});
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
	$self->_mongodb()->get_collection('workspaceObjects')->remove({uuid => $uuid});
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
	my $grid = $self->_gridfs();
	$grid->remove({chsum => $chsum});
}

=head3 _clearAllWorkspaces

Definition:
	void  _clearAllWorkspaces();
Description:
	Clears all workspaces from the database

=cut

sub _clearAllWorkspaces {
	my ($self) = @_;
	$self->_mongodb()->get_collection('workspaces')->remove({});
}

=head3 _clearAllJobs

Definition:
	void  _clearAllJobs();
Description:
	Clears all jobs from the database

=cut

sub _clearAllJobs {
	my ($self) = @_;
	$self->_mongodb()->get_collection('jobObjects')->remove({});
}

=head3 _clearAllWorkspaceUsers

Definition:
	void  _clearAllWorkspaceUsers();
Description:
	Clears all workspace users from the database

=cut

sub _clearAllWorkspaceUsers {
	my ($self) = @_;
	$self->_mongodb()->get_collection('workspaceUsers')->remove({});
}

=head3 _clearAllWorkspaceObjects

Definition:
	void  _clearAllWorkspaceObjects();
Description:
	Clears all workspace objects from the database

=cut

sub _clearAllWorkspaceObjects {
	my ($self) = @_;
	$self->_mongodb()->get_collection('workspaceObjects')->remove({});
}

=head3 _clearAllWorkspaceDataObjects

Definition:
	void  _clearAllWorkspaceDataObjects();
Description:
	Clears all workspace data objects from the database

=cut

sub _clearAllWorkspaceDataObjects {
	my ($self) = @_;
	my $grid = $self->_gridfs();
	$grid->drop();
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
	my $cursor = $self->_mongodb()->get_collection('workspaceUsers')->find({id => {'$in' => $ids} });
	my $objHash = {};
	while (my $object = $cursor->next) {
        my $newObject = Bio::KBase::workspaceService::WorkspaceUser->new({
			parent => $self,
			id => $object->{id},
			workspaces => $object->{workspaces},
			moddate => $object->{moddate},
			settings => $object->{settings}
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
    my $cursor = $self->_mongodb()->get_collection('workspaceUsers')->find({$key => {'$in' => ["a","w","r","n"]} });
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
	my $cursor = $self->_mongodb()->get_collection( 'workspaces' )->find($query);
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
    my $cursor = $self->_mongodb()->get_collection('workspaceObjects')->find({chsum => {'$in' => $chsums} });
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
	my $cursor = $self->_mongodb()->get_collection('workspaceObjects')->find({uuid => {'$in' => $ids} });
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
	my $cursor = $self->_mongodb()->get_collection( 'workspaceObjects' )->find({
    	id => $id,
    	type => $type,
    	workspace => $workspace,
    	instance => int($instance)
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
    my $cursor = $self->_mongodb()->get_collection('workspaceObjects')->find({
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
	my $grid = $self->_gridfs();
    my $objects = [];
    foreach my $chsum (@{$chsums}) {
    	my $file = $grid->find_one({chsum => $chsum});
    	if (!defined($file) && $options->{throwErrorIfMissing} == 1) {
    		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "DataObject ".$chsum." not found!",
							       method_name => '_getDataObjects');
    	}
    	if (defined($file)) {
			my $dataString = $file->slurp();
	    	my $newObject = Bio::KBase::workspaceService::DataObject->new({
	        	parent => $self,
	        	compressed => $file->{info}->{compressed},
				json => $file->{info}->{json},
				chsum => $file->{info}->{chsum},
				data => $dataString,
				creationDate => $file->{info}->{creationDate}	
			});
			push(@{$objects},$newObject);
    	}
    }
	return $objects;
}

=head3 _tohtml

Definition:
	string =  _tohtml(Bio::KBase::workspaceService::Object);
Description:
	Prints the input object in HTML format

=cut

sub _tohtml {
	my ($self,$object) = @_;
	my $html;
	if ($object->type() eq "Model") {
		
	} elsif ($object->type() eq "Media") {
		
	} elsif ($object->type() eq "Mapping") {
		
	} elsif ($object->type() eq "FBA") {
		
	} elsif ($object->type() eq "Annotation") {
		
	} elsif ($object->type() eq "PROMModel") {
	
	} elsif ($object->type() eq "GapFill") {
		
	} elsif ($object->type() eq "GapGen") {
	
	} elsif ($object->type() eq "PhenotypeSet") {
		
	} elsif ($object->type() eq "Genome") {
	
	} elsif ($object->type() eq "ProbAnno") {
		
	} elsif ($object->type() eq "Biochemistry") {
		
	} elsif ($object->type() eq "PhenotypeSimulationSet") {
		
	} elsif ($object->type() eq "TestData") {
		
	} elsif ($object->type() eq "Unspecified") {
	
	} elsif ($object->type() eq "Growmatch data") {
		
	} elsif ($object->type() eq "Unspcifeedie") {
		
	} elsif ($object->type() eq "foo") {
		
	}
	return $html;
}
	

#####################################################################
#Data validation methods
#####################################################################

sub _validateWorkspaceID {
	my ($self,$id) = @_;
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Workspace name must contain only alphanumeric characters!",
		method_name => '_validateWorkspaceID') if ($id !~ m/^\w+$/ || $id eq "NO_WORKSPACE");
}

sub _validateUserID {
	my ($self,$id) = @_;
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Username must contain only alphanumeric characters!",
		method_name => '_validateUserID') if ($id !~ m/^[\w-]+$/);
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
	my $cursor = $self->_mongodb()->get_collection('typeObjects')->find({id => $type});
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
        ProbAnno => 1,
        GenomeContigs => 1,
        PromConstraints => 1,
        ModelTemplate => 1
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

=head3 _patch

Definition:
	0/1 =  _patch({});
Description:
	This function permits the remote application of data patches to handle correction and adjustments in the database

=cut
sub _patch {
	my($self, $params) = @_;
	#Correcting the modification date on all objects
	if ($params->{patch_id} eq "moddate") {
		my $cursor = $self->_mongodb()->get_collection('workspaceObjects')->find();
		my $grid = $self->_gridfs();
		while (my $object = $cursor->next) {
	        my $file = $grid->find_one({chsum => $object->{chsum}});
	        my $date = $file->{info}->{creationDate};
	        $self->_updateDB("workspaceObjects",{uuid => $object->{uuid}},{'$set' => {'moddate' => $date}})
	    }
	#Correcting the gene count on all models
	} elsif ($params->{patch_id} eq "jobs") {
		my $cursor = $self->_mongodb()->get_collection('jobObjects')->find();
		while (my $object = $cursor->next) {
			if ($object->{id} !~ m/^job/) {
	       		my $obj = $self->_getObject($object->{id});
	       		if (defined($obj)) {
		       		my $data = $obj->data();
		       		my $changes = {
		       			type => "FBA",
		      			jobdata => {
		      				postprocess_command => $data->{postprocess_command},
							fbaref => $data->{clusterjobs}->[0]->{fbaid}
		      			},
		      			queuecommand => $data->{queuing_command}
		       		};
		       		if (defined($data->{clusterjobs}->[0]->{postprocess_args})) {
		       			if (ref($data->{clusterjobs}->[0]->{postprocess_args}) eq "ARRAY") {
		       				$changes->{jobdata}->{postprocess_args} = $data->{clusterjobs}->[0]->{postprocess_args};
		       				if (defined($data->{clusterjobs}->[0]->{postprocess_args}->[0]->{auth})) {
				       			$changes->{auth} = $data->{clusterjobs}->[0]->{postprocess_args}->[0]->{auth};
				       		}
		       			} else {
		       				$changes->{jobdata}->{postprocess_args}->[0] = $data->{clusterjobs}->[0]->{postprocess_args};
		       				if (defined($data->{clusterjobs}->[0]->{postprocess_args}->{auth})) {
				       			$changes->{auth} = $data->{clusterjobs}->[0]->{postprocess_args}->{auth};
				       		}
		       			}
		       		}
		       		if (defined($object->{queuetime}) && $object->{queuetime} =~ m/^\d+$/) {
		       			$changes->{queuetime} = DateTime->from_epoch(epoch => $object->{queuetime})->datetime();
		       		}
		       		if (defined($object->{starttime}) && $object->{starttime} =~ m/^\d+$/) {
		       			$changes->{starttime} = DateTime->from_epoch(epoch => $object->{starttime})->datetime();
		       		}
		       		if (defined($object->{completetime}) && $object->{completetime} =~ m/^\d+$/) {
		       			$changes->{completetime} = DateTime->from_epoch(epoch => $object->{completetime})->datetime();
		       		}
		       		if (defined($object->{requeuetime}) && $object->{requeuetime} =~ m/^\d+$/) {
		       			$changes->{requeuetime} = DateTime->from_epoch(epoch => $object->{requeuetime})->datetime();
		       		}
		       		$self->_updateDB("jobObjects",{id => $object->{id}},{'$set' => $changes});
	       		}
	       }
	    }
	} elsif ($params->{patch_id} eq "genenum") {
		my $cursor = $self->_mongodb()->get_collection('workspaceObjects')->find();
		while (my $object = $cursor->next) {
	        if ($object->{type} eq "Model") {
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
		        my $data = $newObject->data();
		        if (defined($data->{modelreactions})) {
					my $genehash = {};
					for (my $i=0; $i < @{$data->{modelreactions}}; $i++) {
						my $rxn = $data->{modelreactions}->[$i];
						if (defined($rxn->{modelReactionProteins})) {
							for (my $j=0; $j < @{$rxn->{modelReactionProteins}}; $j++) {
								my $prot = $rxn->{modelReactionProteins}->[$j];
								if (defined($prot->{modelReactionProteinSubunits})) {
									for (my $k=0; $k < @{$prot->{modelReactionProteinSubunits}}; $k++) {
										my $subunit = $prot->{modelReactionProteinSubunits}->[$k];
										if (defined($subunit->{modelReactionProteinSubunitGenes})) {
											for (my $m=0; $m < @{$subunit->{modelReactionProteinSubunitGenes}}; $m++) {
												my $gene = $subunit->{modelReactionProteinSubunitGenes}->[$m];
												if (defined($gene->{feature_uuid})) {
													$genehash->{$gene->{feature_uuid}} = 1;
												}
											}
										}
									}
								}
							}
						}
					}
					my $numgenes = keys(%{$genehash});
		        	$self->_updateDB("workspaceObjects",{uuid => $object->{uuid}},{'$set' => {'meta.number_genes' => $numgenes}});
		        }
			}
	    }
	}
};

#END_HEADER

sub new
{
    my($class, @args) = @_;
    my $self = {
    };
    bless $self, $class;
    #BEGIN_CONSTRUCTOR
    my $options = $args[0];
	$ENV{KB_NO_FILE_ENVIRONMENT} = 1;
    my $params;
    $self->{_accounttype} = "kbase";
    $self->{'_idserver-url'} = "http://bio-data-1.mcs.anl.gov/services/idserver";
    $self->{'_mssserver-url'} = "http://biologin-4.mcs.anl.gov:7050";
    my $host = "localhost";
    my $db = "workspace_service";
    my $user = undef;
	my $pwd = undef;
	my $paramlist = [qw(mongodb-database mongodb-host mongodb-user mongodb-pwd testuser mssserver-url accounttype idserver-url)];

    # so it looks like params is created by looping over the config object
    # if deployment.cfg exists

    # the keys in the params hash are the same as in the config object 
    # except the block name from the config file is ommitted.

    # the block name is picked up from KB_SERVICE_NAME. this has to be set
    # in the start_service script as an environment variable.

    # looping over a set of predefined set of parameter keys, see if there
    # is a value for that key in the config object

	if ((my $e = $ENV{KB_DEPLOYMENT_CONFIG}) && -e $ENV{KB_DEPLOYMENT_CONFIG}) {
		my $service = $ENV{KB_SERVICE_NAME};
		if (defined($service)) {
			my $c = Config::Simple->new();
			$c->read($e);
			for my $p (@{$paramlist}) {
				my $v = $c->param("$service.$p");
				if ($v) {
					$params->{$p} = $v;
				}
			}
		}
    }

    # now, we have the options hash. THis is passed into the constructor as a
    # parameter to new(). If a key from the predefined set of parameter keys
    # is found in the incoming hash, let the associated value override what
    # was previously assigned to the params hash from the config object.

    for my $p (@{$paramlist}) {
  		if (defined($options->{$p})) {
			$params->{$p} = $options->{$p};
        }
    }
	
    # now, if params has one of the predefined set of parameter keys,
    # use that value to override object instance variable values. The
    # default object instance variable values were set above.

	if (defined $params->{'mongodb-host'}) {
		$host = $params->{'mongodb-host'};
    }
	if (defined $params->{'mongodb-database'}) {
		$db = $params->{'mongodb-database'};
	}
	if (defined $params->{'mongodb-user'}) {
		$user = $params->{'mongodb-user'};
	}
	if (defined $params->{'mongodb-pwd'}) {
		$pwd = $params->{'mongodb-pwd'};
	}
    if (defined $params->{accounttype}) {
		$self->{_accounttype} = $params->{accounttype};
    }
    if (defined($params->{testuser})) {
    	$self->{_testuser} = $params->{testuser};
    }
    if (defined $params->{'idserver-url'}) {
    		$self->{'_idserver-url'} = $params->{'idserver-url'};
    }
    if (defined $params->{'mssserver-url'}) {
    		$self->{'_mssserver-url'} = $params->{'mssserver-url'};
    }
    
	print STDERR "***Starting workspace service with mongo parameters:***\n";
	print STDERR "Host: $host\n";
	print STDERR "Database: $db\n";
	print STDERR "User: $user\n";
	if($pwd) {
		print STDERR "Password of length " . length($pwd) . "\n";
	}
	my $config = {
		host => $host,
		db_name => $db,
		auto_connect => 1,
		auto_reconnect => 1
	};
	if(defined $user && defined $pwd) {
		$config->{username} = $user;
		$config->{password} = $pwd;
	}
	my $conn = MongoDB::Connection->new(%$config);
	Bio::KBase::Exceptions::KBaseException->throw(error => "Unable to connect: $@",
								method_name => 'Impl::new') if (!defined($conn));
	$self->{_mongodb} = $conn->get_database($db);
	
    #END_CONSTRUCTOR

    if ($self->can('_init_instance'))
    {
	$self->_init_instance();
    }
    return $self;
}

=head1 METHODS



=head2 load_media_from_bio

  $mediaMetas = $obj->load_media_from_bio($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a load_media_from_bio_params
$mediaMetas is a reference to a list where each element is an object_metadata
load_media_from_bio_params is a reference to a hash where the following keys are defined:
	mediaWS has a value which is a workspace_id
	bioid has a value which is an object_id
	bioWS has a value which is a workspace_id
	clearExisting has a value which is a bool
	overwrite has a value which is a bool
	auth has a value which is a string
	asHash has a value which is a bool
workspace_id is a string
object_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
object_type is a string
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a load_media_from_bio_params
$mediaMetas is a reference to a list where each element is an object_metadata
load_media_from_bio_params is a reference to a hash where the following keys are defined:
	mediaWS has a value which is a workspace_id
	bioid has a value which is an object_id
	bioWS has a value which is a workspace_id
	clearExisting has a value which is a bool
	overwrite has a value which is a bool
	auth has a value which is a string
	asHash has a value which is a bool
workspace_id is a string
object_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
object_type is a string
timestamp is a string
username is a string
workspace_ref is a string


=end text



=item Description

Creates "Media" objects in the workspace for all media contained in the specified biochemistry

=back

=cut

sub load_media_from_bio
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to load_media_from_bio:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'load_media_from_bio');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($mediaMetas);
    #BEGIN load_media_from_bio
    $self->_setContext($ctx,$params);
    $params = $self->_validateargs($params,[],{
    	mediaWS => "KBaseMedia",
    	bioid => "default",
    	bioWS => "kbase",
    	clearExisting => 0,
    	overwrite => 0,
    	asHash => 0
    });
    #Creating the workspace if not already existing
    my $biows = $self->_getWorkspace($params->{bioWS});
    if (!defined($biows)) {
    	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Biochemistry workspace not found!",
							       method_name => 'load_media_from_bio');
    }
    my $ws = $self->_getWorkspace($params->{mediaWS});
	if (!defined($ws)) {
		$self->_createWorkspace($params->{mediaWS},"r");
		$ws = $self->_getWorkspace($params->{mediaWS});
	}
	my $bio = $biows->getObject("Biochemistry",$params->{bioid});
	if (defined($bio->data()->{media})) {
		my $media = $bio->data()->{media};
		for (my $i=0; $i < @{$media};$i++) {
			my $obj = $ws->getObject("Media",$media->[$i]->{id});
			if (!defined($obj) || $params->{overwrite} == 1) {
				$obj = $ws->saveObject("Media",$media->[$i]->{id},$media->[$i],"load_media_from_bio",{});	
			}
			push(@{$mediaMetas},$obj->metadata($params->{asHash}));
		}
	}
	$self->_clearContext();
    #END load_media_from_bio
    my @_bad_returns;
    (ref($mediaMetas) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"mediaMetas\" (value was \"$mediaMetas\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to load_media_from_bio:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'load_media_from_bio');
    }
    return($mediaMetas);
}




=head2 import_bio

  $metadata = $obj->import_bio($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is an import_bio_params
$metadata is an object_metadata
import_bio_params is a reference to a hash where the following keys are defined:
	bioid has a value which is an object_id
	bioWS has a value which is a workspace_id
	url has a value which is a string
	compressed has a value which is a bool
	clearExisting has a value which is a bool
	overwrite has a value which is a bool
	auth has a value which is a string
	asHash has a value which is a bool
object_id is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
object_type is a string
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is an import_bio_params
$metadata is an object_metadata
import_bio_params is a reference to a hash where the following keys are defined:
	bioid has a value which is an object_id
	bioWS has a value which is a workspace_id
	url has a value which is a string
	compressed has a value which is a bool
	clearExisting has a value which is a bool
	overwrite has a value which is a bool
	auth has a value which is a string
	asHash has a value which is a bool
object_id is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
object_type is a string
timestamp is a string
username is a string
workspace_ref is a string


=end text



=item Description

Imports a biochemistry from a URL

=back

=cut

sub import_bio
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to import_bio:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'import_bio');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN import_bio
    $self->_setContext($ctx,$params);
    $params = $self->_validateargs($params,[],{
    	bioid => "default",
    	bioWS => "kbase",
    	url => "http://bioseed.mcs.anl.gov/~chenry/exampleObjects/defaultBiochem.json.gz",
    	compressed => 1,
    	overwrite => 0,
    	asHash => 0
    });
    #Creating the workspace if not already existing
    my $ws = $self->_getWorkspace($params->{bioWS});
	if (!defined($ws)) {
		$self->_createWorkspace($params->{bioWS},"r");
		$ws = $self->_getWorkspace($params->{bioWS});
	}
	#Checking for existing object
	my $obj = $ws->getObject("Biochemistry",$params->{bioid});
	if (defined($obj) && $params->{overwrite} == 0) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Biochemistry exists, and overwrite not requested",
							       method_name => 'import_bio');
	}
	#Retreiving object from url
	my ($fh1, $compressed_filename) = tempfile();
	close($fh1);
	my $status = getstore($params->{url}, $compressed_filename);
	if ($status != 200) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Unable to fetch from URL",
							       method_name => 'import_bio');
	}
	#Uncompressing
	if ($params->{compressed} == 1) {
		my ($fh2, $uncompressed_filename) = tempfile();
		close($fh2);
		gunzip $compressed_filename => $uncompressed_filename;
		$compressed_filename = $uncompressed_filename;
	}
	#Saving object
	open(my $fh, "<", $compressed_filename) || die "$!: $@";
	my @lines = <$fh>;
	close($fh);
	my $string = join("\n",@lines);
	my $data = JSON::XS->new->utf8->decode($string);
	$data->{uuid} = $params->{bioWS}."/".$params->{bioid};
	$obj = $ws->saveObject("Biochemistry",$params->{bioid},$data,"import_bio",{});
    $metadata = $obj->metadata($params->{asHash});
    $self->_clearContext();
    #END import_bio
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to import_bio:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'import_bio');
    }
    return($metadata);
}




=head2 import_map

  $metadata = $obj->import_map($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is an import_map_params
$metadata is an object_metadata
import_map_params is a reference to a hash where the following keys are defined:
	bioid has a value which is an object_id
	bioWS has a value which is a workspace_id
	mapid has a value which is an object_id
	mapWS has a value which is a workspace_id
	url has a value which is a string
	compressed has a value which is a bool
	overwrite has a value which is a bool
	auth has a value which is a string
	asHash has a value which is a bool
object_id is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
object_type is a string
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is an import_map_params
$metadata is an object_metadata
import_map_params is a reference to a hash where the following keys are defined:
	bioid has a value which is an object_id
	bioWS has a value which is a workspace_id
	mapid has a value which is an object_id
	mapWS has a value which is a workspace_id
	url has a value which is a string
	compressed has a value which is a bool
	overwrite has a value which is a bool
	auth has a value which is a string
	asHash has a value which is a bool
object_id is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
object_type is a string
timestamp is a string
username is a string
workspace_ref is a string


=end text



=item Description

Imports a mapping from a URL

=back

=cut

sub import_map
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to import_map:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'import_map');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN import_map
    $self->_setContext($ctx,$params);
    $params = $self->_validateargs($params,[],{
    	bioid => "default",
    	bioWS => "kbase",
    	mapid => "default",
    	mapWS => "kbase",
    	url => "http://bioseed.mcs.anl.gov/~chenry/exampleObjects/defaultMap.json.gz",
    	compressed => 1,
    	overwrite => 0,
    	asHash => 0
    });
    #Creating the workspace if not already existing
    my $ws = $self->_getWorkspace($params->{mapWS});
	if (!defined($ws)) {
		$self->_createWorkspace($params->{mapWS},"r");
		$ws = $self->_getWorkspace($params->{mapWS});
	}
	#Checking for existing object
	my $obj = $ws->getObject("Mapping",$params->{mapid});
	if (defined($obj) && $params->{overwrite} == 0) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Mapping exists, and overwrite not requested",
							       method_name => 'import_map');
	}
	#Retreiving object from url
	my ($fh1, $compressed_filename) = tempfile();
	close($fh1);
	my $status = getstore($params->{url}, $compressed_filename);
	if ($status != 200) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Unable to fetch from URL",
							       method_name => 'import_map');
	}
	#Uncompressing
	if ($params->{compressed} == 1) {
		my ($fh2, $uncompressed_filename) = tempfile();
		close($fh2);
		gunzip $compressed_filename => $uncompressed_filename;
		$compressed_filename = $uncompressed_filename;
	}
	#Saving object
	open(my $fh, "<", $compressed_filename) || die "$!: $@";
	my @lines = <$fh>;
	close($fh);
	my $string = join("\n",@lines);
	my $data = JSON::XS->new->utf8->decode($string);
	$data->{biochemistry_uuid} = $params->{bioWS}."/".$params->{bioid};
	$data->{uuid} = $params->{mapWS}."/".$params->{mapid};
	$obj = $ws->saveObject("Mapping",$params->{mapid},$data,"import_map",{});
    $metadata = $obj->metadata($params->{asHash});
    $self->_clearContext();
    #END import_map
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to import_map:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'import_map');
    }
    return($metadata);
}




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
	asHash has a value which is a bool
object_id is a string
object_type is a string
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
	asHash has a value which is a bool
object_id is a string
object_type is a string
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
    	retrieveFromURL => 0,
    	asHash => 0,
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
    #Dealing with objects that will be saved as references only
    my $obj;
    if ($params->{workspace} eq "NO_WORKSPACE") {
    	$obj = $self->_saveObjectByRef($params->{type},$params->{id},$params->{data},$params->{command},$params->{metadata});
    } else {
    	my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    	$obj = $ws->saveObject($params->{type},$params->{id},$params->{data},$params->{command},$params->{metadata});	
    }
    $metadata = $obj->metadata($params->{asHash});
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
	asHash has a value which is a bool
object_id is a string
object_type is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
	asHash has a value which is a bool
object_id is a string
object_type is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
    $self->_validateargs($params,["id","type","workspace"],{
    	asHash => 0
    });
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    my $obj = $ws->deleteObject($params->{type},$params->{id});
    $metadata = $obj->metadata($params->{asHash});
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
	asHash has a value which is a bool
object_id is a string
object_type is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
	asHash has a value which is a bool
object_id is a string
object_type is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
    $self->_validateargs($params,["id","type","workspace"],{
    	asHash => 0
    });
    if ($params->{workspace} eq "NO_WORKSPACE") {
    	my $obj = $self->_getObject($params->{id},{throwErrorIfMissing => 1});
    	$metadata = $obj->metadata($params->{asHash});
    	if ($obj->owner() eq $self->_getUsername()) {
    		$obj->permanentDelete();
    	}
    } else {
	    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
	    my $obj = $ws->deleteObjectPermanently($params->{type},$params->{id});
	    $metadata = $obj->metadata($params->{asHash});
    }
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
	asHash has a value which is a bool
	asJSON has a value which is a bool
object_id is a string
object_type is a string
workspace_id is a string
bool is an int
get_object_output is a reference to a hash where the following keys are defined:
	data has a value which is a string
	metadata has a value which is an object_metadata
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
	asHash has a value which is a bool
	asJSON has a value which is a bool
object_id is a string
object_type is a string
workspace_id is a string
bool is an int
get_object_output is a reference to a hash where the following keys are defined:
	data has a value which is a string
	metadata has a value which is an object_metadata
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
    	instance => undef,
    	asHash => 0,
    	asJSON => 0
    });
    my $obj;
    if ($params->{workspace} eq "NO_WORKSPACE") {
    	$obj = $self->_getObject($params->{id});
    } else {
    	my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    	$obj = $ws->getObject($params->{type},$params->{id},{
	    	throwErrorIfMissing => 1,
	    	instance => $params->{instance}
	    });
    }
    my $data;
    if ($params->{asJSON} == 1) {
    	my $JSON = JSON::XS->new->utf8(1);
    	$data = $JSON->encode($obj->data());
    } else {
    	$data = $obj->data();
    }
    $output = {
    	data => $obj->data(),
    	metadata => $obj->metadata($params->{asHash})
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




=head2 get_objects

  $output = $obj->get_objects($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_objects_params
$output is a reference to a list where each element is a get_object_output
get_objects_params is a reference to a hash where the following keys are defined:
	ids has a value which is a reference to a list where each element is an object_id
	types has a value which is a reference to a list where each element is an object_type
	workspaces has a value which is a reference to a list where each element is a workspace_id
	instances has a value which is a reference to a list where each element is an int
	auth has a value which is a string
	asHash has a value which is a bool
	asJSON has a value which is a bool
object_id is a string
object_type is a string
workspace_id is a string
bool is an int
get_object_output is a reference to a hash where the following keys are defined:
	data has a value which is a string
	metadata has a value which is an object_metadata
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a get_objects_params
$output is a reference to a list where each element is a get_object_output
get_objects_params is a reference to a hash where the following keys are defined:
	ids has a value which is a reference to a list where each element is an object_id
	types has a value which is a reference to a list where each element is an object_type
	workspaces has a value which is a reference to a list where each element is a workspace_id
	instances has a value which is a reference to a list where each element is an int
	auth has a value which is a string
	asHash has a value which is a bool
	asJSON has a value which is a bool
object_id is a string
object_type is a string
workspace_id is a string
bool is an int
get_object_output is a reference to a hash where the following keys are defined:
	data has a value which is a string
	metadata has a value which is an object_metadata
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
timestamp is a string
username is a string
workspace_ref is a string


=end text



=item Description

Retrieves the specified objects from the specified workspaces.
Both the object data and metadata are returned.
This commands provides access to all versions of the objects via the instances parameter.

=back

=cut

sub get_objects
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to get_objects:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_objects');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($output);
    #BEGIN get_objects
    $self->_setContext($ctx,$params);
    $params = $self->_validateargs($params,["ids","types","workspaces"],{
    	instances => [],
    	asHash => 0,
    	asJSON => 0
    });
    $output = [];
    my $idHash = {};
    my $refs = [];
    my $refIndecies = {};
    my $wsHash = {};
	for (my $i=0; $i < @{$params->{ids}}; $i++) {
    	if ($params->{workspaces}->[$i] eq "NO_WORKSPACE") {
    		$refIndecies->{$params->{ids}->[$i]} = $i;
    		push(@{$refs},$params->{ids}->[$i]);
    	} else {
    		$idHash->{$params->{workspaces}->[$i]}->{$params->{types}->[$i]}->{$params->{ids}->[$i]} = $i;
    		if (!defined($wsHash->{$params->{workspaces}->[$i]})) {
    			$wsHash->{$params->{workspaces}->[$i]} = {
    				types => [],ids => [],instances => []
    			}
    		}
    		push(@{$wsHash->{$params->{workspaces}->[$i]}->{types}},$params->{types}->[$i]);
    		push(@{$wsHash->{$params->{workspaces}->[$i]}->{ids}},$params->{ids}->[$i]);
    		push(@{$wsHash->{$params->{workspaces}->[$i]}->{instances}},$params->{instances}->[$i]);
   		}
    }
    #Retreiving references
    if (@{$refs} > 0) {
    	my $objs = $self->_getObjects($refs,{throwErrorIfMissing => 1});
    	for (my $i=0; $i < @{$objs}; $i++) {
    		$output->[$refIndecies->{$refs->[$i]}] = {
    			data => $objs->[$i]->data(),
    			metadata => $objs->[$i]->metadata($params->{asHash})
    		};
    	}
    }
    #Retrieving workspace objects
    if (keys(%{$wsHash}) > 0) {
    	my $wsList = $self->_getWorkspaces([keys(%{$wsHash})],{throwErrorIfMissing => 1});
    	for (my $i=0; $i < @{$wsList}; $i++) {
    		my $ws = $wsList->[$i]->id();
    		my $objs = $wsList->[$i]->getObjects($wsHash->{$ws}->{types},$wsHash->{$ws}->{ids},$wsHash->{$ws}->{instances},{throwErrorIfMissing => 1});
    		for (my $j=0; $j < @{$objs}; $j++) {
    			$output->[$idHash->{$ws}->{$wsHash->{$ws}->{types}->[$j]}->{$wsHash->{$ws}->{ids}->[$j]}] = {
	    			data => $objs->[$j]->data(),
	    			metadata => $objs->[$j]->metadata($params->{asHash})
	    		};
    		} 
    	}
    }
    if ($params->{asJSON} == 1) {
    	my $JSON = JSON::XS->new->utf8(1);
    	for (my $i=0; $i < @{$output}; $i++) {
    		$output->[$i]->{data} = $JSON->encode($output->[$i]->{data});
    	}
    }
    $self->_clearContext();
    #END get_objects
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_objects:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_objects');
    }
    return($output);
}




=head2 get_object_by_ref

  $output = $obj->get_object_by_ref($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_object_by_ref_params
$output is a get_object_output
get_object_by_ref_params is a reference to a hash where the following keys are defined:
	reference has a value which is a workspace_ref
	auth has a value which is a string
	asHash has a value which is a bool
	asJSON has a value which is a bool
workspace_ref is a string
bool is an int
get_object_output is a reference to a hash where the following keys are defined:
	data has a value which is a string
	metadata has a value which is an object_metadata
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
object_id is a string
object_type is a string
timestamp is a string
username is a string
workspace_id is a string

</pre>

=end html

=begin text

$params is a get_object_by_ref_params
$output is a get_object_output
get_object_by_ref_params is a reference to a hash where the following keys are defined:
	reference has a value which is a workspace_ref
	auth has a value which is a string
	asHash has a value which is a bool
	asJSON has a value which is a bool
workspace_ref is a string
bool is an int
get_object_output is a reference to a hash where the following keys are defined:
	data has a value which is a string
	metadata has a value which is an object_metadata
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
object_id is a string
object_type is a string
timestamp is a string
username is a string
workspace_id is a string


=end text



=item Description

Retrieves the specified object from the specified workspace.
Both the object data and metadata are returned.
This commands provides access to all versions of the object via the instance parameter.

=back

=cut

sub get_object_by_ref
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to get_object_by_ref:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_object_by_ref');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($output);
    #BEGIN get_object_by_ref
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["reference"],{
    	asHash => 0,
    	asJSON => 0
    });
    my $obj = $self->_getObject($params->{reference},{throwErrorIfMissing => 1});
    my $data;
    if ($params->{asJSON} == 1) {
    	my $JSON = JSON::XS->new->utf8(1);
    	$data = $JSON->encode($obj->data());
    } else {
    	$data = $obj->data();
    }
    $output = {
    	data => $data,
    	metadata => $obj->metadata($params->{asHash})
    };
    $self->_clearContext();
    #END get_object_by_ref
    my @_bad_returns;
    (ref($output) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_object_by_ref:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_object_by_ref');
    }
    return($output);
}




=head2 save_object_by_ref

  $metadata = $obj->save_object_by_ref($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a save_object_by_ref_params
$metadata is an object_metadata
save_object_by_ref_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	data has a value which is an ObjectData
	command has a value which is a string
	metadata has a value which is a reference to a hash where the key is a string and the value is a string
	reference has a value which is a workspace_ref
	json has a value which is a bool
	compressed has a value which is a bool
	retrieveFromURL has a value which is a bool
	replace has a value which is a bool
	auth has a value which is a string
	asHash has a value which is a bool
object_id is a string
object_type is a string
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int
workspace_ref is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
timestamp is a string
username is a string
workspace_id is a string

</pre>

=end html

=begin text

$params is a save_object_by_ref_params
$metadata is an object_metadata
save_object_by_ref_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	data has a value which is an ObjectData
	command has a value which is a string
	metadata has a value which is a reference to a hash where the key is a string and the value is a string
	reference has a value which is a workspace_ref
	json has a value which is a bool
	compressed has a value which is a bool
	retrieveFromURL has a value which is a bool
	replace has a value which is a bool
	auth has a value which is a string
	asHash has a value which is a bool
object_id is a string
object_type is a string
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int
workspace_ref is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
timestamp is a string
username is a string
workspace_id is a string


=end text



=item Description

Retrieves the specified object from the specified workspace.
Both the object data and metadata are returned.
This commands provides access to all versions of the object via the instance parameter.

=back

=cut

sub save_object_by_ref
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to save_object_by_ref:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'save_object_by_ref');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN save_object_by_ref
    $self->_setContext($ctx,$params);
    $params = $self->_validateargs($params,["data","id","type"],{
    	reference => undef,
    	command => undef,
    	metadata => {},
    	json => 0,
    	compressed => 0,
    	retrieveFromURL => 0,
    	asHash => 0,
    	replace => 0
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
    #Dealing with objects that will be saved as references only
    my $obj = $self->_saveObjectByRef($params->{type},$params->{id},$params->{data},$params->{command},$params->{metadata},$params->{reference},$params->{replace});
    $metadata = $obj->metadata($params->{asHash});
	$self->_clearContext();
    #END save_object_by_ref
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to save_object_by_ref:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'save_object_by_ref');
    }
    return($metadata);
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
	asHash has a value which is a bool
object_id is a string
object_type is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
	asHash has a value which is a bool
object_id is a string
object_type is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
    	instance => undef,
    	asHash => 0
    });
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    my $obj = $ws->getObject($params->{type},$params->{id},{
    	throwErrorIfMissing => 1,
    	instance => $params->{instance}
    });
    $metadata = $obj->metadata($params->{asHash});
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




=head2 get_objectmeta_by_ref

  $metadata = $obj->get_objectmeta_by_ref($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_objectmeta_by_ref_params
$metadata is an object_metadata
get_objectmeta_by_ref_params is a reference to a hash where the following keys are defined:
	reference has a value which is a workspace_ref
	auth has a value which is a string
	asHash has a value which is a bool
workspace_ref is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
object_id is a string
object_type is a string
timestamp is a string
username is a string
workspace_id is a string

</pre>

=end html

=begin text

$params is a get_objectmeta_by_ref_params
$metadata is an object_metadata
get_objectmeta_by_ref_params is a reference to a hash where the following keys are defined:
	reference has a value which is a workspace_ref
	auth has a value which is a string
	asHash has a value which is a bool
workspace_ref is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
object_id is a string
object_type is a string
timestamp is a string
username is a string
workspace_id is a string


=end text



=item Description

Retrieves the specified object from the specified workspace.
Both the object data and metadata are returned.
This commands provides access to all versions of the object via the instance parameter.

=back

=cut

sub get_objectmeta_by_ref
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to get_objectmeta_by_ref:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_objectmeta_by_ref');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($metadata);
    #BEGIN get_objectmeta_by_ref
	$self->_setContext($ctx,$params);
    $self->_validateargs($params,["reference"],{
    	asHash => 0
    });
    my $obj = $self->_getObject($params->{reference},{throwErrorIfMissing => 1});
    $metadata = $obj->metadata($params->{asHash});
    $self->_clearContext();
    #END get_objectmeta_by_ref
    my @_bad_returns;
    (ref($metadata) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"metadata\" (value was \"$metadata\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_objectmeta_by_ref:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_objectmeta_by_ref');
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
	asHash has a value which is a bool
object_id is a string
object_type is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
	asHash has a value which is a bool
object_id is a string
object_type is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
    	instance => undef,
    	asHash => 0
    });
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    my $obj = $ws->revertObject($params->{type},$params->{id},$params->{instance});
    $metadata = $obj->metadata($params->{asHash});
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
	new_workspace_url has a value which is a string
	new_id has a value which is an object_id
	new_workspace has a value which is a workspace_id
	source_id has a value which is an object_id
	instance has a value which is an int
	type has a value which is an object_type
	source_workspace has a value which is a workspace_id
	auth has a value which is a string
	asHash has a value which is a bool
object_id is a string
workspace_id is a string
object_type is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a copy_object_params
$metadata is an object_metadata
copy_object_params is a reference to a hash where the following keys are defined:
	new_workspace_url has a value which is a string
	new_id has a value which is an object_id
	new_workspace has a value which is a workspace_id
	source_id has a value which is an object_id
	instance has a value which is an int
	type has a value which is an object_type
	source_workspace has a value which is a workspace_id
	auth has a value which is a string
	asHash has a value which is a bool
object_id is a string
workspace_id is a string
object_type is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
    	instance => undef,
    	asHash => 0,
    	new_workspace_url => undef
    });
    my $sourcews = $self->_getWorkspace($params->{source_workspace},{throwErrorIfMissing => 1});
    my $obj = $sourcews->getObject($params->{type},$params->{source_id},{
    	throwErrorIfMissing => 1,
    	instance => $params->{instance}
    });
    #Copying objects to other workspace servers
    if (defined($params->{new_workspace_url})) {
		my $destClient = Bio::KBase::workspaceService::Client->new($params->{new_workspace_url});
    	my $output = $self->get_workspacemeta({
    		workspace => $params->{new_workspace},
    		auth => $self->_getContext->{_override}->{_authentication}
    	});
        if ($destClient->has_object({
    		id => $params->{new_id},
    		type => $obj->type(),
    		workspace => $params->{new_workspace},
    		auth => $self->_getContext->{_override}->{_authentication}
    	}) == 1) {
	   		my $otherMeta = $destClient->get_objectmeta({
		    	id => $params->{new_id},
		    	type => $obj->type(),
		    	workspace => $params->{new_workspace},
		    	auth => $self->_getContext->{_override}->{_authentication},
		    	asHash => 1
	   		});
			if ($otherMeta->{instance} < $obj->instance()) {
				my $compareObj = $sourcews->getObject($obj->type(),$obj->id(),{instance => $otherMeta->{instance}});
				if ($compareObj->chsum() eq $otherMeta->{chsum}) {
					#Copying over all instances of object since the last sync
					for (my $j=($otherMeta->{instance}+1); $j <= $obj->instance();$j++) {
						my $objInst = $sourcews->getObject($obj->type(),$obj->id(),{instance => $j});
						$metadata = $destClient->save_object({
							id => $params->{new_id},
							type => $objInst->type(),
							data => $objInst->data(),
							workspace => $params->{new_workspace},
							command => $objInst->command(),
							metadata => $objInst->meta(),
							auth => $self->_getContext->{_override}->{_authentication},
							json => 0,
							compressed => 0,
							retrieveFromURL => 0,
							asHash => 0
						});
					}
				} else {
					#Just save the current version if the versions don't overlap
					$metadata = $destClient->save_object({
						id => $params->{new_id},
						type => $obj->type(),
						data => $obj->data(),
						workspace => $params->{new_workspace},
						command => "copy_object",
						metadata => $obj->meta(),
						auth => $self->_getContext->{_override}->{_authentication},
						json => 0,
						compressed => 0,
						retrieveFromURL => 0,
						asHash => 0
					});
				}
			} elsif ($otherMeta->{instance} > $obj->instance()) {
				my $compareMeta = $destClient->get_objectmeta({
					id => $params->{new_id},
					type => $obj->type(),
					instance => $obj->instance(),
					workspace => $params->{new_workspace},
					auth => $self->_getContext->{_override}->{_authentication},
					asHash => 1
   				});
  				if ($compareMeta->{chsum} eq $obj->chsum()) {
					#The other object is more updated than this object, so do nothing
				} else {
					#Just save the current version if the versions don't overlap
					$metadata = $destClient->save_object({
						id => $params->{new_id},
						type => $obj->type(),
						data => $obj->data(),
						workspace => $params->{new_workspace},
						command => "copy_object",
						metadata => $obj->meta(),
						auth => $self->_getContext->{_override}->{_authentication},
						json => 0,
						compressed => 0,
						retrieveFromURL => 0,
						asHash => 0
					});
				}
			} elsif ($otherMeta->{chsum} ne $obj->chsum()) {
				#Just save the current version if the versions are identical but don't overlap
				$metadata = $destClient->save_object({
					id => $params->{new_id},
					type => $obj->type(),
					data => $obj->data(),
					workspace => $params->{new_workspace},
					command => "copy_object",
					metadata => $obj->meta(),
					auth => $self->_getContext->{_override}->{_authentication},
					json => 0,
					compressed => 0,
					retrieveFromURL => 0,
					asHash => 0
				});
			}
	   	} else {
			for (my $j=0; $j <= $obj->instance();$j++) {
				my $objInst = $sourcews->getObject($obj->type(),$obj->id(),{instance => $j});
				$metadata = $destClient->save_object({
					id => $params->{new_id},
					type => $objInst->type(),
					data => $objInst->data(),
					workspace => $params->{new_workspace},
					command => $objInst->command(),
					metadata => $objInst->meta(),
					auth => $self->_getContext->{_override}->{_authentication},
					json => 0,
					compressed => 0,
					retrieveFromURL => 0,
					asHash => 0
				});
			}
		}
	} else {
		my $newobj;
		my $ws = $self->_getWorkspace($params->{new_workspace},{throwErrorIfMissing => 1});
		if (defined($ws->objects()->{$obj->type()}->{$params->{new_id}})) {
			my $otherObj = $ws->getObject($obj->type(),$params->{new_id});
			if ($otherObj->instance() < $obj->instance()) {
				my $compareObj = $sourcews->getObject($obj->type(),$obj->id(),{instance => $otherObj->instance()});
				if ($compareObj->chsum() eq $otherObj->chsum()) {
					#Copying over all instances of object since the last sync
					for (my $j=($otherObj->instance()+1); $j <= $obj->instance();$j++) {
						my $objInst = $sourcews->getObject($obj->type(),$obj->id(),{instance => $j});
						$newobj = $ws->saveObject(
							$objInst->type(),
							$params->{new_id},
							$objInst->data(),
							$objInst->command(),
							$objInst->meta()
						);
					}
				} else {
					#Just save the current version if the versions don't overlap
					$newobj = $ws->saveObject(
						$obj->type(),
						$params->{new_id},
						$obj->data(),
						"copy_object",
						$obj->meta()
					);
				}
			} elsif ($otherObj->instance() > $obj->instance()) {
				my $compareObj = $ws->getObject($obj->type(),$params->{new_id},{instance => $obj->instance()});
				if ($compareObj->chsum() eq $obj->chsum()) {
					#The other object is more updated than this object, so do nothing
				} else {
					#Just save the current version if the versions don't overlap
					$newobj = $ws->saveObject(
						$obj->type(),
						$params->{new_id},
						$obj->data(),
						"copy_object",
						$obj->meta()
					);
				}
			} elsif ($otherObj->chsum() ne $obj->chsum()) {
				#Just save the current version if the versions are identical but don't overlap
				$newobj = $ws->saveObject(
					$obj->type(),
					$params->{new_id},
					$obj->data(),
					"copy_object",
					$obj->meta()
				);
			}
		} else {
			#Copying over all instances of object if the object doesn't exist in other workspace
			for (my $j=0; $j <= $obj->instance();$j++) {
				my $objInst = $sourcews->getObject($obj->type(),$obj->id(),{instance => $j});
				$newobj = $ws->saveObject(
					$objInst->type(),
					$params->{new_id},
					$objInst->data(),
					$objInst->command(),
					$objInst->meta()
				);
			}
			
		}
		$metadata = $newobj->metadata($params->{asHash});
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
	new_workspace_url has a value which is a string
	new_id has a value which is an object_id
	new_workspace has a value which is a workspace_id
	source_id has a value which is an object_id
	type has a value which is an object_type
	source_workspace has a value which is a workspace_id
	auth has a value which is a string
	asHash has a value which is a bool
object_id is a string
workspace_id is a string
object_type is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a move_object_params
$metadata is an object_metadata
move_object_params is a reference to a hash where the following keys are defined:
	new_workspace_url has a value which is a string
	new_id has a value which is an object_id
	new_workspace has a value which is a workspace_id
	source_id has a value which is an object_id
	type has a value which is an object_type
	source_workspace has a value which is a workspace_id
	auth has a value which is a string
	asHash has a value which is a bool
object_id is a string
workspace_id is a string
object_type is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
    $self->_validateargs($params,["new_id","new_workspace","source_id","type","source_workspace"],{
    	asHash => 0
    });
    my $ws = $self->_getWorkspace($params->{source_workspace},{throwErrorIfMissing => 1});
    my $obj = $ws->getObject($params->{type},$params->{source_id},{
    	throwErrorIfMissing => 1
    });
    if ($params->{new_workspace} ne $params->{source_workspace}) {
    	$ws->deleteObject($params->{type},$params->{source_id});
    	$ws = $self->_getWorkspace($params->{new_workspace},{throwErrorIfMissing => 1});
    	$obj = $ws->saveObject($params->{type},$params->{new_id},$obj->data(),"move_object",$obj->meta());
    	$metadata = $obj->metadata($params->{asHash});
    } elsif ($params->{new_id} eq $params->{source_id}) {
    	$metadata = $obj->metadata($params->{asHash});
    } else {
    	$ws->deleteObject($params->{type},$params->{source_id});
    	$obj = $ws->saveObject($params->{type},$params->{new_id},$obj->data(),"move_object",$obj->meta());
    	$metadata = $obj->metadata($params->{asHash});
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
	asHash has a value which is a bool
object_id is a string
object_type is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
	asHash has a value which is a bool
object_id is a string
object_type is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
    $self->_validateargs($params,["id","type","workspace"],{
    	asHash => 0
    });
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    my $history = $ws->getObjectHistory($params->{type},$params->{id});
    for (my $i=0; $i < @{$history}; $i++) {
    	$metadatas->[$history->[$i]->instance()] = $history->[$i]->metadata($params->{asHash});
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
	asHash has a value which is a bool
workspace_id is a string
permission is a string
bool is an int
workspace_metadata is a reference to a list containing 6 items:
	0: (id) a workspace_id
	1: (owner) a username
	2: (moddate) a timestamp
	3: (objects) an int
	4: (user_permission) a permission
	5: (global_permission) a permission
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
	asHash has a value which is a bool
workspace_id is a string
permission is a string
bool is an int
workspace_metadata is a reference to a list containing 6 items:
	0: (id) a workspace_id
	1: (owner) a username
	2: (moddate) a timestamp
	3: (objects) an int
	4: (user_permission) a permission
	5: (global_permission) a permission
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
    	default_permission => "n",
    	asHash => 0
    });
    my $ws = $self->_getWorkspace($params->{workspace});
    if (defined($ws)) {
    	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Cannot create workspace because workspace already exists!",
		method_name => 'create_workspace');
    }
    $ws = $self->_createWorkspace($params->{workspace},$params->{default_permission});
    $metadata = $ws->metadata($params->{asHash});
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
	asHash has a value which is a bool
workspace_id is a string
bool is an int
workspace_metadata is a reference to a list containing 6 items:
	0: (id) a workspace_id
	1: (owner) a username
	2: (moddate) a timestamp
	3: (objects) an int
	4: (user_permission) a permission
	5: (global_permission) a permission
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
	asHash has a value which is a bool
workspace_id is a string
bool is an int
workspace_metadata is a reference to a list containing 6 items:
	0: (id) a workspace_id
	1: (owner) a username
	2: (moddate) a timestamp
	3: (objects) an int
	4: (user_permission) a permission
	5: (global_permission) a permission
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
    $self->_validateargs($params,["workspace"],{
    	asHash => 0
    });
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
	$metadata = $ws->metadata($params->{asHash});
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
	asHash has a value which is a bool
workspace_id is a string
bool is an int
workspace_metadata is a reference to a list containing 6 items:
	0: (id) a workspace_id
	1: (owner) a username
	2: (moddate) a timestamp
	3: (objects) an int
	4: (user_permission) a permission
	5: (global_permission) a permission
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
	asHash has a value which is a bool
workspace_id is a string
bool is an int
workspace_metadata is a reference to a list containing 6 items:
	0: (id) a workspace_id
	1: (owner) a username
	2: (moddate) a timestamp
	3: (objects) an int
	4: (user_permission) a permission
	5: (global_permission) a permission
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
    $self->_validateargs($params,["workspace"],{
    	asHash => 0
    });
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    $ws->permanentDelete();
    $metadata = $ws->metadata($params->{asHash});
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
	new_workspace_url has a value which is a string
	current_workspace has a value which is a workspace_id
	default_permission has a value which is a permission
	auth has a value which is a string
	asHash has a value which is a bool
workspace_id is a string
permission is a string
bool is an int
workspace_metadata is a reference to a list containing 6 items:
	0: (id) a workspace_id
	1: (owner) a username
	2: (moddate) a timestamp
	3: (objects) an int
	4: (user_permission) a permission
	5: (global_permission) a permission
username is a string
timestamp is a string

</pre>

=end html

=begin text

$params is a clone_workspace_params
$metadata is a workspace_metadata
clone_workspace_params is a reference to a hash where the following keys are defined:
	new_workspace has a value which is a workspace_id
	new_workspace_url has a value which is a string
	current_workspace has a value which is a workspace_id
	default_permission has a value which is a permission
	auth has a value which is a string
	asHash has a value which is a bool
workspace_id is a string
permission is a string
bool is an int
workspace_metadata is a reference to a list containing 6 items:
	0: (id) a workspace_id
	1: (owner) a username
	2: (moddate) a timestamp
	3: (objects) an int
	4: (user_permission) a permission
	5: (global_permission) a permission
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
    	default_permissions => "n",
    	asHash => 0,
    	new_workspace_url => undef
    });
    my $sourcews = $self->_getWorkspace($params->{current_workspace},{throwErrorIfMissing => 1});
    my $objs = $sourcews->getAllObjects();
    if (defined($params->{new_workspace_url})) {
		my $destClient = Bio::KBase::workspaceService::Client->new($params->{new_workspace_url});
    	my $output;
    	eval {
    		$output = $self->get_workspacemeta({
    			workspace => $params->{new_workspace},
    			auth => $self->_getContext->{_override}->{_authentication}
    		});
    	};
    	if (!defined($output)) {
    		$self->create_workspace({
    			workspace => $params->{new_workspace},
    			default_permission => $params->{default_permissions},
    			auth => $self->_getContext->{_override}->{_authentication}
    		});
    	}
    	for (my $i=0; $i < @{$objs}; $i++) {
    		my $obj = $objs->[$i];
    		if ($destClient->has_object({
    			id => $obj->id(),
    			type => $obj->type(),
    			workspace => $params->{new_workspace},
    			auth => $self->_getContext->{_override}->{_authentication}
    		}) == 1) {
   				my $otherMeta = $destClient->get_objectmeta({
	    			id => $obj->id(),
	    			type => $obj->type(),
	    			workspace => $params->{new_workspace},
	    			auth => $self->_getContext->{_override}->{_authentication},
	    			asHash => 1
   				});
    			if ($otherMeta->{instance} < $obj->instance()) {
    				my $compareObj = $sourcews->getObject($obj->type(),$obj->id(),{instance => $otherMeta->{instance}});
    				if ($compareObj->chsum() eq $otherMeta->{chsum}) {
    					#Copying over all instances of object since the last sync
    					for (my $j=($otherMeta->{instance}+1); $j <= $obj->instance();$j++) {
			    			my $objInst = $sourcews->getObject($obj->type(),$obj->id(),{instance => $j});
			    			$destClient->save_object({
		    					id => $objInst->id(),
								type => $objInst->type(),
								data => $objInst->data(),
								workspace => $params->{new_workspace},
								command => $objInst->command(),
								metadata => $objInst->meta(),
								auth => $self->_getContext->{_override}->{_authentication},
								json => 0,
								compressed => 0,
								retrieveFromURL => 0,
								asHash => 0
		    				});
			    		}
    				} else {
    					#Just save the current version if the versions don't overlap
    					$destClient->save_object({
	    					id => $obj->id(),
							type => $obj->type(),
							data => $obj->data(),
							workspace => $params->{new_workspace},
							command => "clone_workspace",
							metadata => $obj->meta(),
							auth => $self->_getContext->{_override}->{_authentication},
							json => 0,
							compressed => 0,
							retrieveFromURL => 0,
							asHash => 0
	    				});
    				}
    			} elsif ($otherMeta->{instance} > $obj->instance()) {
    				my $compareMeta = $destClient->get_objectmeta({
		    			id => $obj->id(),
		    			type => $obj->type(),
		    			instance => $obj->instance(),
		    			workspace => $params->{new_workspace},
		    			auth => $self->_getContext->{_override}->{_authentication},
		    			asHash => 1
	   				});
      				if ($compareMeta->{chsum} eq $obj->chsum()) {
    					#The other object is more updated than this object, so do nothing
    				} else {
    					#Just save the current version if the versions don't overlap
    					$destClient->save_object({
	    					id => $obj->id(),
							type => $obj->type(),
							data => $obj->data(),
							workspace => $params->{new_workspace},
							command => "clone_workspace",
							metadata => $obj->meta(),
							auth => $self->_getContext->{_override}->{_authentication},
							json => 0,
							compressed => 0,
							retrieveFromURL => 0,
							asHash => 0
	    				});
    				}
    			} elsif ($otherMeta->{chsum} ne $obj->chsum()) {
    				#Just save the current version if the versions are identical but don't overlap
    				$destClient->save_object({
    					id => $obj->id(),
						type => $obj->type(),
						data => $obj->data(),
						workspace => $params->{new_workspace},
						command => "clone_workspace",
						metadata => $obj->meta(),
						auth => $self->_getContext->{_override}->{_authentication},
						json => 0,
						compressed => 0,
						retrieveFromURL => 0,
						asHash => 0
    				});
    			}
       		} else {
    			for (my $j=0; $j <= $obj->instance();$j++) {
    				my $objInst = $sourcews->getObject($obj->type(),$obj->id(),{instance => $j});
    				$destClient->save_object({
    					id => $objInst->id(),
						type => $objInst->type(),
						data => $objInst->data(),
						workspace => $params->{new_workspace},
						command => $objInst->command(),
						metadata => $objInst->meta(),
						auth => $self->_getContext->{_override}->{_authentication},
						json => 0,
						compressed => 0,
						retrieveFromURL => 0,
						asHash => 0
    				});
    			}
    		}
    	}
    	$metadata = $destClient->get_workspacemeta({
    		workspace => $params->{new_workspace},
			auth => $self->_getContext->{_override}->{_authentication},
			asHash => $params->{asHash}
    	});
    } else {
    	my $ws = $self->_getWorkspace($params->{new_workspace});
    	if (!defined($ws)) {
    		$ws = $self->_createWorkspace($params->{new_workspace},$params->{default_permission});
    	}
    	for (my $i=0; $i < @{$objs}; $i++) {
    		my $obj = $objs->[$i];
    		if (defined($ws->objects()->{$obj->type()}->{$obj->id()})) {
    			my $otherObj = $ws->getObject($obj->type(),$obj->id());
    			if ($otherObj->instance() < $obj->instance()) {
    				my $compareObj = $sourcews->getObject($obj->type(),$obj->id(),{instance => $otherObj->instance()});
    				if ($compareObj->chsum() eq $otherObj->chsum()) {
    					#Copying over all instances of object since the last sync
    					for (my $j=($otherObj->instance()+1); $j <= $obj->instance();$j++) {
			    			my $objInst = $sourcews->getObject($obj->type(),$obj->id(),{instance => $j});
			    			$ws->saveObject(
			    				$objInst->type(),
			    				$objInst->id(),
			    				$objInst->data(),
			    				$objInst->command(),
			    				$objInst->meta()
			    			);
			    		}
    				} else {
    					#Just save the current version if the versions don't overlap
    					$ws->saveObject(
		    				$obj->type(),
		    				$obj->id(),
		    				$obj->data(),
		    				"clone_workspace",
		    				$obj->meta()
		    			);
    				}
    			} elsif ($otherObj->instance() > $obj->instance()) {
    				my $compareObj = $ws->getObject($obj->type(),$obj->id(),{instance => $obj->instance()});
    				if ($compareObj->chsum() eq $obj->chsum()) {
    					#The other object is more updated than this object, so do nothing
    				} else {
    					#Just save the current version if the versions don't overlap
    					$ws->saveObject(
		    				$obj->type(),
		    				$obj->id(),
		    				$obj->data(),
		    				"clone_workspace",
		    				$obj->meta()
		    			);
    				}
    			} elsif ($otherObj->chsum() ne $obj->chsum()) {
    				#Just save the current version if the versions are identical but don't overlap
    				$ws->saveObject(
		    			$obj->type(),
		    			$obj->id(),
		    			$obj->data(),
		    			"clone_workspace",
		    			$obj->meta()
		    		);
    			}
    		} else {
    			#Copying over all instances of object if the object doesn't exist in other workspace
    			for (my $j=0; $j <= $obj->instance();$j++) {
	    			my $objInst = $sourcews->getObject($obj->type(),$obj->id(),{instance => $j});
	    			$ws->saveObject(
	    				$objInst->type(),
	    				$objInst->id(),
	    				$objInst->data(),
	    				$objInst->command(),
	    				$objInst->meta()
	    			);
	    		}
    		}
    	}
    	$metadata = $ws->metadata($params->{asHash});
    }
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
	asHash has a value which is a bool
bool is an int
workspace_metadata is a reference to a list containing 6 items:
	0: (id) a workspace_id
	1: (owner) a username
	2: (moddate) a timestamp
	3: (objects) an int
	4: (user_permission) a permission
	5: (global_permission) a permission
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
	asHash has a value which is a bool
bool is an int
workspace_metadata is a reference to a list containing 6 items:
	0: (id) a workspace_id
	1: (owner) a username
	2: (moddate) a timestamp
	3: (objects) an int
	4: (user_permission) a permission
	5: (global_permission) a permission
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
    $self->_validateargs($params,[],{
    	asHash => 0
    });
    #Getting user-specific permissions
    my $wsu = $self->_getWorkspaceUser($self->_getUsername());
    if (!defined($wsu)) {
    	$wsu = $self->_createWorkspaceUser($self->_getUsername());
    }
    my $wss = $wsu->getUserWorkspaces();
    $workspaces = [];
    for (my $i=0; $i < @{$wss}; $i++) {
    	push(@{$workspaces},$wss->[$i]->metadata($params->{asHash}));
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
	asHash has a value which is a bool
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
	asHash has a value which is a bool
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 11 items:
	0: (id) an object_id
	1: (type) an object_type
	2: (moddate) a timestamp
	3: (instance) an int
	4: (command) a string
	5: (lastmodifier) a username
	6: (owner) a username
	7: (workspace) a workspace_id
	8: (ref) a workspace_ref
	9: (chsum) a string
	10: (metadata) a reference to a hash where the key is a string and the value is a string
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
    	showDeletedObject => 0,
    	asHash => 0
    });
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
	$objects = [];
	my $objs = $ws->getAllObjects($params->{type});    
	foreach my $obj (@{$objs}) {
		if ($obj->command() ne "delete" || $params->{showDeletedObject} == 1) {
			push(@{$objects},$obj->metadata($params->{asHash}));
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
	asHash has a value which is a bool
permission is a string
workspace_id is a string
bool is an int
workspace_metadata is a reference to a list containing 6 items:
	0: (id) a workspace_id
	1: (owner) a username
	2: (moddate) a timestamp
	3: (objects) an int
	4: (user_permission) a permission
	5: (global_permission) a permission
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
	asHash has a value which is a bool
permission is a string
workspace_id is a string
bool is an int
workspace_metadata is a reference to a list containing 6 items:
	0: (id) a workspace_id
	1: (owner) a username
	2: (moddate) a timestamp
	3: (objects) an int
	4: (user_permission) a permission
	5: (global_permission) a permission
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
    $self->_validateargs($params,["new_permission","workspace"],{
    	asHash => 0
    });
    my $ws = $self->_getWorkspace($params->{workspace},{throwErrorIfMissing => 1});
    $ws->setDefaultPermissions($params->{new_permission});
    $metadata = $ws->metadata($params->{asHash});
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




=head2 get_user_settings

  $output = $obj->get_user_settings($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_user_settings_params
$output is a user_settings
get_user_settings_params is a reference to a hash where the following keys are defined:
	auth has a value which is a string
user_settings is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
workspace_id is a string

</pre>

=end html

=begin text

$params is a get_user_settings_params
$output is a user_settings
get_user_settings_params is a reference to a hash where the following keys are defined:
	auth has a value which is a string
user_settings is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
workspace_id is a string


=end text



=item Description

Retrieves settings for user account, including currently selected workspace

=back

=cut

sub get_user_settings
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to get_user_settings:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_user_settings');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($output);
    #BEGIN get_user_settings
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,[],{});
    my $wsu = $self->_getWorkspaceUser($self->_getUsername(),{createIfMissing => 1});
    $output = $wsu->settings();
	$self->_clearContext();
    #END get_user_settings
    my @_bad_returns;
    (ref($output) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_user_settings:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_user_settings');
    }
    return($output);
}




=head2 set_user_settings

  $output = $obj->set_user_settings($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a set_user_settings_params
$output is a user_settings
set_user_settings_params is a reference to a hash where the following keys are defined:
	setting has a value which is a string
	value has a value which is a string
	auth has a value which is a string
user_settings is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
workspace_id is a string

</pre>

=end html

=begin text

$params is a set_user_settings_params
$output is a user_settings
set_user_settings_params is a reference to a hash where the following keys are defined:
	setting has a value which is a string
	value has a value which is a string
	auth has a value which is a string
user_settings is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
workspace_id is a string


=end text



=item Description

Retrieves settings for user account, including currently selected workspace

=back

=cut

sub set_user_settings
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to set_user_settings:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'set_user_settings');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($output);
    #BEGIN set_user_settings
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["setting","value"],{});
    my $wsu = $self->_getWorkspaceUser($self->_getUsername(),{createIfMissing => 1});
    $wsu->updateSettings($params->{setting},$params->{value});
    $output = $wsu->settings();
	$self->_clearContext();
    #END set_user_settings
    my @_bad_returns;
    (ref($output) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to set_user_settings:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'set_user_settings');
    }
    return($output);
}




=head2 queue_job

  $job = $obj->queue_job($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a queue_job_params
$job is a JobObject
queue_job_params is a reference to a hash where the following keys are defined:
	auth has a value which is a string
	state has a value which is a string
	type has a value which is a string
	queuecommand has a value which is a string
	jobdata has a value which is a reference to a hash where the key is a string and the value is a string
JobObject is a reference to a hash where the following keys are defined:
	id has a value which is a job_id
	type has a value which is a string
	auth has a value which is a string
	status has a value which is a string
	jobdata has a value which is a reference to a hash where the key is a string and the value is a string
	queuetime has a value which is a string
	starttime has a value which is a string
	completetime has a value which is a string
	owner has a value which is a string
	queuecommand has a value which is a string
job_id is a string

</pre>

=end html

=begin text

$params is a queue_job_params
$job is a JobObject
queue_job_params is a reference to a hash where the following keys are defined:
	auth has a value which is a string
	state has a value which is a string
	type has a value which is a string
	queuecommand has a value which is a string
	jobdata has a value which is a reference to a hash where the key is a string and the value is a string
JobObject is a reference to a hash where the following keys are defined:
	id has a value which is a job_id
	type has a value which is a string
	auth has a value which is a string
	status has a value which is a string
	jobdata has a value which is a reference to a hash where the key is a string and the value is a string
	queuetime has a value which is a string
	starttime has a value which is a string
	completetime has a value which is a string
	owner has a value which is a string
	queuecommand has a value which is a string
job_id is a string


=end text



=item Description

Queues a new job in the workspace.

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
    my($job);
    #BEGIN queue_job
    $self->_setContext($ctx,$params);
    $params = $self->_validateargs($params,["type"],{
    	"state" => "queued",
    	jobdata => {},
    	queuecommand => "unknown"
    });
    #Obtaining new job ID
    my $id = $self->_get_new_id("job.");
    #Checking that job doesn't already exist
    my $cursor = $self->_mongodb()->get_collection('jobObjects')->find({id => $id});
    while (my $object = $cursor->next) {
    	if ($id =~ m/job\.(\d+)/) {
    		my $num = $1;
    		$num++;
    		$id = "job.".$num;
    	}
    	print stderr "Getting new ID:".$id."\n";
    	$cursor = $self->_mongodb()->get_collection('jobObjects')->find({id => $id});
    }
    #Inserting jobs in database
    $job = {
		id => $id,
		type => $params->{type},
		auth => $params->{auth},
		status => $params->{"state"},
		jobdata => $params->{jobdata},
		queuetime => DateTime->now()->datetime(),
		owner => $self->_getUsername(),
		queuecommand => $params->{queuecommand}
    };
    $self->_mongodb()->get_collection('jobObjects')->insert($job);
	$self->_clearContext();  
    #END queue_job
    my @_bad_returns;
    (ref($job) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"job\" (value was \"$job\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to queue_job:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'queue_job');
    }
    return($job);
}




=head2 set_job_status

  $job = $obj->set_job_status($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a set_job_status_params
$job is a JobObject
set_job_status_params is a reference to a hash where the following keys are defined:
	jobid has a value which is a string
	status has a value which is a string
	auth has a value which is a string
	currentStatus has a value which is a string
	jobdata has a value which is a reference to a hash where the key is a string and the value is a string
JobObject is a reference to a hash where the following keys are defined:
	id has a value which is a job_id
	type has a value which is a string
	auth has a value which is a string
	status has a value which is a string
	jobdata has a value which is a reference to a hash where the key is a string and the value is a string
	queuetime has a value which is a string
	starttime has a value which is a string
	completetime has a value which is a string
	owner has a value which is a string
	queuecommand has a value which is a string
job_id is a string

</pre>

=end html

=begin text

$params is a set_job_status_params
$job is a JobObject
set_job_status_params is a reference to a hash where the following keys are defined:
	jobid has a value which is a string
	status has a value which is a string
	auth has a value which is a string
	currentStatus has a value which is a string
	jobdata has a value which is a reference to a hash where the key is a string and the value is a string
JobObject is a reference to a hash where the following keys are defined:
	id has a value which is a job_id
	type has a value which is a string
	auth has a value which is a string
	status has a value which is a string
	jobdata has a value which is a reference to a hash where the key is a string and the value is a string
	queuetime has a value which is a string
	starttime has a value which is a string
	completetime has a value which is a string
	owner has a value which is a string
	queuecommand has a value which is a string
job_id is a string


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
    my($job);
    #BEGIN set_job_status
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["jobid","status"],{
    	currentStatus => undef,
    	jobdata => {}
    });
    my $peviousStatus = $params->{currentStatus};
    my $timevar;
    #Checking status validity
    if (!defined($peviousStatus)) {
	    if ($params->{status} eq "queued") {
	    	$peviousStatus = "done";
	    } elsif ($params->{status} eq "running") {
	    	$peviousStatus = "queued";
	    } elsif ($params->{status} eq "done") {
	    	$peviousStatus = "running";
	    }
    }
    if ($params->{status} eq "queued") {
    	$timevar = "queuetime";
    } elsif ($params->{status} eq "running") {
    	$timevar = "starttime";
    } elsif ($params->{status} eq "done" || $params->{status} eq "error" || $params->{status} eq "crash" || $params->{status} eq "delete") {
    	$timevar = "completetime";
    } else {
    	my $msg = "Input status not valid!";
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => 'set_job_status');
    }
    my $cursor = $self->_mongodb()->get_collection('jobObjects')->find({id => $params->{jobid}});
    my $obj = $cursor->next;
	$job = {};
	my $attributes = [qw(id type auth status jobdata queuetime starttime completetime owner queuecommand)];
	foreach my $attribute (@{$attributes}) {
		if (defined($obj->{$attribute})) {
			$job->{$attribute} = $obj->{$attribute};
		}
	}
    if ($params->{status} eq "delete") {
    	my $query = {status => $peviousStatus,id => $params->{jobid}};
	    if ($self->_getUsername() ne "workspaceroot") {
	    	$query->{owner} = $self->_getUsername();
	    }
	    $self->_mongodb()->get_collection('jobObjects')->remove($query);
    	$job->{status} = "deleted";
    } else {
	    #Checking that job doesn't already exist
	    if (!defined($job)) {
	    	my $msg = "Job not found!";
			Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => 'set_job_status');
	    }
	    #Updating job
	    if (defined($params->{jobdata})) {
		    foreach my $key (keys(%{$params->{jobdata}})) {
		    	$job->{jobdata}->{$key} = $params->{jobdata}->{$key};
		    }
	    }
	    $job->{status} = $params->{status};
	    $job->{$timevar} = DateTime->now()->datetime();
	    $self->_updateDB("jobObjects",{status => $peviousStatus,id => $params->{jobid}},{'$set' => {'status' => $params->{status},$timevar => $job->{$timevar},'jobdata' => $job->{jobdata}}});
	}
	my $JSON = JSON::XS->new->utf8(1);
    $job = $JSON->decode($JSON->encode($job));
	$self->_clearContext();
    #END set_job_status
    my @_bad_returns;
    (ref($job) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"job\" (value was \"$job\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to set_job_status:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'set_job_status');
    }
    return($job);
}




=head2 get_jobs

  $jobs = $obj->get_jobs($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_jobs_params
$jobs is a reference to a list where each element is a JobObject
get_jobs_params is a reference to a hash where the following keys are defined:
	jobids has a value which is a reference to a list where each element is a string
	type has a value which is a string
	status has a value which is a string
	auth has a value which is a string
JobObject is a reference to a hash where the following keys are defined:
	id has a value which is a job_id
	type has a value which is a string
	auth has a value which is a string
	status has a value which is a string
	jobdata has a value which is a reference to a hash where the key is a string and the value is a string
	queuetime has a value which is a string
	starttime has a value which is a string
	completetime has a value which is a string
	owner has a value which is a string
	queuecommand has a value which is a string
job_id is a string

</pre>

=end html

=begin text

$params is a get_jobs_params
$jobs is a reference to a list where each element is a JobObject
get_jobs_params is a reference to a hash where the following keys are defined:
	jobids has a value which is a reference to a list where each element is a string
	type has a value which is a string
	status has a value which is a string
	auth has a value which is a string
JobObject is a reference to a hash where the following keys are defined:
	id has a value which is a job_id
	type has a value which is a string
	auth has a value which is a string
	status has a value which is a string
	jobdata has a value which is a reference to a hash where the key is a string and the value is a string
	queuetime has a value which is a string
	starttime has a value which is a string
	completetime has a value which is a string
	owner has a value which is a string
	queuecommand has a value which is a string
job_id is a string


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
    	status => undef,
    	jobids => undef,
    	type => undef
    });
    my $query = {};
    if (defined($params->{status})) {
    	$query->{status} = $params->{status};
    }
    if (defined($params->{type})) {
    	$query->{type} = $params->{type};
    }
    if (defined($params->{jobids})) {
    	$query->{id} = {'$in' => $params->{jobids}};
    }
    if ($self->_getUsername() ne "workspaceroot") {
    	$query->{owner} = $self->_getUsername();
    }
    my $cursor = $self->_mongodb()->get_collection('jobObjects')->find($query);
	$jobs = [];
	while (my $object = $cursor->next) {
        my $keys = [qw(
        	type id ws auth status queuetime owner requeuetime starttime completetime jobdata queuecommand
        )];
        my $newobj = {};
        foreach my $key (@{$keys}) {
        	if (defined($object->{$key})) {
        		$newobj->{$key} = $object->{$key};
        	}
        }
        push(@{$jobs},$newobj);
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
    $types = [keys(%{$self->_permanentTypes()})];
    my $cursor = $self->_mongodb()->get_collection('typeObjects')->find({});
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
    my $cursor = $self->_mongodb()->get_collection('typeObjects')->find({id => $params->{type}});
    if (my $object = $cursor->next) {
    	my $msg = "Trying to add a type that already exists!";
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => 'queue_job');
    }
    $self->_mongodb()->get_collection('typeObjects')->insert({
		id => $params->{type},
		owner => $self->_getUsername(),
		moddate => DateTime->now()->datetime(),
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
    my $cursor = $self->_mongodb()->get_collection('typeObjects')->find({id => $params->{type},permanent => 0});
    if (my $object = $cursor->next) {
    	$self->_mongodb()->get_collection('typeObjects')->remove({id => $params->{type}});
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




=head2 patch

  $success = $obj->patch($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a patch_params
$success is a bool
patch_params is a reference to a hash where the following keys are defined:
	patch_id has a value which is a string
	auth has a value which is a string
bool is an int

</pre>

=end html

=begin text

$params is a patch_params
$success is a bool
patch_params is a reference to a hash where the following keys are defined:
	patch_id has a value which is a string
	auth has a value which is a string
bool is an int


=end text



=item Description

This function patches the database after an update. Called remotely, but only callable by the admin user.

=back

=cut

sub patch
{
    my $self = shift;
    my($params) = @_;

    my @_bad_arguments;
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to patch:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'patch');
    }

    my $ctx = $Bio::KBase::workspaceService::Server::CallContext;
    my($success);
    #BEGIN patch
    $self->_setContext($ctx,$params);
    $self->_validateargs($params,["patch_id"],{});
    if ($self->_getUsername() ne "workspaceroot") {
    	my $msg = "Only root user can run the patch command!";
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => 'add_type');
    }
    $self->_patch($params);
   	$self->_clearContext();
   	$success = 1;
    #END patch
    my @_bad_returns;
    (!ref($success)) or push(@_bad_returns, "Invalid type for return variable \"success\" (value was \"$success\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to patch:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'patch');
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



=head2 job_id

=over 4



=item Description

ID of a job object


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
        string command - name of the command last used to modify or create the object
        username lastmodifier - name of the user who last modified the object
        username owner - name of the user who owns (who created) this object
        workspace_id workspace - ID of the workspace in which the object is currently stored
        workspace_ref ref - a 36 character ID that provides permanent undeniable access to this specific instance of this object
        string chsum - checksum of the associated data object
        mapping<string,string> metadata - custom metadata entered for data object during save operation


=item Definition

=begin html

<pre>
a reference to a list containing 11 items:
0: (id) an object_id
1: (type) an object_type
2: (moddate) a timestamp
3: (instance) an int
4: (command) a string
5: (lastmodifier) a username
6: (owner) a username
7: (workspace) a workspace_id
8: (ref) a workspace_ref
9: (chsum) a string
10: (metadata) a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

a reference to a list containing 11 items:
0: (id) an object_id
1: (type) an object_type
2: (moddate) a timestamp
3: (instance) an int
4: (command) a string
5: (lastmodifier) a username
6: (owner) a username
7: (workspace) a workspace_id
8: (ref) a workspace_ref
9: (chsum) a string
10: (metadata) a reference to a hash where the key is a string and the value is a string


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
0: (id) a workspace_id
1: (owner) a username
2: (moddate) a timestamp
3: (objects) an int
4: (user_permission) a permission
5: (global_permission) a permission

</pre>

=end html

=begin text

a reference to a list containing 6 items:
0: (id) a workspace_id
1: (owner) a username
2: (moddate) a timestamp
3: (objects) an int
4: (user_permission) a permission
5: (global_permission) a permission


=end text

=back



=head2 JobObject

=over 4



=item Description

Data structures for a job object

job_id id - ID of the job object
string type - type of the job
string auth - authentication token of job owner
string status - current status of job
mapping<string,string> jobdata;
string queuetime - time when job was queued
string starttime - time when job started running
string completetime - time when the job was completed
string owner - owner of the job
string queuecommand - command used to queue job


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is a job_id
type has a value which is a string
auth has a value which is a string
status has a value which is a string
jobdata has a value which is a reference to a hash where the key is a string and the value is a string
queuetime has a value which is a string
starttime has a value which is a string
completetime has a value which is a string
owner has a value which is a string
queuecommand has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is a job_id
type has a value which is a string
auth has a value which is a string
status has a value which is a string
jobdata has a value which is a reference to a hash where the key is a string and the value is a string
queuetime has a value which is a string
starttime has a value which is a string
completetime has a value which is a string
owner has a value which is a string
queuecommand has a value which is a string


=end text

=back



=head2 user_settings

=over 4



=item Description

Settings for user accounts stored in the workspace

        workspace_id workspace - the workspace currently selected by the user


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id


=end text

=back



=head2 load_media_from_bio_params

=over 4



=item Description

Input parameters for the "load_media_from_bio" function.

        workspace_id mediaWS - ID of workspace where media will be loaded (an optional argument with default "KBaseMedia")
        object_id bioid - ID of biochemistry from which media will be loaded (an optional argument with default "default")
        workspace_id bioWS - ID of workspace with biochemistry from which media will be loaded (an optional argument with default "kbase")
        bool clearExisting - A boolean indicating if existing media in the specified workspace should be cleared (an optional argument with default "0")
        bool overwrite - A boolean indicating if a matching existing media should be overwritten (an optional argument with default "0")


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
mediaWS has a value which is a workspace_id
bioid has a value which is an object_id
bioWS has a value which is a workspace_id
clearExisting has a value which is a bool
overwrite has a value which is a bool
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
mediaWS has a value which is a workspace_id
bioid has a value which is an object_id
bioWS has a value which is a workspace_id
clearExisting has a value which is a bool
overwrite has a value which is a bool
auth has a value which is a string
asHash has a value which is a bool


=end text

=back



=head2 import_bio_params

=over 4



=item Description

Input parameters for the "import_bio" function.

        object_id bioid - ID of biochemistry to be imported (an optional argument with default "default")
        workspace_id bioWS - ID of workspace to which biochemistry will be imported (an optional argument with default "kbase")
        string url - URL from which biochemistry should be retrieved
        bool compressed - boolean indicating if biochemistry is compressed
        bool overwrite - A boolean indicating if a matching existing biochemistry should be overwritten (an optional argument with default "0")


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
bioid has a value which is an object_id
bioWS has a value which is a workspace_id
url has a value which is a string
compressed has a value which is a bool
clearExisting has a value which is a bool
overwrite has a value which is a bool
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
bioid has a value which is an object_id
bioWS has a value which is a workspace_id
url has a value which is a string
compressed has a value which is a bool
clearExisting has a value which is a bool
overwrite has a value which is a bool
auth has a value which is a string
asHash has a value which is a bool


=end text

=back



=head2 import_map_params

=over 4



=item Description

Input parameters for the "import_map" function.

        object_id mapid - ID of mapping to be imported (an optional argument with default "default")
        workspace_id mapWS - ID of workspace to which mapping will be imported (an optional argument with default "kbase")
        string url - URL from which mapping should be retrieved
        bool compressed - boolean indicating if mapping is compressed
        bool overwrite - A boolean indicating if a matching existing mapping should be overwritten (an optional argument with default "0")


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
bioid has a value which is an object_id
bioWS has a value which is a workspace_id
mapid has a value which is an object_id
mapWS has a value which is a workspace_id
url has a value which is a string
compressed has a value which is a bool
overwrite has a value which is a bool
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
bioid has a value which is an object_id
bioWS has a value which is a workspace_id
mapid has a value which is an object_id
mapWS has a value which is a workspace_id
url has a value which is a string
compressed has a value which is a bool
overwrite has a value which is a bool
auth has a value which is a string
asHash has a value which is a bool


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
        bool asHash - a boolean indicating if metadata should be returned as a hash


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
asHash has a value which is a bool

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
asHash has a value which is a bool


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
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool


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
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool


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
        bool asHash - a boolean indicating if metadata should be returned as a hash
        bool asJSON - indicates that data should be returned in JSON format (an optional argument; default is '0')


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string
asHash has a value which is a bool
asJSON has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string
asHash has a value which is a bool
asJSON has a value which is a bool


=end text

=back



=head2 get_object_output

=over 4



=item Description

Output generated by the "get_object" function.

        string data - data for object retrieved in json format (an essential argument)
        object_metadata metadata - metadata for object retrieved (an essential argument)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
data has a value which is a string
metadata has a value which is an object_metadata

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
data has a value which is a string
metadata has a value which is an object_metadata


=end text

=back



=head2 get_objects_params

=over 4



=item Description

Input parameters for the "get_object" function.

        list<object_id> ids - ID of the object to be retrieved (an essential argument)
        list<object_type> types - type of the object to be retrieved (an essential argument)
        list<workspace_id> workspaces - ID of the workspace containing the object to be retrieved (an essential argument)
        list<int> instances  - Version of the object to be retrieved, enabling retrieval of any previous version of an object (an optional argument; the current version is retrieved if no version is provides)
        string auth - the authentication token of the KBase account to associate with this object retrieval command (an optional argument; user is "public" if auth is not provided)
        bool asHash - a boolean indicating if metadata should be returned as a hash
        bool asJSON - indicates that data should be returned in JSON format (an optional argument; default is '0')


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
ids has a value which is a reference to a list where each element is an object_id
types has a value which is a reference to a list where each element is an object_type
workspaces has a value which is a reference to a list where each element is a workspace_id
instances has a value which is a reference to a list where each element is an int
auth has a value which is a string
asHash has a value which is a bool
asJSON has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
ids has a value which is a reference to a list where each element is an object_id
types has a value which is a reference to a list where each element is an object_type
workspaces has a value which is a reference to a list where each element is a workspace_id
instances has a value which is a reference to a list where each element is an int
auth has a value which is a string
asHash has a value which is a bool
asJSON has a value which is a bool


=end text

=back



=head2 get_object_by_ref_params

=over 4



=item Description

Input parameters for the "get_object_by_ref" function.

        workspace_ref reference - reference to a specific instance of a specific object in a workspace (an essential argument)
        string auth - the authentication token of the KBase account to associate with this object retrieval command (an optional argument; user is "public" if auth is not provided)
        bool asHash - a boolean indicating if metadata should be returned as a hash
        bool asJSON - indicates that data should be returned in JSON format (an optional argument; default is '0')


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
reference has a value which is a workspace_ref
auth has a value which is a string
asHash has a value which is a bool
asJSON has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
reference has a value which is a workspace_ref
auth has a value which is a string
asHash has a value which is a bool
asJSON has a value which is a bool


=end text

=back



=head2 save_object_by_ref_params

=over 4



=item Description

Input parameters for the "save_object_by_ref" function.

        object_id id - ID to which the model should be saved (an essential argument)
        object_type type - type of the object for which metadata is to be retrieved (an essential argument)
        ObjectData data - string or reference to complex datastructure to be saved in the workspace (an essential argument)
        string command - the name of the KBase command that is calling the "save_object" function (an optional argument with default "unknown")
        mapping<string,string> metadata - a hash of metadata to be associated with the object (an optional argument with default "{}")
        workspace_ref reference - reference the object should be saved in
        bool json - a flag indicating if the input data is encoded as a JSON string (an optional argument with default "0")
        bool compressed - a flag indicating if the input data in zipped (an optional argument with default "0")
        bool retrieveFromURL - a flag indicating that the "data" argument contains a URL from which the actual data should be downloaded (an optional argument with default "0")
        bool replace - a flag indicating any existing object located at the specified reference should be overwritten (an optional argument with default "0")
        string auth - the authentication token of the KBase account to associate this save command (an optional argument, user is "public" if auth is not provided)
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
data has a value which is an ObjectData
command has a value which is a string
metadata has a value which is a reference to a hash where the key is a string and the value is a string
reference has a value which is a workspace_ref
json has a value which is a bool
compressed has a value which is a bool
retrieveFromURL has a value which is a bool
replace has a value which is a bool
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
data has a value which is an ObjectData
command has a value which is a string
metadata has a value which is a reference to a hash where the key is a string and the value is a string
reference has a value which is a workspace_ref
json has a value which is a bool
compressed has a value which is a bool
retrieveFromURL has a value which is a bool
replace has a value which is a bool
auth has a value which is a string
asHash has a value which is a bool


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
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string
asHash has a value which is a bool


=end text

=back



=head2 get_objectmeta_by_ref_params

=over 4



=item Description

Input parameters for the "get_objectmeta_by_ref" function.

        workspace_ref reference - reference to a specific instance of a specific object in a workspace (an essential argument)
        string auth - the authentication token of the KBase account to associate with this object retrieval command (an optional argument; user is "public" if auth is not provided)
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
reference has a value which is a workspace_ref
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
reference has a value which is a workspace_ref
auth has a value which is a string
asHash has a value which is a bool


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
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string
asHash has a value which is a bool


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
        string new_workspace_url - URL of workspace server where object should be copied (an optional argument - object will be saved in the same server if not provided)
        string auth - the authentication token of the KBase account to associate with this object copy command (an optional argument; user is "public" if auth is not provided)
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_workspace_url has a value which is a string
new_id has a value which is an object_id
new_workspace has a value which is a workspace_id
source_id has a value which is an object_id
instance has a value which is an int
type has a value which is an object_type
source_workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_workspace_url has a value which is a string
new_id has a value which is an object_id
new_workspace has a value which is a workspace_id
source_id has a value which is an object_id
instance has a value which is an int
type has a value which is an object_type
source_workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool


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
        string new_workspace_url - URL of workspace server where object should be copied (an optional argument - object will be saved in the same server if not provided)
        string auth - the authentication token of the KBase account to associate with this object move command (an optional argument; user is "public" if auth is not provided)
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_workspace_url has a value which is a string
new_id has a value which is an object_id
new_workspace has a value which is a workspace_id
source_id has a value which is an object_id
type has a value which is an object_type
source_workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_workspace_url has a value which is a string
new_id has a value which is an object_id
new_workspace has a value which is a workspace_id
source_id has a value which is an object_id
type has a value which is an object_type
source_workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool


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
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool


=end text

=back



=head2 create_workspace_params

=over 4



=item Description

Input parameters for the "create_workspace" function.

        workspace_id workspace - ID of the workspace to be created (an essential argument)
        permission default_permission - Default permissions of the workspace to be created. Accepted values are 'a' => admin, 'w' => write, 'r' => read, 'n' => none (optional argument with default "n")
        string auth - the authentication token of the KBase account that will own the created workspace (an optional argument; user is "public" if auth is not provided)
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
default_permission has a value which is a permission
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
default_permission has a value which is a permission
auth has a value which is a string
asHash has a value which is a bool


=end text

=back



=head2 get_workspacemeta_params

=over 4



=item Description

Input parameters for the "get_workspacemeta" function.

        workspace_id workspace - ID of the workspace for which metadata should be returned (an essential argument)
        string auth - the authentication token of the KBase account accessing workspace metadata (an optional argument; user is "public" if auth is not provided)
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool


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
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool


=end text

=back



=head2 clone_workspace_params

=over 4



=item Description

Input parameters for the "clone_workspace" function.

        workspace_id current_workspace - ID of the workspace to be cloned (an essential argument)
        workspace_id new_workspace - ID of the workspace to which the cloned workspace will be copied (an essential argument)
        string new_workspace_url - URL of workspace server where workspace should be cloned (an optional argument - workspace will be cloned in the same server if not provided)
        permission default_permission - Default permissions of the workspace created by the cloning process. Accepted values are 'a' => admin, 'w' => write, 'r' => read, 'n' => none (an essential argument)
        string auth - the authentication token of the KBase account that will own the cloned workspace (an optional argument; user is "public" if auth is not provided)
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_workspace has a value which is a workspace_id
new_workspace_url has a value which is a string
current_workspace has a value which is a workspace_id
default_permission has a value which is a permission
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_workspace has a value which is a workspace_id
new_workspace_url has a value which is a string
current_workspace has a value which is a workspace_id
default_permission has a value which is a permission
auth has a value which is a string
asHash has a value which is a bool


=end text

=back



=head2 list_workspaces_params

=over 4



=item Description

Input parameters for the "list_workspaces" function.

        string auth - the authentication token of the KBase account accessing the list of workspaces (an optional argument; user is "public" if auth is not provided)
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
auth has a value which is a string
asHash has a value which is a bool


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
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
type has a value which is a string
showDeletedObject has a value which is a bool
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
type has a value which is a string
showDeletedObject has a value which is a bool
auth has a value which is a string
asHash has a value which is a bool


=end text

=back



=head2 set_global_workspace_permissions_params

=over 4



=item Description

Input parameters for the "set_global_workspace_permissions" function.

        workspace_id workspace - ID of the workspace for which permissions will be set (an essential argument)
        permission new_permission - New default permissions to which the workspace should be set. Accepted values are 'a' => admin, 'w' => write, 'r' => read, 'n' => none (an essential argument)
        string auth - the authentication token of the KBase account changing workspace default permissions; must have 'admin' privelages to workspace (an optional argument; user is "public" if auth is not provided)
        bool asHash - a boolean indicating if metadata should be returned as a hash


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_permission has a value which is a permission
workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_permission has a value which is a permission
workspace has a value which is a workspace_id
auth has a value which is a string
asHash has a value which is a bool


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



=head2 get_user_settings_params

=over 4



=item Description

Input parameters for the "get_user_settings" function.

        string auth - the authentication token of the KBase account changing workspace permissions; must have 'admin' privelages to workspace (an optional argument; user is "public" if auth is not provided)


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



=head2 set_user_settings_params

=over 4



=item Description

Input parameters for the "set_user_settings" function.

        string setting - the setting to be set (an essential argument)
        string value - new value to be set (an essential argument)
        string auth - the authentication token of the KBase account changing workspace permissions; must have 'admin' privelages to workspace (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
setting has a value which is a string
value has a value which is a string
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
setting has a value which is a string
value has a value which is a string
auth has a value which is a string


=end text

=back



=head2 queue_job_params

=over 4



=item Description

Input parameters for the "queue_job" function.

        string auth - the authentication token of the KBase account queuing the job; must have access to the job being queued (an optional argument; user is "public" if auth is not provided)
        string state - the initial state to assign to the job being queued (an optional argument; default is "queued")
        string type - the type of the job being queued
        mapping<string,string> jobdata - hash of data associated with job


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
auth has a value which is a string
state has a value which is a string
type has a value which is a string
queuecommand has a value which is a string
jobdata has a value which is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
auth has a value which is a string
state has a value which is a string
type has a value which is a string
queuecommand has a value which is a string
jobdata has a value which is a reference to a hash where the key is a string and the value is a string


=end text

=back



=head2 set_job_status_params

=over 4



=item Description

Input parameters for the "set_job_status" function.

        string jobid - ID of the job to be have status changed (an essential argument)
        string status - Status to which job should be changed; accepted values are 'queued', 'running', and 'done' (an essential argument)
        string auth - the authentication token of the KBase account requesting job status; only status for owned jobs can be retrieved (an optional argument; user is "public" if auth is not provided)
        string currentStatus - Indicates the current statues of the selected job (an optional argument; default is "undef")
        mapping<string,string> jobdata - hash of data associated with job


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
jobid has a value which is a string
status has a value which is a string
auth has a value which is a string
currentStatus has a value which is a string
jobdata has a value which is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
jobid has a value which is a string
status has a value which is a string
auth has a value which is a string
currentStatus has a value which is a string
jobdata has a value which is a reference to a hash where the key is a string and the value is a string


=end text

=back



=head2 get_jobs_params

=over 4



=item Description

Input parameters for the "get_jobs" function.

list<string> jobids - list of specific jobs to be retrieved (an optional argument; default is an empty list)
string status - Status of all jobs to be retrieved; accepted values are 'queued', 'running', and 'done' (an essential argument)
string auth - the authentication token of the KBase account accessing job list; only owned jobs will be returned (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
jobids has a value which is a reference to a list where each element is a string
type has a value which is a string
status has a value which is a string
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
jobids has a value which is a reference to a list where each element is a string
type has a value which is a string
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



=head2 patch_params

=over 4



=item Description

Input parameters for the "patch" function.

string patch_id - ID of the patch that should be run on the workspace
string auth - the authentication token of the KBase account removing a custom type (an optional argument; user is "public" if auth is not provided)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
patch_id has a value which is a string
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
patch_id has a value which is a string
auth has a value which is a string


=end text

=back



=cut

1;
