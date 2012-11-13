use Bio::KBase::workspaceService::Impl;
use Bio::KBase::AuthToken;
use strict;
use warnings;
use Test::More;
use Data::Dumper;
my $test_count = 0;

$ENV{MONGODBHOST} = "127.0.0.1";
$ENV{MONGODBDB} = "testObjectStore";
my $impl = Bio::KBase::workspaceService::Impl->new();
#Deleting test objects
$impl->_clearAllWorkspaces();
$impl->_clearAllWorkspaceObjects();
$impl->_clearAllWorkspaceUsers();
$impl->_clearAllWorkspaceDataObjects();
# Create an authorization token
my $token = Bio::KBase::AuthToken->new(
    user_id => 'kbasetest', password => '@Suite525'
);
$token = $token->token;
# Test creating a workspace with this token
my ($meta) = $impl->create_workspace({
        workspace => "testworkspace",
        default_permission => "n",
        authentication => $token,
});
is $meta->[0], "testworkspace";
is $meta->[1], "kbasetest";
# Now test creating a workspace without an auth token
my ($meta2) = $impl->create_workspace({
        workspace => "test_two",
        default_permission => "n",
});
isnt $meta2->[0], $meta->[0];
isnt $meta2->[1], $meta->[1];
$test_count += 4;

done_testing($test_count);


