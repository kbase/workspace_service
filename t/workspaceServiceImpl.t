use FindBin qw($Bin);
use lib $Bin.'/../lib';
use Bio::KBase::workspaceService::Impl;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
my $test_count = 24;

#  Test 1 - Can a new impl object be created without parameters? 
#Creating new workspace services implementation connected to testdb
$ENV{MONGODBHOST} = "127.0.0.1";
$ENV{MONGODBDB} = "testObjectStore";
# Create an authorization token
my $token = Bio::KBase::AuthToken->new(
    user_id => 'kbasetest', password => '@Suite525'
);
my $impl = Bio::KBase::workspaceService::Impl->new();
ok( defined $impl, "Did an impl object get defined" );    

#  Test 2 - Is the impl object in the right class?
isa_ok( $impl, 'Bio::KBase::workspaceService::Impl', "Is it in the right class" );   

# Gene calling methods that takes a genomeTO as input
my @impl_methods = qw(
  create_workspace
  delete_workspace
  clone_workspace
  list_workspaces
  list_workspace_objects
  set_global_workspace_permissions
  set_workspace_permissions
  save_object
  delete_object
  delete_object_permanently
  get_object
  get_objectmeta
  revert_object
  unrevert_object
  copy_object
  move_object
  has_object
);

#  Test 3 - Can the object do all of the methods
can_ok($impl, @impl_methods);    

#Deleting test objects
$impl->_clearAllWorkspaces();
$impl->_clearAllWorkspaceObjects();
$impl->_clearAllWorkspaceUsers();
$impl->_clearAllWorkspaceDataObjects();

note("create_workspace called testworkspace");
#TESTS Creating a workspace called "testworkspace"

my $wsmeta = $impl->create_workspace({workspace=>"testworkspace",default_permission=>"a",auth=>$token->token()});
is($@,'',"create workspace works without error");
is(ref($wsmeta),'ARRAY', "Did the create_workspace return an ARRAY (workspace_metadata)?");
ok $wsmeta->[0] eq "testworkspace", "create_workspace creates new workspace testworkspace!";

eval{$wsmeta = $impl->create_workspace({workspace=>"testworkspace",default_permission=>"n",auth=>$token->token()});};
isnt($@,'',"Attempt to create duplicate workspace fails");

eval{$wsmeta = $impl->create_workspace({workspace=>"testworkspace",default_permission=>"g",auth=>$token->token()});};
isnt($@,'',"Attempt to create workspace with bad permissions fails");

eval{$wsmeta = $impl->create_workspace({workspace=>"testworkspace",auth=>$token->token()});};
isnt($@,'',"Attempt to create workspace with no permissions fails");

eval{$wsmeta = $impl->create_workspace("testworkspace",'n',auth=>$token->token());};
isnt($@,'',"Attempt to create workspace without a hash reference  fails");

note("list_workspaces");
#Listing workspaces that user testuser has access to
my $wsmetas;

eval { $wsmetas = $impl->list_workspaces({auth=>$token->token()}); };
is($@,'',"list workspace works without error");
is(ref($wsmetas),'ARRAY', "Did the list_workspace return an ARRAY (workspace_metadata objects)?");
isnt(scalar $#{$wsmetas}, -1, "Was the returned ARRAY not empty?");
is($wsmetas->[0]->[0],'testworkspace',"Was the returned name testworkspace");

$wsmeta = $impl->create_workspace({workspace=>"testworkspace2",default_permission=>"r",auth=>$token->token()});
ok $wsmeta->[0] eq "testworkspace2", "create_workspace creates 2nd workspace testworkspace with write-only permissions!";

#
#  Switch to adding objects to this workspace for the next few tests
#

my $data = "This is my data string";
my %metadata = (a=>1,b=>2,c=>3);
my $conf = {
        id => "Test1",
        type => "Genome",
        data => $data,
        workspace => "testworkspace",
        command => "string",
        metadata => \%metadata,
        auth => $token->token()
    };
my $conf1 = {
        id => "Test1",
        type => "Genome",
        workspace => "testworkspace",
        auth => $token->token()
    };
my $conf2 = {
        id => "Test2",
        type => "Genome",
        workspace => "testworkspace",
        auth => $token->token()
    };

note("Test Adding Objects to the workspace testworkspace");
#Adding new test object to database
my $objmeta = $impl->save_object($conf);
is(ref($objmeta),'ARRAY', "Did the save_object return an ARRAY ?");

ok $objmeta->[0] eq "Test1",
	"save_object ran and returned Test1 object with correct ID!";

#Test should fail gracefully when sending bad parameters
eval { $wsmeta = $impl->has_object($wsmetas); };
isnt($@,'', "Confirm bad input parameters fails gracefully ");

#Checking if test object is present
$wsmeta = $impl->has_object($conf1);
is($wsmeta,1,"has_object successfully determined object Test1 exists!");

eval { $wsmeta = $impl->has_object($conf2); };
isnt($@,'', "Confirm that Test2 does not exist");
#Documentation claims that 0 is returned when this is unsuccessful.  Not true
#is($wsmeta,0,"has_object successfully determined object Test2 does not exist!");

note("Retrieving test object data from database");
#Retrieving test object data from database
$objmeta = [];

eval { ($data,$objmeta) = $impl->get_object($conf1); };
is($@,"","Retrieving test object data from database");

if (exists $objmeta->[0])
{
ok $objmeta->[0] eq "Test1",
	"get_object successfully retrieved object Test1!";
}

note("Retrieving test object metadata from database");
#Retrieving test object metadata from database
$objmeta = $impl->get_objectmeta($conf1); 
ok $objmeta->[0] eq "Test1",
	"get_objectmeta successfully retrieved metadata for Test1!";

#Copying object
    $conf2 = {
        new_id => "TestCopy",
        new_workspace => "testworkspace2",
        source_id => "Test1",
        type => "Genome",
        source_workspace => "testworkspace",
        auth => $token->token()
    };

note("copy_object from testworkspace to testworkspace2");
$objmeta = $impl->copy_object($conf2);
ok $objmeta->[0] eq "TestCopy",
	"copy_object successfully returned metadata for TestCopy!";

note("move_object from testworkspace to testworkspace2");
$conf2->{'new_id'} = 'TestMove';
$objmeta = $impl->move_object($conf2);
ok $objmeta->[0] eq "TestMove",
	"move_object successfully returned metadata for TestMove!";

note("Delete object TestCopy from testworkspace2");
 $conf2 = {
        id => "TestCopy",
        type => "Genome",
        workspace => "testworkspace2",
        auth => $token->token()
    };

#Deleting object
 $objmeta = $impl->delete_object($conf2);
ok $objmeta->[4] eq "delete",
	"delete_object successfully returned metadata for deleted object!";

#Reverting deleted object
$objmeta = $impl->revert_object($conf2);
print Dumper($objmeta);
ok $objmeta->[4] eq "revert",
#	"revert_object successfully undeleted TestCopy!";
my $objmetas = $impl->list_workspace_objects( { workspace=>"testworkspace2"});
my $objidhash = {};
foreach $objmeta (@{$objmetas}) {
	$objidhash->{$objmeta->[0]} = 1;
}
ok defined($objidhash->{TestCopy}),
	"list_workspace_objects now returns undeleted object TestCopy!";
	
note("List the objects in testworkspace");
$objmetas = $impl->list_workspace_objects( { workspace=>"testworkspace",auth => $token->token()});
$objidhash = {};
foreach $objmeta (@{$objmetas}) {
	$objidhash->{$objmeta->[0]} = 1;
}

ok !defined($objidhash->{Test1}),
	"list_workspace_objects returned object list without deleted object Test1!";
#Checking that the copied objects still exist
ok !defined($objidhash->{TestCopy}),
	"list_workspace_objects returned object list without copied object TestCopy!";
ok !defined($objidhash->{TestMove}),
	"list_workspace_objects returned object list without moved result object TestMove!";

note("List the objects in testworkspace2");
$objmetas = $impl->list_workspace_objects( { workspace=>"testworkspace2",auth => $token->token()});
$objidhash = {};
foreach $objmeta (@{$objmetas}) {
	$objidhash->{$objmeta->[0]} = 1;
}

ok !defined($objidhash->{Test1}),
	"list_workspace_objects returned object list without deleted object Test1!";
#Checking that the copied objects still exist
ok !defined($objidhash->{TestCopy}),
	"list_workspace_objects returned object list without copied object TestCopy!";
ok defined($objidhash->{TestMove}),
	"list_workspace_objects returned object list with moved result object TestMove!";

#
#  Back to workspaces
#

$conf2 = {
        new_workspace => "clonetestworkspace",
        current_workspace => "testworkspace2",
        default_permission => "n",
        auth => $token->token()
};

#Cloning workspace
$wsmeta = $impl->clone_workspace($conf2);
$objmetas = $impl->list_workspace_objects({ workspace=>"clonetestworkspace",auth => $token->token()});
$objidhash = {};
foreach $objmeta (@{$objmetas}) {
	$objidhash->{$objmeta->[0]} = 1;
}
ok defined($objidhash->{TestMove}),
	"clone_workspace successfully recreates workspace with identical objects!";

$conf = {
        workspace => "testworkspace",
        new_permission => "r",
        auth => $token->token()
    };

#Changing workspace global permissions
eval { $wsmeta = $impl->set_global_workspace_permissions($conf); };
is($@,'',"set_global_workspace_permissions - testworkspace to r - Command ran without errors");
ok $wsmeta->[5] eq "r",
	"set_global_workspace_permissions - Value = $wsmeta->[5] ";

#Changing workspace user permissions global permissions
$conf = {
        workspace => "clonetestworkspace",
        new_permission => "w",
		users => ["public"],
		auth => $token->token()
    };

$wsmeta='';
eval { $wsmeta = $impl->set_workspace_permissions($conf); };
is($@,'',"set_workspace_permissions - user global permissions for clonetestworkspace to w - Command ran without errors");
if (ref($wsmeta) eq 'ARRAY')
{
	ok $wsmeta->[5] eq "w",
		"set_workspace_permissions - Value = $wsmeta->[5] ";
	print Dumper($wsmeta);
}

eval { $wsmetas = $impl->list_workspaces({}); };
is($@,'',"Logging as public");

print Dumper($wsmetas);
my $idhash = {};
foreach $wsmeta (@{$wsmetas}) {
	$idhash->{$wsmeta->[0]} = $wsmeta->[4];
}
ok defined($idhash->{testworkspace}),
	"list_workspaces reveals read oly workspace testworkspace to testuser1!";
ok defined($idhash->{clonetestworkspace}),
	"list_workspaces reveals nonreadable workspace clonetestworkspace with write privelages granted to testuser1!";
ok $idhash->{testworkspace} eq "r",
	"list_workspaces says testuser1 has read only privelages to testworkspace!";
ok $idhash->{clonetestworkspace} eq "w",
	"list_workspaces says testuser1 has write privelages to clonetestworkspace!";

done_testing($test_count);
