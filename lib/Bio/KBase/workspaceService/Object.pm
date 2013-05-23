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
		my $linkSpecs = {
			ProbAnno => {
				probmodel_uuid => "ProbModel",
			},
			Model => {
				annotation_uuid => "Annotation",
				biochemistry_uuid => "Biochemistry",
				mapping_uuid => "Mapping",
				fbaFormulation_uuids => "FBA",
				unintegratedGapgen_uuids => "GapGen",
				integratedGapgen_uuids => "GapGen",
				unintegratedGapfilling_uuids => "GapFill",
				integratedGapfilling_uuids => "GapFill",
			},
			Genome => {
				annotation_uuid => "Annotation",
				contigs_uuid => "Contigs",
			},
			Mapping => {
				biochemistry_uuid => "Biochemistry"
			},
			Annotation => {
				mapping_uuid => "Mapping"
			},
			Media => {
				biochemistry_uuid => "Biochemistry",
			},
			GapGen => {
				model_uuid => "Model",
				fbaFormulation_uuids => "FBA",
			},
			GapFill => {
				model_uuid => "Model",
				fbaFormulation_uuids => "FBA",
			},
			FBA => {
				model_uuid => "Model",
			},
			PROMModel => {
				annotation_uuid => "Annotation"
			}
		};
		my $data = $self->data();
		if (defined($linkSpecs->{$self->type()})) {
			foreach my $key (keys(%{$linkSpecs->{$self->type()}})) {
				if (defined($data->{$key})) {
					if (ref($data->{$key}) eq "ARRAY") {
						foreach my $uuid (@{$data->{$key}}) {
							$uuid =~ s/\./_DOT_/g;
							$self->{_allDependencies}->{$uuid} = $linkSpecs->{$self->type()}->{$key};
						}
					} else {
						my $uuid = $data->{$key};
						$uuid =~ s/\./_DOT_/g;
						$self->{_allDependencies}->{$uuid} = $linkSpecs->{$self->type()}->{$key};
					}
				}
			}
		}
	}
	return $self->{_allDependencies};
}

=head3 setDefaultMetadata

Definition:
	void setDefaultMetadata();
Description:
	Sets the metadata portion of the object to a default value based on type
=cut

sub setDefaultMetadata {
	my ($self) = @_;
	my $data = $self->data();
	if ($self->type() eq "Model") {
		if (defined($data->{name})) {
			$self->meta()->{name} = $data->{name};
		}
		if (defined($data->{id})) {
			$self->meta()->{id} = $data->{id};
		}
		if (defined($data->{type})) {
			$self->meta()->{type} = $data->{type};
		}
		if (defined($data->{annotation_uuid})) {
			$self->meta()->{annotation_uuid} = $data->{annotation_uuid};
		}
		if (defined($data->{modelcompounds})) {
			my $num = @{$data->{modelcompounds}};
			$self->meta()->{number_compounds} = $num;
		}
		if (defined($data->{biomasses}->[0])) {
			my $num = @{$data->{biomasses}->[0]->{biomasscompounds}};
			$self->meta()->{number_biomasscpd} = $num;
		}
		if (defined($data->{modelreactions})) {
			my $num = @{$data->{modelreactions}};
			$self->meta()->{number_reactions} = $num;
		}
		if (defined($data->{modelcompartments})) {
			my $num = @{$data->{modelcompartments}};
			$self->meta()->{number_compartments} = $num;
		}
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
			$self->meta()->{number_genes} = keys(%{$genehash});
		}
	} elsif ($self->type() eq "FBA") {
		if (defined($data->{media_uuid})) {
			$self->meta()->{media_uuid} = $data->{media_uuid};
		}
		if (defined($data->{notes})) {
			$self->meta()->{notes} = $data->{notes};
		}
		if (defined($data->{fbaResults}->[0]->{objectiveValue})) {
			$self->meta()->{object_value} = $data->{fbaResults}->[0]->{objectiveValue};
		}
	} elsif ($self->type() eq "Media") {
		if (defined($data->{id})) {
			$self->meta()->{id} = $data->{id};
		}
		if (defined($data->{name})) {
			$self->meta()->{name} = $data->{name};
		}
		if (defined($data->{type})) {
			$self->meta()->{type} = $data->{type};
		}
		if (defined($data->{isMinimal})) {
			$self->meta()->{isMinimal} = $data->{isMinimal};
		}
		if (defined($data->{isDefined})) {
			$self->meta()->{isDefined} = $data->{isDefined};
		}
		if (defined($data->{mediacompounds})) {
			my $num = @{$data->{mediacompounds}};
			$self->meta()->{number_compounds} = $num;
		}	
	} elsif ($self->type() eq "Genome") {
		if (defined($data->{domain})) {
			$self->meta()->{domain} = $data->{domain};
		}
		if (defined($data->{gc})) {
			$self->meta()->{gc} = $data->{gc};
		}
		if (defined($data->{scientific_name})) {
			$self->meta()->{scientific_name} = $data->{scientific_name};
		}
		if (defined($data->{size})) {
			$self->meta()->{size} = $data->{size};
		}
		if (defined($data->{id})) {
			$self->meta()->{id} = $data->{id};
		}
		if (defined($data->{features})) {
			my $num = @{$data->{features}};
			$self->meta()->{number_features} = $num;
		}	
	}
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
