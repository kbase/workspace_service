use FindBin qw($Bin);
use lib $Bin.'/../lib';
use Bio::KBase::workspaceService::Impl;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
my $test_count = 42;

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


#Deleting test objects
$impl->_clearAllWorkspaces();
$impl->_clearAllWorkspaceObjects();
$impl->_clearAllWorkspaceUsers();
$impl->_clearAllWorkspaceDataObjects();

my $oauth_token = $token->token();
# Can I create a test workspace
my $wsmeta1 = $impl->create_workspace({workspace=>"testworkspace1",default_permission=>"n",auth=>$oauth_token});

ok(defined $wsmeta1, "workspace defined");

ok($wsmeta1->[0] eq "testworkspace1", "created workspace");

ok($wsmeta1->[1] eq "kbasetest", "user == kbasetest");

ok($wsmeta1->[3] eq 0, "ws has no objects");

ok($wsmeta1->[4] eq "a", "ws has a user perms");

ok($wsmeta1->[5] eq "n", "ws has n global perms");

# Is the workspace listed

my $workspace_list = $impl->list_workspaces({auth=>$oauth_token});

ok(@{$workspace_list}[0]->[0] eq "testworkspace1", "name matches");

# Create a few more workspaces
lives_ok { $impl->create_workspace({workspace=>"testworkspace2",default_permission=>"r",auth=>$oauth_token}); } "create read-only ws";
lives_ok { $impl->create_workspace({workspace=>"testworkspace3",default_permission=>"a",auth=>$oauth_token}); } "create admin ws";
lives_ok { $impl->create_workspace({workspace=>"testworkspace4",default_permission=>"w",auth=>$oauth_token}); } "create rw ws";
lives_ok { $impl->create_workspace({workspace=>"testworkspace5",default_permission=>"n",auth=>$oauth_token}); } "create no perm ws";

$workspace_list = $impl->list_workspaces({auth=>$oauth_token});

# Makes sure the length matches
ok(scalar(@{$workspace_list}) eq 5, "length matches");


my $idhash={};
my $ws;
foreach $ws (@{$workspace_list}) {
	$idhash->{$ws->[0]} = 1;
}

ok(defined($idhash->{testworkspace3}),
   "list_workspaces returns newly created workspace testworkspace!");
    
# Does creating a duplicate workspace fail

dies_ok { $impl->create_workspace({workspace=>"testworkspace1",default_permission=>"n",auth=>$oauth_token}) } "create duplicate fails";


# Can I delete a workspace
lives_ok { $impl->delete_workspace("testworkspace1")  } "delete succeeds";
# Does deleting a non-existent workspace fail
dies_ok { $impl->delete_workspace("testworkspace_foo")  } "delete for non-existent ws fails";
# Does deleting a previously deleted workspace fail
dies_ok { $impl->delete_workspace("testworkspace1")  } "duplicate delete fails";

# Can I clone a workspace
lives_ok{ $impl->clone_workspace("clonetestworkspace2","testworkspace2", "n") } "clone succeeds";
$impl->delete_workspace("clonetestworkspace2");


# Does cloning a deleted workspace fail
dies_ok{ $impl->clone_workspace("clonetestworkspace1","testworkspace1", "n") } "clone a deleted workspace should fail";

# Can I clone a workspace without specifying perms
lives_ok{ $impl->clone_workspace("clonetestworkspace3","testworkspace3") } "clone without perms argument succeeds";
$impl->delete_workspace("clonetestworkspace3");


# Does the cloned workspace match the original

# Does the cloned workspace preserve permissions

# Can I list workspace objects

# Can I write to a read only workspace?

# Test multiple users

# Clean up
$impl->delete_workspace("testworkspace2");
$impl->delete_workspace("testworkspace3");
$impl->delete_workspace("testworkspace4");
$impl->delete_workspace("testworkspace5");



#Deleting test objects
$impl->delete_workspace("testworkspace");

$impl->_deleteWorkspaceUser("kbasetest");

done_testing($test_count);