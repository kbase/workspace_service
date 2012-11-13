use strict;
use warnings;
use Bio::KBase::workspaceService::Impl;
use Bio::KBase::AuthToken;
use Test::More;
use Test::Exception;
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
# Now check that list_workspaces returns only one workspace
# with each auth type (none and $tokeN)
my ($metas) = $impl->list_workspaces({});
is scalar @$metas, 1;
($metas) = $impl->list_workspaces({authentication => $token});
is scalar @$metas, 1;
$test_count += 2;
# Now test workspace listing with invalid auth token
dies_ok sub { $impl->list_workspaces({authentication => "bad" }) };
$test_count += 1;

done_testing($test_count);
