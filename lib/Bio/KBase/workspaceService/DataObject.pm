package Bio::KBase::workspaceService::DataObject;
use strict;
use Bio::KBase::Exceptions;
use IO::Compress::Gzip qw(gzip);
use IO::Uncompress::Gunzip qw(gunzip);
use DateTime;

our $VERSION = "0";

=head1 NAME

Workspace

=head1 DESCRIPTION

=head1 Object

API for manipulating Data objects

=cut

=head3 new

Definition:
	Object = Bio::KBase::workspaceService::DataObject->new();
Description:
	Returns a Workspace data object

=cut

sub new {
	my ($class,$args) = @_;
	$args = Bio::KBase::workspaceService::Impl::_args(["parent"],{
		compressed => undef,
		json => undef,
		chsum => undef,
		data => undef,
		creationDate => DateTime->now()->datetime(),
		rawdata => undef
	},$args);
	my $self = {
		_creationDate => $args->{creationDate},
		_parent => $args->{parent},
		_chsum => $args->{chsum},
		_data => $args->{data},
		_compressed => $args->{compressed},
		_json => $args->{json},
	};
	bless $self;
	if (defined($args->{rawdata})) {
		$self->processRawData($args->{rawdata});
	}
	$self->_validateObject();
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

=head3 creationDate

Definition:
	string = creationDate()
Description:
	Returns the creationDate for the object

=cut

sub creationDate {
	my ($self) = @_;
	return $self->{_creationDate};
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

=head3 data

Definition:
	string = data()
Description:
	Returns the data for the object

=cut

sub data {
	my ($self) = @_;
	return $self->{_data};
}

=head3 compressed

Definition:
	0/1 = compressed()
Description:
	Returns the compressed for the object

=cut

sub compressed {
	my ($self) = @_;
	return $self->{_compressed};
}

=head3 json

Definition:
	0/1 = json()
Description:
	Returns the json for the object

=cut

sub json {
	my ($self) = @_;
	return $self->{_json};
}

=head3 processRawData

Definition:
	void processRawData({}|string:rawdata)
Description:
	Processes input raw data for storage

=cut

sub processRawData {
	my ($self,$data) = @_;
	my $compressed = 0;
	my $json = 0;
	if (ref($data)) {
		my $JSON = JSON::XS->new->utf8(1);
    	$data = $JSON->encode($data);
    	$json = 1;
	}
	
	#if (length($data) > 5000000) {
	#	my $gzip_obj;
	#	gzip \$data => \$gzip_obj;
	#	$data = $gzip_obj;
	#	$compressed = 1;
	#}
	$self->{_compressed} = $compressed;
	$self->{_json} = $json;
	$self->{_data} = $data;
	$self->{_chsum} = Digest::MD5::md5_hex($data);
}

=head3 retrieveRawData

Definition:
	{}|string = retrieveRawData()
Description:
	Returns the data stored in the object

=cut

sub retrieveRawData {
	my ($self) = @_;
	my $outdata = $self->data();
	if ($self->compressed() == 1) {
		my $temp = $outdata;
		gunzip \$temp => \$outdata;
	}
	if ($self->json() == 1) {
		my $temp = $outdata;
		#my $JSON = JSON::XS->new->utf8(1);
		my $JSON = JSON::XS->new();
    	$outdata = $JSON->decode($temp);
	}
	return $outdata;
}
	
sub _validateObject {
	my ($self) = @_;
	my $list = [
		"chsum",
		"creationDate",
		"compressed",
		"json",
		"data",
	];
	foreach my $item (@{$list}) {
		if (!defined($self->$item())) {
			Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Data object not valid!",
				method_name => '_validateObject');
		}
	}
}

1;
