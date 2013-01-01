use MongoDB;
use MongoDB::GridFS;
use JSON::XS;
use Tie::IxHash;
use FileHandle;
use DateTime;
use Data::Dumper;
use Bio::KBase::workspaceService::Object;
use Bio::KBase::workspaceService::Workspace;
use Bio::KBase::workspaceService::WorkspaceUser;
use Bio::KBase::workspaceService::DataObject;
use Config::Simple;
use IO::Compress::Gzip qw(gzip);
use IO::Uncompress::Gunzip qw(gunzip);
use File::Temp qw(tempfile);
use LWP::Simple qw(getstore);

#Handling config file
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

#Connecting to the database
my $config = {
host => $self->{_host},
	host => $self->{_host},
	db_name		=> $self->{_db},
	auto_connect   => 1,
	auto_reconnect => 1
};
my $conn = MongoDB::Connection->new(%$config);
Bio::KBase::Exceptions::KBaseException->throw(error => "Unable to connect: $@",
						   method_name => 'workspaceDocumentDB::_mongodb') if (!defined($conn));
my $db_name = $self->{_db};
$self->{_mongodb} = $conn->$db_name;	
$self->{_gridfs} = $self->{_mongodb}->get_gridfs;

#Rerieving all data objects from the old style database
my $cursor = $self->{_mongodb}->workspaceDataObjects->find({});
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

#Saving all data objects in the gridfs store
foreach my $key (keys(%{$objHash})) {
	my $obj = $objHash->{$key};
	my $file = $self->{_gridfs}->find_one({chsum => $obj->chsum()});
	if (!defined($file)) {
		my $dataString = $obj->data();
		open(my $basic_fh, "<", \$dataString);
		my $fh = FileHandle->new;
		$fh->fdopen($basic_fh, 'r');
		$self->{_gridfs}->insert($fh, {
			creationDate => $obj->creationDate(),
			chsum => $obj->chsum(),
			compressed => $obj->compressed(),
			json => $obj->json()
		});
	}
}

#Checking that files were saved intact
foreach my $key (keys(%{$objHash})) {
	my $obj = $objHash->{$key};
	my $file = $self->{_gridfs}->find_one({chsum => $obj->chsum()});
    if (!defined($file)) {
    	die "Missing file!\n";
    }
	my $dataString = $file->slurp();
	if ($dataString ne $obj->data()) {
		die "Data mismatch!\n";
	}
}