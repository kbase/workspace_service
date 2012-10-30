package Bio::KBase::workspaceService::Workspace;
use strict;
use Bio::KBase::Exceptions;
use Data::UUID;

our $VERSION = "0";

=head1 NAME

Workspace

=head1 DESCRIPTION

=head1 Workspace

API for manipulating workspaces

=cut

=head3 new

Definition:
	Workspace = Bio::KBase::workspaceService::Workspace->new({}:workspace data);
Description:
	Returns a Workspace object

=cut

sub new {
	my ($class,$args) = @_;
	$args = Bio::KBase::workspaceService::Impl::_args([
		"parent",
		"id",
		"owner",
		"moddate",
		"defaultPermissions",
		"objects"
	],{},$args);
	my $self = {
		_id => $args->{id},
		_parent => $args->{parent},
		_owner => $args->{owner},
		_moddate => $args->{moddate},
		_defaultPermissions => $args->{defaultPermissions},
		_objects => $args->{objects}
	};
	bless $self;
	$self->_validateID($args->{id});
	$self->_validatePermission($args->{defaultPermissions});
    return $self;
}

=head3 id

Definition:
	string = id()
Description:
	Returns the id for the workspace

=cut

sub id {
	my ($self) = @_;
	return $self->{_id};
}

=head3 parent

Definition:
	string = parent()
Description:
	Returns the parent workspace implementation

=cut

sub parent {
	my ($self) = @_;
	return $self->{_parent};
}

=head3 owner

Definition:
	string = owner()
Description:
	Returns the owner for the workspace

=cut

sub owner {
	my ($self) = @_;
	return $self->{_owner};
}

=head3 moddate

Definition:
	string = moddate()
Description:
	Returns the moddate for the workspace

=cut

sub moddate {
	my ($self) = @_;
	return $self->{_moddate};
}

=head3 defaultPermissions

Definition:
	string = defaultPermissions()
Description:
	Returns the defaultPermissions for the workspace

=cut

sub defaultPermissions {
	my ($self) = @_;
	return $self->{_defaultPermissions};
}

=head3 objects

Definition:
	{} = objects();
Description:
	Returns the workspace objects hash

=cut

sub objects {
	my ($self,$type,$alias) = @_;
	return $self->{_objects};
}

=head3 metadata

Definition:
	{} = metadata();
Description:
	Returns the metadata object for workspace

=cut

sub metadata {
	my ($self) = @_;
	my $objects = 0;
	foreach my $key (keys(%{$self->objects()})) {
		$objects += keys(%{$self->objects()->{$key}});
	}
	return [
		$self->id(),
		$self->owner(),
		$self->moddate(),
		$objects,
		$self->currentPermission(),
		$self->defaultPermissions()
	];
}

=head3 currentPermission

Definition:
	string = currentPermission()
Description:
	Returns the current permissions for access to this workspace

=cut

sub currentPermission {
	my ($self) = @_;
	if (!defined($self->{_currentPermission})) {
		my $userObj = $self->parent()->_getCurrentUserObj();
		if (!defined($userObj)) {
			$self->{_currentPermission} = $self->defaultPermissions();
		} else {
			$self->{_currentPermission} = $userObj->getWorkspacePermission($self);
		}
	}
	return $self->{_currentPermission};
}

=head3 currentUser

Definition:
	string = currentUser()
Description:
	Returns the current user accessing this workspace

=cut

sub currentUser {
	my ($self) = @_;
	return $self->parent()->_getUsername();
}

=head3 setDefaultPermissions

Definition:
	void setDefaultPermissions(string:permission)
Description:
	Alters the default permissions for workspace

=cut

sub setDefaultPermissions {
	my ($self,$perm) = @_;
	$self->_validatePermission($perm);
	if ($self->currentPermission() ne "a") {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "User does not have rights to edit workspace permissions!",
							       method_name => 'setDefaultPermissions');
	}
	$self->{_defaultPermissions} = $perm;
	$self->parent()->_updateDB("workspaces",{id => $self->id()},{'$set' => {'defaultPermissions' => $perm}});
}

=head3 getObject

Definition:
	Bio::KBase::workspaceService::Object = getObject(string:type,string:alias)
Description:
	Returns a Workspace object

=cut

sub getObject {
	my ($self,$type,$id,$options) = @_;
	my $objects = $self->objects();
	if (!defined($objects->{$type}->{$id})) {
		if (defined($options->{throwErrorIfMissing}) && $options->{throwErrorIfMissing} == 1) {
			Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Specified object not found in the workspace!",
							       method_name => 'getObject');
		}
		return undef;
	}
	my $uuid = $objects->{$type}->{$id};
	return $self->parent()->_getObject($uuid,{throwErrorIfMissing => 1});
}

=head3 getAllObjects

Definition:
	Bio::KBase::workspaceService::Object = getAllObjects(string:type)
Description:
	Returns all workspace objects of the specified type

=cut

sub getAllObjects {
	my ($self,$type) = @_;
	my $uuids = [];
	my $objects = $self->objects();
	if (!defined($type)) {
		foreach my $type (keys(%{$objects})) {
			foreach my $alias (keys(%{$objects->{$type}})) {
				push(@{$uuids},$objects->{$type}->{$alias});
			}
		}
	} else {
		foreach my $alias (keys(%{$objects->{$type}})) {
			push(@{$uuids},$objects->{$type}->{$alias});	
		}
	}
	return $self->parent()->_getObjects($uuids,{throwErrorIfMissing => 1}); 
}

=head3 saveObject

Definition:
	Bio::KBase::workspaceService::Object = saveObject(string:type)
Description:
	Returns saved object.

=cut

sub saveObject {
	my ($self,$type,$id,$data,$command,$meta) = @_;
	$self->_validateType($type);
	if ($self->currentPermission() =~ m/[rn]/) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "User does not have rights to save an object in the workspace!",
							       method_name => 'saveObject');
	}
	my $continue = 1;
	my ($ancestor,$instance,$owner);
	my $uuid = Data::UUID->new()->create_str();
	while($continue == 1) {
		$ancestor = undef;
		$instance = 0;
		$owner = $self->currentUser();
		my $obj = $self->getObject($type,$id);
		my $olduuid = undef;
		if (defined($obj)) {
			if (!defined($meta)) {
				$meta = $obj->meta();
			}
			$ancestor = $obj->uuid();
			$owner = $obj->owner();
			$instance = ($obj->instance()+1);
			$olduuid = $obj->uuid();
		}
		if ($self->_updateObjects($type,$id,$uuid,$olduuid) == 1) {
			$continue = 0;
		};
	}
	my $newObject = $self->parent()->_createObject({
		uuid => $uuid,
		type => $type,
		workspace => $self->id(),
		parent => $self->parent(),
		ancestor => $ancestor,
		revertAncestors => [],
		owner => $owner,
		lastModifiedBy => $self->currentUser(),
		command => $command,
		id => $id,
		instance => $instance,
		rawdata => $data,
		meta => $meta
	});
	return $newObject;
}

=head3 revertObject

Definition:
	Bio::KBase::workspaceService::Object = revertObject(string:type)
Description:
	Returns previous object in object history

=cut

sub revertObject {
	my ($self,$type,$id) = @_;
	if ($self->currentPermission() =~ m/[rn]/) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "User does not have right to revert an object in the workspace!",
							       method_name => 'revertObject');
	}
	my $obj = $self->getObject($type,$id,{throwErrorIfMissing => 1});
	if (!defined($obj->ancestor())) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Cannot revert an object with no ancestor!",
							       method_name => 'revertObject');
	}
	my $ancestor = $self->parent()->_getObject($obj->ancestor(),{throwErrorIfMissing => 1});	
	my $revertAncestors = $ancestor->revertAncestors();
	push(@{$revertAncestors},$obj->uuid());
	my $uuid = Data::UUID->new()->create_str();
	if ($self->_updateObjects($type,$id,$uuid,$obj->uuid()) == 0) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "State of object was altered during revert process. Revert aborted!",
			method_name => 'revertObject');
	}
	my $newObject = $self->parent()->_createObject({
		uuid => $uuid,
		type => $type,
		workspace => $self->id(),
		parent => $self->parent(),
		ancestor => $ancestor->ancestor(),
		revertAncestors => $revertAncestors,
		owner => $obj->owner(),
		lastModifiedBy => $self->currentUser(),
		command => "revert",
		id => $id,
		instance => ($obj->instance()+1),
		chsum => $ancestor->chsum(),
		meta => $ancestor->meta()
	});
	return $newObject;
}

=head3 unrevertObject

Definition:
	Bio::KBase::workspaceService::Object = unrevertObject(string:type,string:id)
Description:
	Undoes the action of the revert command

=cut

sub unrevertObject {
	my ($self,$type,$id,$index) = @_;
	if (!defined($index)) {
		$index = 0;	
	}
	if ($self->currentPermission() =~ m/[rn]/) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "User does not have right to unrevert an object in the workspace!",
			method_name => 'unrevertObject');
	}
	my $obj = $self->getObject($type,$id,{throwErrorIfMissing => 1});
	if ($obj->command() ne "revert") {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Cannot unrevert an object that was not reverted!",
			method_name => 'unrevertObject');
	}
	if (!defined($obj->revertAncestors()->[$index])) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Specified reversion ancestor does not exist!",
			method_name => 'unrevertObject');
	}
	if ($self->_updateObjects($type,$id,$obj->revertAncestors()->[$index],$obj->uuid()) == 0) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "State of object was altered during unrevert process. Unrevert aborted!",
			method_name => 'unrevertObject');
	}
	my $newobj = $self->parent()->_getObject($obj->revertAncestors()->[$index],{throwErrorIfMissing => 1});	
	return $newobj;
}

=head3 deleteObject

Definition:
	Bio::KBase::workspaceService::Object = deleteObject(string:type,string:id)
Description:
	Deletes the specified object from the workspacee, leaving a stub that can be reverted.

=cut

sub deleteObject {
	my ($self,$type,$id) = @_;
	if ($self->currentPermission() =~ m/[rn]/) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "User does not have rights to delete an object in the workspace!",
							       method_name => 'deleteObject');
	}
	my $obj = $self->getObject($type,$id,{throwErrorIfMissing => 1});
	if ($obj->command() eq "delete") {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Object already in a deleted state!",
			method_name => 'deleteObject');
	}
	my $uuid = Data::UUID->new()->create_str();
	if ($self->_updateObjects($type,$id,$uuid,$obj->uuid()) == 0) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "State of object was altered during delete process. Delete aborted!",
			method_name => 'deleteObject');
	}
	my $newObject = $self->parent()->_createObject({
		uuid => $uuid,
		type => $type,
		workspace => $self->id(),
		parent => $self->parent(),
		ancestor => $obj->uuid(),
		owner => $obj->owner(),
		lastModifiedBy => $self->currentUser(),
		command => "delete",
		id => $id,
		instance => ($obj->instance()+1),
		chsum => $obj->chsum(),
		meta => $obj->meta()
	});
	return $newObject;
}

=head3 deleteObjectPermanently

Definition:
	Bio::KBase::workspaceService::Object = deleteObject(string:type,string:id)
Description:
	Deletes the specified object from the workspacee and database permanently and irreversibly.
	The object must already be in a "deleted" state in the workspace.

=cut

sub deleteObjectPermanently {
	my ($self,$type,$id) = @_;
	my $obj = $self->getObject($type,$id,{throwErrorIfMissing => 1});
	if ($self->currentPermission() ne "a" && $self->currentUser() ne $obj->owner()) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "User does not have rights to permanently delete an object in the workspace!",
							       method_name => 'deleteObjectPermanently');
	}
	if ($obj->command() ne "delete") {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Object must be in a deleted state before it can be permanently deleted!",
							       method_name => 'deleteObjectPermanently');
	}
	if ($self->_updateObjects($type,$id,undef,$obj->uuid()) == 0) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "State of object was altered during delete process. Delete aborted!",
							       method_name => 'deleteObjectPermanently');	
	}
	$obj->permanentDelete();
	return $obj;
}

=head3 setUserPermissions

Definition:
	void setUserPermissions([string]:usernames,string:permission)
Description:
	Sets user permissions

=cut

sub setUserPermissions {
	my ($self,$users,$perm) = @_;
	$self->_validatePermission($perm);
	if ($self->currentPermission() ne "a") {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "User does not have rights to set user permissions for workspace!",
							       method_name => 'setUserPermissions');
	}
	my $userObjects = $self->parent()->_getWorkspaceUsers($users,{
		throwErrorIfMissing => 0,
		createIfMissing => 1
	});
	for (my $i=0; $i < @{$userObjects}; $i++) {
		$userObjects->[$i]->setWorkspacePermission($self->id(),$perm);
	}
}

=head3 permanentDelete

Definition:
	void permanentDelete()
Description:
	Permanently deletes workspace and all objects in it (DANGEROUS TO CALL!!!!)

=cut

sub permanentDelete {
	my ($self) = @_;
	if ($self->currentUser() ne $self->owner()) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Only workspace owner can delete workspace!",
							       method_name => 'permanentDelete');
	}
	my $objs = $self->getAllObjects();
	for (my $i=0; $i < @{$objs}; $i++) {
		$objs->[$i]->permanentDelete();
	}
}

=head3 _updateObjects

Definition:
	bool _updateObjects(string:type,string:id,string:uuid,string:olduuid)
Description:
	Updates object uuid in the database if the old uuid still retains the specified value. Otherwise, nothing is done.
	Returns "1" if successful, "0" otherwise.
	This avoid race conditions. You must check if the return is "1"; if not, then the update failed.
=cut

sub _updateObjects {
	my ($self,$type,$id,$uuid,$olduuid) = @_;
	my $result;
	if (!defined($uuid)) {
		if ($self->parent()->_updateDB("workspaces",{id => $self->id(),'objects.'.$type.'.'.$id => $olduuid},{'$unset' => {'objects.'.$type.'.'.$id => $olduuid}}) == 0) {
			return 0;
		}
		delete $self->objects()->{$type}->{$id};
	} else {
		if ($self->parent()->_updateDB("workspaces",{id => $self->id(),'objects.'.$type.'.'.$id => $olduuid},{'$set' => {'objects.'.$type.'.'.$id => $uuid}}) == 0) {
			return 0;
		}
		$self->objects()->{$type}->{$id} = $uuid;
	}
	return 1;
}

sub _validateID {
	my ($self,$id) = @_;
	$self->parent()->_validateWorkspaceID($id);
}

sub _validatePermission {
	my ($self,$permission) = @_;
	$self->parent()->_validatePermission($permission);
}

sub _validateType {
	my ($self,$type) = @_;
	$self->parent()->_validateObjectType($type);
}

1;
