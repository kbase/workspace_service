package Bio::KBase::workspaceService::WorkspaceUser;
use strict;
use Bio::KBase::Exceptions;

our $VERSION = "0";

=head1 NAME

Workspace

=head1 DESCRIPTION

=head1 Object

API for manipulating WorkspaceUser

=cut

=head3 new

Definition:
	Object = Bio::KBase::workspaceService::WorkspaceUser->new();
Description:
	Returns a WorkspaceUser object

=cut

sub new {
	my ($class,$args) = @_;
	$args = Bio::KBase::workspaceService::Impl::_args([
		"parent",
		"id",
		"workspaces",
		"moddate"
	],{
		settings => {
			workspace => "default"
		}
	},$args);
	my $self = {
		_id => $args->{id},
		_parent => $args->{parent},
		_workspaces => $args->{workspaces},
		_moddate => $args->{moddate},
		_settings => $args->{settings}
	};
	bless $self;
	$self->_validateID($args->{id});
    return $self;
}

=head3 id

Definition:
	string = id()
Description:
	Returns the id for the workspace user

=cut

sub id {
	my ($self) = @_;
	return $self->{_id};
}

=head3 parent

Definition:
	string = parent()
Description:
	Returns the parent for the workspace user

=cut

sub parent {
	my ($self) = @_;
	return $self->{_parent};
}

=head3 workspaces

Definition:
	string = workspaces()
Description:
	Returns the workspaces for the workspace user

=cut

sub workspaces {
	my ($self) = @_;
	return $self->{_workspaces};
}

=head3 settings

Definition:
	string = settings()
Description:
	Returns the settings for the workspace user

=cut

sub settings {
	my ($self) = @_;
	return $self->{_settings};
}

=head3 moddate

Definition:
	string = moddate()
Description:
	Returns the moddate for the workspace user

=cut

sub moddate {
	my ($self) = @_;
	return $self->{_moddate};
}

=head3 setWorkspacePermission

Definition:
	void setWorkspacePermission(string:workspace,string:permission)
Description:
	Sets permission for user for input workspace

=cut

sub setWorkspacePermission {
	my ($self,$workspace,$perm) = @_;
	$self->_validatePermission($perm);
	$self->workspaces()->{$workspace} = $perm;
	if ($perm eq "n" && defined($self->workspaces()->{$workspace})) {
		$self->parent()->_updateDB("workspaceUsers",{id => $self->id()},{'$unset' => {'workspaces.'.$workspace => $self->workspaces()->{$workspace}}});
	} else {
		$self->parent()->_updateDB("workspaceUsers",{id => $self->id()},{'$set' => {'workspaces.'.$workspace => $perm}});
	}
}

=head3 getWorkspacePermission

Definition:
	void getWorkspacePermission(string:workspace)
Description:
	Returns the users permission for a workspace

=cut

sub getWorkspacePermission {
	my ($self,$workspace) = @_;
	if (!ref($workspace)) {
		if (defined($self->workspaces()->{$workspace})) {
			return $self->workspaces()->{$workspace};
		}
		$workspace = $self->_getWorkspace($workspace,{throwErrorIfMissing => 1});
	} elsif (defined($self->workspaces()->{$workspace->id()})) {
		return $self->workspaces()->{$workspace->id()};
	}
	return $workspace->defaultPermissions();
}

=head3 getUserWorkspaces

Definition:
	[Bio::KBase::workspaceService::Workspace] = getUserWorkspaces()
Description:
	Returns the workspaces the user has access to

=cut

sub getUserWorkspaces {
	my ($self) = @_;
	my $workspaceHash = {};
	my $workspaces = $self->workspaces();
	foreach my $key (keys(%{$workspaces})) {
    	if ($workspaces->{$key} ne "n") {
    		$workspaceHash->{$key} = $self->workspaces()->{$key};
    	}
    }
	return $self->parent()->_getWorkspaces([keys(%{$workspaceHash})],{orQuery => [{defaultPermissions => {'$in' => ["a","w","r"]}}]});
}

=head3 updateSettings

Definition:
	[Bio::KBase::workspaceService::Workspace] = updateSettings(string setting,string value)
Description:
	Updates user settings in workspace

=cut

sub updateSettings {
	my ($self,$setting,$value) = @_;
	$self->settings()->{$setting} = $value;
	$self->parent()->_updateDB("workspaceUsers",{id => $self->id()},{'$set' => {'settings.'.$setting => $value}});
}

sub _validateID {
	my ($self,$id) = @_;
	$self->parent()->_validateUserID($id);
}

sub _validatePermission {
	my ($self,$permission) = @_;
	$self->parent()->_validatePermission($permission);
}

1;
