use FindBin qw($Bin);
use lib $Bin.'/../lib';
use Bio::KBase::workspaceService::Impl;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
my $test_count = 67;

################################################################################
#Test intiailization: setting test config, instantiating Impl, getting auth token
################################################################################
$ENV{KB_SERVICE_NAME}="workspaceService";
$ENV{KB_DEPLOYMENT_CONFIG}=$Bin."/../configs/test.cfg";
my $impl = Bio::KBase::workspaceService::Impl->new();
#Getting auth token for kbasetest user
my $tokenObj = Bio::KBase::AuthToken->new(
    user_id => 'kbasetest', password => '@Suite525'
);
#This test should immediately die if we cannot get a valid auth token for kbasetest
if (!$tokenObj->validate()) {
	die("Authentication of kbasetest is failing! Check connect to auth subservice!");	
}
my $oauth = $tokenObj->token();
#Deleting all existing test objects (note, because we are doing this, you must NEVER use the production config)
$impl->_clearAllWorkspaces();
$impl->_clearAllWorkspaceObjects();
$impl->_clearAllWorkspaceUsers();
$impl->_clearAllWorkspaceDataObjects();
################################################################################
#Test 1: did an impl object get defined
################################################################################
ok( defined $impl, "Did an impl object get defined" );
################################################################################
#Test 2: Is the impl object in the right class?
################################################################################
isa_ok( $impl, 'Bio::KBase::workspaceService::Impl', "Is it in the right class" );   
################################################################################
#Test 3: Can impl perform all defined functions
################################################################################
my @impl_methods = qw(
	create_workspace
	delete_workspace
	clone_workspace
	list_workspaces
	list_workspace_objects
	set_global_workspace_permissions
	set_workspace_permissions
	save_object
	delete_workspace
	delete_object
	delete_object_permanently
	get_object
	get_objectmeta
	revert_object
	copy_object
	move_object
	has_object
	get_object_by_ref
	get_objectmeta_by_ref
	get_workspacemeta
	get_workspacepermissions
	object_history
	get_user_settings
	set_user_settings
	queue_job
	set_job_status
	get_jobs
	add_type
	get_types
	remove_type
);
can_ok($impl, @impl_methods);    
################################################################################
#Test 4-9: Can kbasetest create a workspace, and is the returned metadata correct?
################################################################################
my $meta;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$meta = $impl->create_workspace({
	        workspace => "testworkspace",
	        default_permission => "n",
	        auth => $oauth,
	});
};
ok(defined $meta, "Workspace defined");
is $meta->[0],"testworkspace";
is $meta->[1],"kbasetest";
is $meta->[3],0;
is $meta->[4],"a";
is $meta->[5],"n";
################################################################################
#Test 10-11: Creating a public workspace, and is the returned metadata correct?
################################################################################
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$meta = $impl->create_workspace({
	        workspace => "test_two",
	        default_permission => "n",
	});
};
is $meta->[0], "test_two";
is $meta->[1], "public";
################################################################################
#Test 12-15: List workspaces returns the right workspaces
################################################################################
my $metas;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$metas = $impl->list_workspaces({});
};
is scalar @$metas, 1;
ok($metas->[0]->[0] eq "test_two", "name matches");
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$metas = $impl->list_workspaces({auth => $oauth});
};
is scalar @$metas, 1;
ok($metas->[0]->[0] eq "testworkspace", "name matches");
################################################################################
#Test 16: Workspace dies when accessed with bad token
################################################################################
my $output;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$output = $impl->list_workspaces({auth => "bad" });
};
is $output, undef, "list_workspaces dies with bad authentication";
################################################################################
#Test 17-22: Can create lots of workspaces and list the right number
################################################################################
# Create a few more workspaces
$output = undef;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$output = $impl->create_workspace({workspace=>"testworkspace2",default_permission=>"r",auth=>$oauth}); 
};
ok (defined($output),"Created workspace");
$output = undef;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$output = $impl->create_workspace({workspace=>"testworkspace3",default_permission=>"a",auth=>$oauth}); 
};
ok (defined($output),"Created workspace");
$output = undef;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$output = $impl->create_workspace({workspace=>"testworkspace4",default_permission=>"w",auth=>$oauth}); 
};
ok (defined($output),"Created workspace");
$output = undef;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$output = $impl->create_workspace({workspace=>"testworkspace5",default_permission=>"n",auth=>$oauth}); 
};
ok (defined($output),"Created workspace"); 
my $workspace_list = $impl->list_workspaces({auth=>$oauth});
# Makes sure the length matches
ok(scalar(@{$workspace_list}) eq 5, "length matches");
my $idhash={};
my $ws;
foreach $ws (@{$workspace_list}) {
    $idhash->{$ws->[0]} = 1;
}
ok(defined($idhash->{testworkspace3}),
   "list_workspaces returns newly created workspace testworkspace!");
################################################################################
#Test 23: Dies when attempting to create duplicate workspace
################################################################################   
$output = undef;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$output = $impl->create_workspace({workspace=>"testworkspace",default_permission=>"n",auth=>$oauth});
};
ok(!defined($output), "Dies when attempting to create duplicate workspace");
################################################################################
#Test 24-26: Can delete workspace, but cannot delete twice, and cannot delete nonexistant workspace
################################################################################ 
$output = undef;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$output = $impl->delete_workspace({workspace=>"testworkspace",auth=>$oauth});
};
ok (defined($output),"delete succeeds");
# Does deleting a non-existent workspace fail
$output = undef;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$output = $impl->delete_workspace({workspace=>"testworkspace_foo",auth=>$oauth});
};
ok(!defined($output), "delete for non-existent ws fails");
# Does deleting a previously deleted workspace fail
$output = undef;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$output = $impl->delete_workspace({workspace=>"testworkspace",auth=>$oauth});
};
ok(!defined($output),"duplicate delete fails");
################################################################################
#Test 27-29: Can clone workspace, but cannot clone a deleted or nonexistant workspace
################################################################################ 
$output = undef;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$output = $impl->clone_workspace({
		new_workspace => "clonetestworkspace2",
		current_workspace => "testworkspace2",
		default_permission => "n",
		auth => $oauth
	}); 
};
ok (defined($output),"clone succeeds");
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$impl->delete_workspace({
		workspace=>"clonetestworkspace2",
		auth=>$oauth
	});
};
$output = undef;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$output = $impl->clone_workspace({
		new_workspace => "clonetestworkspace",
		current_workspace => "testworkspace",
		default_permission => "n",
		auth=> $oauth
	}); 
};
is $output, undef, "clone a deleted workspace should fail";
$output = undef;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$output = $impl->clone_workspace({
		new_workspace => "clonetestworkspace3",
		current_workspace => "testworkspace_foo",
		default_permission => "n",
		auth => $oauth
	}); 
};
is $output, undef, "clone a non-existent workspace should fail";
# Does the cloned workspace match the original
# Does the cloned workspace preserve permissions
################################################################################
#Test 30-32: Cannot make workspace with bad or no permissions, and must use hash ref
################################################################################ 
eval{
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$meta = $impl->create_workspace({
		workspace=>"testworkspace6",
		default_permission=>"g",
		auth=>$oauth
	});
};
isnt($@,'',"Attempt to create workspace with bad permissions fails");
eval{
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$meta = $impl->create_workspace(
		"testworkspace",
		'n',
		auth=>$oauth
	);
};
isnt($@,'',"Attempt to create workspace without a hash reference  fails");
################################################################################
#Test 33-38: Adding objects to workspace
################################################################################ 
note("Test Adding Objects to the workspace testworkspace");
my $wsmeta;
eval{
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$wsmeta = $impl->create_workspace({
		workspace=>"testworkspace",
		default_permission=>"n",
		auth=>$oauth
	});
};
my $data = "This is my data string";
my %metadata = (a=>1,b=>2,c=>3);
my $conf = {
        id => "Test1",
        type => "TestData",
        data => $data,
        workspace => "testworkspace",
        command => "string",
        metadata => \%metadata,
        auth => $oauth
    };
my $conf1 = {
        id => "Test1",
        type => "TestData",
        workspace => "testworkspace",
        auth => $oauth
    };
my $conf2 = {
        id => "Test2",
        type => "TestData",
        workspace => "testworkspace",
        auth => $oauth
    };
my $objmeta;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$objmeta = $impl->save_object($conf);
};
is(ref($objmeta),'ARRAY', "Did the save_object return an ARRAY ?");
#Adding object from URL
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$objmeta = $impl->save_object({
		id => "testbiochem",
		type => "Biochemistry",
		data => "http://bioseed.mcs.anl.gov/~chenry/KbaseFiles/testKBaseBiochem.json",
		workspace => "testworkspace",
		command => "implementationTest",
		json => 1,
		compressed => 0,
		retrieveFromURL => 1,
		auth => $oauth
	});
};
ok $objmeta->[0] eq "testbiochem","save_object ran and returned testbiochem object with correct ID!";
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$output = $impl->get_object({
		id => "testbiochem",
		type => "Biochemistry",
		workspace => "testworkspace",
		auth => $oauth
	});
};
ok $output->{metadata}->[0] eq "testbiochem","save_object ran and returned testbiochem object with correct ID!";
#Test should fail gracefully when sending bad parameters
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$wsmeta = $impl->has_object($wsmeta);
};
isnt($@,'', "Confirm bad input parameters fails gracefully ");
#Checking if test object is present
my $bool;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$bool = $impl->has_object($conf1);
};
is($bool,1,"has_object successfully determined object Test1 exists!");
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$bool = $impl->has_object($conf2);
};
is($bool,0, "Confirm that Test2 does not exist");


note("Retrieving test object data from database");
################################################################################
#Test 39-51: Retreiving, moving, copying, deleting, and reverting objects 
################################################################################ 
#Retrieving test object data from database
$objmeta = [];
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$output = $impl->get_object($conf1);
};
is($@,"","Retrieving test object data from database");
ok $output->{metadata}->[0] eq "Test1","get_object successfully retrieved object Test1!";
note("Retrieving test object metadata from database");
#Retrieving test object metadata from database
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$objmeta = $impl->get_objectmeta($conf1);
}; 
ok $objmeta->[0] eq "Test1",
	"get_objectmeta successfully retrieved metadata for Test1!";
#Copying object
$conf2 = {
	new_id => "TestCopy",
	new_workspace => "testworkspace2",
	source_id => "Test1",
	type => "TestData",
	source_workspace => "testworkspace",
	auth => $oauth
};
note("copy_object from testworkspace to testworkspace2");
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$objmeta = $impl->copy_object($conf2);
};
ok $objmeta->[0] eq "TestCopy",
	"copy_object successfully returned metadata for TestCopy!";
note("move_object from testworkspace to testworkspace2");
$conf2->{'new_id'} = 'TestMove';
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$objmeta = $impl->move_object($conf2);
};
ok $objmeta->[0] eq "TestMove",
	"move_object successfully returned metadata for TestMove!";
note("Delete object TestCopy from testworkspace2");
$conf2 = {
	id => "TestCopy",
	type => "TestData",
	workspace => "testworkspace2",
	auth => $oauth
};
#Deleting object
#eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$objmeta = $impl->delete_object($conf2);
#};
ok $objmeta->[4] eq "delete",
	"delete_object successfully returned metadata for deleted object!";
#Reverting deleted object
#eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$objmeta = $impl->revert_object($conf2);
	print Dumper($objmeta);
#};
ok $objmeta->[4] =~ m/^revert/,"object successfully reverted!";
#	"revert_object successfully undeleted TestCopy!";
my $objmetas;
my $objidhash = {};
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$objmetas = $impl->list_workspace_objects( { workspace=>"testworkspace2"});
	foreach $objmeta (@{$objmetas}) {
		$objidhash->{$objmeta->[0]} = 1;
	}
};
ok defined($objidhash->{TestCopy}),
	"list_workspace_objects now returns undeleted object TestCopy!";
note("List the objects in testworkspace");
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$objmetas = $impl->list_workspace_objects( { workspace=>"testworkspace",auth => $oauth});
	$objidhash = {};
	foreach $objmeta (@{$objmetas}) {
		$objidhash->{$objmeta->[0]} = 1;
	}
};
ok !defined($objidhash->{Test1}),
	"list_workspace_objects returned object list without deleted object Test1!";
#Checking that the copied objects still exist
ok !defined($objidhash->{TestCopy}),
	"list_workspace_objects returned object list without copied object TestCopy!";
ok !defined($objidhash->{TestMove}),
	"list_workspace_objects returned object list without moved result object TestMove!";
note("List the objects in testworkspace2");
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$objmetas = $impl->list_workspace_objects( { workspace=>"testworkspace2",auth => $oauth});
	$objidhash = {};
	foreach $objmeta (@{$objmetas}) {
		$objidhash->{$objmeta->[0]} = 1;
	}
};
ok !defined($objidhash->{Test1}),
	"list_workspace_objects returned object list without deleted object Test1!";
#Checking that the copied objects still exist
ok defined($objidhash->{TestCopy}),
	"list_workspace_objects returned object list with copied object TestCopy!";
ok defined($objidhash->{TestMove}),
	"list_workspace_objects returned object list with moved result object TestMove!";
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$output = $impl->get_objects({
		ids => ["TestCopy","TestMove","Test1"],
		types => ["TestData","TestData","TestData"],
		workspaces => ["testworkspace2","testworkspace2","testworkspace"],
		auth => $oauth
	});
};
ok defined($output), "Multiple objects retrieved at once!";
ok @{$output} == 3, "Three objects retrieved at once!";
################################################################################
#Test 52-61: Cloning workspaces with objects
################################################################################ 
$conf2 = {
        new_workspace => "clonetestworkspace",
        current_workspace => "testworkspace2",
        default_permission => "n",
        auth => $oauth
};
#Cloning workspace
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$wsmeta = $impl->clone_workspace($conf2);
};
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$objmetas = $impl->list_workspace_objects({ workspace=>"clonetestworkspace",auth => $oauth});
	$objidhash = {};
	foreach $objmeta (@{$objmetas}) {
		$objidhash->{$objmeta->[0]} = 1;
	}
};
ok defined($objidhash->{TestMove}),
	"clone_workspace successfully recreates workspace with identical objects!";

$conf = {
        workspace => "testworkspace",
        new_permission => "r",
        auth => $oauth
    };

#Changing workspace global permissions
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$wsmeta = $impl->set_global_workspace_permissions($conf);
};
is($@,'',"set_global_workspace_permissions - testworkspace to r - Command ran without errors");
ok $wsmeta->[5] eq "r",
	"set_global_workspace_permissions - Value = $wsmeta->[5] ";

#Changing workspace user permissions global permissions
$conf = {
        workspace => "clonetestworkspace",
        new_permission => "w",
		users => ["public"],
		auth => $oauth
    };
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$bool = $impl->set_workspace_permissions($conf);
};
is($@,'',"set_workspace_permissions - user global permissions for clonetestworkspace to w - Command ran without errors");
ok $bool == 1,"set_workspace_permissions - Value = ".$bool;
#print Dumper($wsmeta);
my $wsmetas;
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$wsmetas = $impl->list_workspaces({});
};
is($@,'',"Logging as public");
#print Dumper($wsmetas);
$idhash = {};
foreach $wsmeta (@{$wsmetas}) {
	$idhash->{$wsmeta->[0]} = $wsmeta->[4];
}
ok defined($idhash->{testworkspace}),
	"list_workspaces reveals read oly workspace testworkspace to public!";
ok defined($idhash->{clonetestworkspace}),
	"list_workspaces reveals nonreadable workspace clonetestworkspace with write privelages granted to testuser1!";
ok $idhash->{testworkspace} eq "r",
	"list_workspaces says public has read only privelages to testworkspace!";
ok $idhash->{clonetestworkspace} eq "w",
	"list_workspaces says public has write privelages to clonetestworkspace!";
################################################################################
#Test 62-65: Testing types
################################################################################ 
#Testing the very basic type services
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$impl->add_type({
		type => "TempTestType",
		auth => $oauth
	});
};
my $types;
my $typehash = {};
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$types = $impl->get_types();
	foreach my $type (@{$types}) {
		$typehash->{$type} = 1;
	}
};
ok defined($typehash->{TempTestType}),
	"TempTestType exists!";
ok defined($typehash->{Genome}),
	"Genome exists!";
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$impl->remove_type({
		type => "TempTestType",
		auth => $oauth
	});
};
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$impl->remove_type({
		type => "Genome",
		auth => $oauth
	});
};
eval {
	local $Bio::KBase::workspaceService::Server::CallContext = {};
	$types = $impl->get_types();
	$typehash = {};
	foreach my $type (@{$types}) {
		$typehash->{$type} = 1;
	}
};
ok !defined($typehash->{TempTestType}),
	"TempTestType no longer exists!";
ok defined($typehash->{Genome}),
	"Genome exists!";

################################################################################
#Cleanup: clearing out all objects from the workspace database
################################################################################ 
$impl->_clearAllWorkspaces();
$impl->_clearAllWorkspaceObjects();
$impl->_clearAllWorkspaceUsers();
$impl->_clearAllWorkspaceDataObjects();

done_testing($test_count);
