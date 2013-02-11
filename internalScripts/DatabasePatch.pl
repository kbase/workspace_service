use MongoDB;
use MongoDB::GridFS;
use JSON::XS;
use Tie::IxHash;
use FileHandle;
use DateTime;
use Data::Dumper;
use Bio::KBase::workspaceService::Impl;
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
my %params;
if ((my $e = $ENV{KB_DEPLOYMENT_CONFIG}) && -e $ENV{KB_DEPLOYMENT_CONFIG})
{
    my $service = $ENV{KB_SERVICE_NAME};
    my $c = Config::Simple->new();
    $c->read($e);
    my @params = qw(mongodb-host mongodb-database);
    for my $p (@params)
    {
	my $v = $c->param("$service.$p");
	if ($v)
	{
	    $params{$p} = $v;
	}
    }
}

if (defined $params{"mongodb-host"}) {
    $self->{_host} = $params{"mongodb-host"};
}
else {
    warn "mongodb-host configuration not found, using 'localhost'\n";
    $self->{_host} = "localhost";
}

if (defined $params{"mongodb-database"}) {
    $self->{_db} = $params{"mongodb-database"};
}
else {
    warn "mongodb-database configuration not found, using 'workspace_service'\n";
    $self->{_db} = "workspace_service";
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
my $numberObjects = 0;
my $numberMismatch = 0;
foreach my $key (keys(%{$objHash})) {
	$numberObjects++;
	my $obj = $objHash->{$key};
	my $file = $self->{_gridfs}->find_one({chsum => $obj->chsum()});
    if (!defined($file)) {
    	die "Missing file!\n";
    }
	my $dataString = $file->slurp();
	if ($dataString ne $obj->data()) {
		print "Missmatch:".$obj->compressed()."/".$obj->json()."\n";
		$numberMismatch++;
	}
}
print "Object:".$numberObjects."\nMissmatches:".$numberMismatch."\n";
