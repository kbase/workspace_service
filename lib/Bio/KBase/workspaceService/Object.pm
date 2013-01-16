package Bio::KBase::workspaceService::Object;
use strict;
use Bio::KBase::Exceptions;
use Data::UUID;
use DateTime;

our $VERSION = "0";

=head1 NAME

Workspace

=head1 DESCRIPTION

=head1 Object

API for manipulating Objects

=cut

=head3 new

Definition:
	Object = Bio::KBase::workspaceService::Object->new();
Description:
	Returns a Workspace object

=cut

sub new {
	my ($class,$args) = @_;
	$args = Bio::KBase::workspaceService::Impl::_args(["parent","id","workspace","type"],{
		uuid => Data::UUID->new()->create_str(),
		ancestor => undef,
		revertAncestors => [],
		owner => $args->{parent}->_getUsername(),
		lastModifiedBy => $args->{parent}->_getUsername(),
		command => "unknown",
		instance => 0,
		rawdata => undef,
		chsum => undef,
		meta => {},
		moddate => DateTime->now()->datetime()
	},$args);
	my $self = {
		_uuid => $args->{uuid},
		_moddate => $args->{moddate},
		_parent => $args->{parent},
		_id => $args->{id},
		_workspace => $args->{workspace},
		_type => $args->{type},
		_ancestor => $args->{ancestor},
		_revertAncestors => $args->{revertAncestors},
		_owner => $args->{owner},
		_lastModifiedBy => $args->{lastModifiedBy},
		_command => $args->{command},
		_instance => $args->{instance},
		_meta => $args->{meta},
		_chsum => $args->{chsum}
	};
	bless $self;
	$self->_validateID($args->{id});
	if (defined($args->{rawdata})) {
		$self->processRawData($args->{rawdata});
	}
    return $self;
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

=head3 id

Definition:
	string = id()
Description:
	Returns the id for the object

=cut

sub id {
	my ($self) = @_;
	return $self->{_id};
}

=head3 uuid

Definition:
	string = uuid()
Description:
	Returns the uuid for the object

=cut

sub uuid {
	my ($self) = @_;
	return $self->{_uuid};
}

=head3 workspace

Definition:
	string = workspace()
Description:
	Returns the workspace for the object

=cut

sub workspace {
	my ($self) = @_;
	return $self->{_workspace};
}

=head3 type

Definition:
	string = type()
Description:
	Returns the type for the object

=cut

sub type {
	my ($self) = @_;
	return $self->{_type};
}

=head3 ancestor

Definition:
	string = ancestor()
Description:
	Returns the ancestor for the object

=cut

sub ancestor {
	my ($self) = @_;
	return $self->{_ancestor};
}

=head3 ancestorObject

Definition:
	Bio::KBase::workspaceService::Object = ancestorObject()
Description:
	Returns the ancestorObject for the object

=cut

sub ancestorObject {
	my ($self) = @_;
	if (!defined($self->ancestor())) {
		return undef;
	}
	return $self->parent()->_getObject($self->ancestor());
}

=head3 revertAncestors

Definition:
	string = revertAncestors()
Description:
	Returns the revertAncestors for the object

=cut

sub revertAncestors {
	my ($self) = @_;
	return $self->{_revertAncestors};
}

=head3 revertAncestorObjects

Definition:
	string = revertAncestorObjects()
Description:
	Returns the revertAncestorObjects for the object

=cut

sub revertAncestorObjects {
	my ($self) = @_;
	my $revAncs = $self->revertAncestors();
	my $list = [];
	for (my $i=0; $i < @{$revAncs}; $i++) {
		$list->[$i] = $self->parent()->_getObject($revAncs->[$i]);
	}
	return $list;
}

=head3 owner

Definition:
	string = owner()
Description:
	Returns the owner for the object

=cut

sub owner {
	my ($self) = @_;
	return $self->{_owner};
}

=head3 lastModifiedBy

Definition:
	string = lastModifiedBy()
Description:
	Returns the lastModifiedBy for the object

=cut

sub lastModifiedBy {
	my ($self) = @_;
	return $self->{_lastModifiedBy};
}

=head3 command

Definition:
	string = command()
Description:
	Returns the command for the object

=cut

sub command {
	my ($self) = @_;
	return $self->{_command};
}

=head3 instance

Definition:
	string = instance()
Description:
	Returns the instance for the object

=cut

sub instance {
	my ($self) = @_;
	return $self->{_instance};
}

=head3 meta

Definition:
	string = meta()
Description:
	Returns the meta for the object

=cut

sub meta {
	my ($self) = @_;
	return $self->{_meta};
}

=head3 chsum

Definition:
	string = chsum()
Description:
	Returns the chsum for the object

=cut

sub chsum {
	my ($self) = @_;
	return $self->{_chsum};
}

=head3 moddate

Definition:
	string = moddate()
Description:
	Returns the moddate for the object

=cut

sub moddate {
	my ($self) = @_;
	return $self->{_moddate};
}

=head3 data

Definition:
	string = data()
Description:
	Returns the data for the object

=cut

sub data {
	my ($self) = @_;
	my $obj = $self->dataObject()->retrieveRawData();
	if (ref($obj)) {
		$obj->{_wsUUID} = $self->uuid();
		$obj->{_wsID} = $self->id();
		$obj->{_wsType} = $self->type();
		$obj->{_wsWS} = $self->workspace();
	}
	return $obj;
}

=head3 metadata

Definition:
	string = metadata()
Description:
	Returns the metadata for the object

=cut

sub metadata {
	my ($self,$ashhash) = @_;
	if (defined($ashhash) && $ashhash == 1) {
		return {
			id => $self->id(),
			type => $self->type(),
			moddate => $self->moddate(),
			instance => $self->instance(),
			command => $self->command(),
			lastmodifier => $self->lastModifiedBy(),
			owner => $self->owner(),
			workspace => $self->workspace(),
			"ref" => $self->uuid(),
			chsum => $self->chsum(),
			metadata => $self->meta()
		};
	}
	return [
		$self->id(),
		$self->type(),
		$self->moddate(),
		$self->instance(),
		$self->command(),
		$self->lastModifiedBy(),
		$self->owner(),
		$self->workspace(),
		$self->uuid(),
		$self->chsum(),
		$self->meta()
	];
}

=head3 processRawData

Definition:
	Bio::KBase::workspaceService::DataObject = processRawData()
Description:
	Creates the data object in the database that will hold the input rawdata

=cut

sub processRawData {
	my ($self,$data) = @_;
	if (ref($data)) {
		my $list = [ qw(_wsUUID _wsUUID _wsType _wsWS) ];
		foreach my $item (@{$list}) {
			if (defined($data->{_wsUUID})) {
				delete $data->{_wsUUID};
			}
		}
	}
	$self->{_dataObject} = $self->parent()->_createDataObject($data);
	$self->{_chsum} = $self->dataObject()->chsum();
	return $self->dataObject();
}

=head3 dataObject

Definition:
	Bio::KBase::workspaceService::DataObject = dataObject()
Description:
	Returns the actual data object for the object

=cut

sub dataObject {
	my ($self) = @_;
	if (!defined($self->{_dataObject})) {
		$self->{_dataObject} = $self->parent()->_getDataObject($self->chsum(),{throwErrorIfMissing => 1});
	}
	return $self->{_dataObject}
}

=head3 objectHistory

Definition:
	[Bio::KBase::workspaceService::Object] = objectHistory()
Description:
	Returns list of previous object versions

=cut

sub objectHistory {
	my ($self) = @_;
	my $ancObj = $self->ancestorObject();
	my $objList = [$self];
	if (defined($ancObj)) {
		push(@{$objList},@{$self->objectHistory()});
	}
	return $objList;
}

=head3 permanentDelete

Definition:
	void permanentDelete();
Description:
	Permanently deletes object and all ancestors

=cut

sub permanentDelete {
	my ($self) = @_;
	my $objs = $self->parent()->_getObjectsByID($self->id(),$self->type(),$self->workspace());
	for (my $i=0; $i < @{$objs};$i++) {
		$self->parent()->_deleteObject($objs->[$i]->uuid(),1);
	}
}

=head3 refDependencies

Definition:
	{string,string} refDependencies();
Description:
	Returns a hash of all reference-type linked objects that this object depends on, with the keys being the IDs and the values being the types

=cut

sub refDependencies {
	my ($self) = @_;
	my $deps = $self->allDependencies();
	my $refdeps = {};
	foreach my $key (keys(%{$deps})) {
		if ($key =~ m/[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}/) {
			$refdeps->{$key} = $deps->{$key};
		}
	}
	return $deps;
}

=head3 idDependencies

Definition:
	{string,string} idDependencies();
Description:
	Returns a hash of all id-type linked objects that this object depends on, with the keys being the IDs and the values being the types

=cut

sub idDependencies {
	my ($self) = @_;
	my $deps = $self->allDependencies();
	my $iddeps = {};
	foreach my $key (keys(%{$deps})) {
		if ($key !~ m/[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}/) {
			$iddeps->{$key} = $deps->{$key};
		}
	}
	return $deps;
}

=head3 allDependencies

Definition:
	void allDependencies();
Description:
	Returns a hash of all linked objects that this object depends on, with the keys being the IDs and the values being the types

=cut

sub allDependencies {
	my ($self) = @_;
	if (!defined($self->{_allDependencies})) {
		$self->{_allDependencies} = {};
		my $data = $self->data();
		if ($self->type() eq "Model") {
			$self->{_allDependencies}->{$data->{annotation_uuid}} = "Annotation";
			$self->{_allDependencies}->{$data->{biochemistry_uuid}} = "Biochemistry";
			$self->{_allDependencies}->{$data->{mapping_uuid}} = "Mapping";
			my $arrayLinks = {
				"fbaFormulation_uuids" => "FBA",
				"unintegratedGapgen_uuids" => "GapGen",
				"integratedGapgen_uuids" => "GapGen",
				"unintegratedGapfilling_uuids" => "GapFill",
				"integratedGapfilling_uuids" => "GapFill",
			};
			foreach my $key (keys(%{$arrayLinks})) {
				if (defined($data->{$key})) {
					foreach my $uuid (@{$data->{$key}}) {
						$self->{_allDependencies}->{$uuid} = $arrayLinks->{$key};
					}
				}
			}
		} elsif ($self->type() eq "Genome") {
			$self->{_allDependencies}->{$data->{annotation_uuid}} = "Annotation";
			$self->{_allDependencies}->{$data->{contigs_uuid}} = "Contigs";
		} elsif ($self->type() eq "Mapping") {
			$self->{_allDependencies}->{$data->{biochemistry_uuid}} = "Biochemistry";
		} elsif ($self->type() eq "Annotation") {
			$self->{_allDependencies}->{$data->{mapping_uuid}} = "Mapping";
		} elsif ($self->type() eq "Media") {
			$self->{_allDependencies}->{$data->{biochemistry_uuid}} = "Biochemistry";
		} elsif ($self->type() eq "GapGen") {
			$self->{_allDependencies}->{$data->{model_uuid}} = "Model";
			$self->{_allDependencies}->{$data->{fbaFormulation_uuid}} = "FBA";
		} elsif ($self->type() eq "GapFill") {
			$self->{_allDependencies}->{$data->{model_uuid}} = "Model";
			$self->{_allDependencies}->{$data->{fbaFormulation_uuid}} = "FBA";
		} elsif ($self->type() eq "FBA") {
			$self->{_allDependencies}->{$data->{model_uuid}} = "Model";
		} elsif ($self->type() eq "PROMModel") {
			$self->{_allDependencies}->{$data->{annotation_uuid}} = "Annotation";
		}
	}
	return $self->{_allDependencies};
}

sub _validateID {
	my ($self,$id) = @_;
	$self->parent()->_validateObjectID($id);
}

sub _validateType {
	my ($self,$type) = @_;
	$self->parent()->_validateObjectType($type);
} 

1;
