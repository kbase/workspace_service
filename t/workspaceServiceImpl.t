use FindBin qw($Bin);
use lib $Bin.'/../lib';
use Bio::KBase::workspaceService::Impl;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
my $test_count = 24;

#Creating new workspace services implementation connected to testdb
$ENV{MONGODBHOST} = "127.0.0.1";
$ENV{MONGODBDB} = "testObjectStore";
$ENV{CURRENTUSER} = "testuser";
my $impl = Bio::KBase::workspaceService::Impl->new();
#Deleting test objects
$impl->_clearAllWorkspaces();
$impl->_clearAllWorkspaceObjects();
$impl->_clearAllWorkspaceUsers();
$impl->_clearAllWorkspaceDataObjects();
#Creating a workspace called "testworkspace"
my $wsmeta = $impl->create_workspace("testworkspace","n");
ok $wsmeta->[0] eq "testworkspace",
	"create_workspace creates new workspace testworkspace!";
#Listing workspaces that user testuser has access to
my $wsmetas = $impl->list_workspaces();
my $idhash = {};
foreach $wsmeta (@{$wsmetas}) {
	$idhash->{$wsmeta->[0]} = 1;
}
ok defined($idhash->{testworkspace}),
	"list_workspaces returns newly created workspace testworkspace!";
#Adding new test object to database
my $objmeta = $impl->save_object("Test1", "TestData", {a=>1,b=>2,c=>3}, "testworkspace", {
	command => "testcommand"
});
ok $objmeta->[0] eq "Test1",
	"save_object ran and returned Test1 object with correct ID!";
#Checking if test object is present
ok $impl->has_object("Test1","TestData","testworkspace") == 1,
	"has_object successfully determined object Test1 exists!";
ok $impl->has_object("Test2","TestData","testworkspace") == 0,
	"has_object successfully determined object Test2 does not exist";
#Retrieving test object metadata from database
$objmeta = $impl->get_objectmeta("Test1","TestData","testworkspace"); 
ok $objmeta->[0] eq "Test1",
	"get_objectmeta successfully retrieved metadata for Test1!";
#Retrieving test object data from database
(my $objdata,$objmeta) = $impl->get_object("Test1","TestData","testworkspace"); 
ok $objmeta->[0] eq "Test1",
	"get_object successfully retrieved metadata for Test1!";
ok $objdata->{a} == 1,
	"get_object successfully retrieved data for Test1!";
#Copying object
$objmeta = $impl->copy_object("TestCopy","testworkspace","Test1","TestData","testworkspace");
ok $objmeta->[0] eq "TestCopy",
	"copy_object successfully returned metadata for TestCopy!";
$objmeta = $impl->move_object("TestMove","testworkspace","TestCopy","TestData","testworkspace");
ok $objmeta->[0] eq "TestMove",
	"move_object successfully returned metadata for TestMove!";
#Deleting object
$objmeta = $impl->delete_object("Test1","TestData","testworkspace");
ok $objmeta->[4] eq "delete",
	"delete_object successfully returned metadata for deleted object!";
my $objmetas = $impl->list_workspace_objects("testworkspace",{});
my $objidhash = {};
foreach $objmeta (@{$objmetas}) {
	$objidhash->{$objmeta->[0]} = 1;
}
ok !defined($objidhash->{Test1}),
	"list_workspace_objects returned object list without deleted object Test1!";
#Checking that the copied objects still exist
ok !defined($objidhash->{TestCopy}),
	"list_workspace_objects returned object list without moved object TestCopy!";
ok defined($objidhash->{TestMove}),
	"list_workspace_objects returned object list with moved result object TestMove!";
#Reverting deleted object
$objmeta = $impl->revert_object("Test1","TestData","testworkspace");
ok $objmeta->[4] eq "revert",
	"revert_object successfully undeleted Test1!";
$objmetas = $impl->list_workspace_objects("testworkspace",{});
$objidhash = {};
foreach $objmeta (@{$objmetas}) {
	$objidhash->{$objmeta->[0]} = 1;
}
ok defined($objidhash->{Test1}),
	"list_workspace_objects now returns undeleted object Test1!";
#Unreverted deleted object
$objmeta = $impl->unrevert_object("Test1","TestData","testworkspace",{});
ok $objmeta->[4] eq "delete",
	"unrevert_object returns Test1 to a deleted state!";
$objmetas = $impl->list_workspace_objects("testworkspace",{});
$objidhash = {};
foreach $objmeta (@{$objmetas}) {
	$objidhash->{$objmeta->[0]} = 1;
}
ok !defined($objidhash->{Test1}),
	"list_workspace_objects now fails to return deleted object Test1!";
#Cloning workspace
$wsmeta = $impl->clone_workspace("clonetestworkspace","testworkspace","n");
$objmetas = $impl->list_workspace_objects("clonetestworkspace",{});
$objidhash = {};
foreach $objmeta (@{$objmetas}) {
	$objidhash->{$objmeta->[0]} = 1;
}
ok defined($objidhash->{TestMove}),
	"clone_workspace successfully recreates workspace with identical objects!";
#Changing workspace global permissions
$wsmeta = $impl->set_global_workspace_permissions("r","testworkspace");
ok $wsmeta->[5] eq "r",
	"set_global_workspace_permissions changes global permissions on testworkspace to read only!";
#Changing workspace user permissions global permissions
$impl->set_workspace_permissions(["testuser1"],"w","clonetestworkspace");
#Logging as testuser1 to check permissions
$ENV{CURRENTUSER} = "testuser1";
my $implTwo = Bio::KBase::workspaceService::Impl->new();
$wsmetas = $implTwo->list_workspaces();
$idhash = {};
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
#Deleting test objects
$impl->delete_workspace("testworkspace");
$impl->delete_workspace("clonetestworkspace");
$impl->_deleteWorkspaceUser("testuser1");
$impl->_deleteWorkspaceUser("testuser");

done_testing($test_count);
