#!/usr/bin/env perl 
# List workspaces that the user can see
use strict;
use warnings;
use Bio::KBase::workspaceService::Helpers qw(workspace auth get_client);
my $usage = "Usage: kb_set_permissions <permission> <users>\n";
my $permission = shift @ARGV;
my $users = shift @ARGV;
my $userList = [split(/;/,$users)];
unless(defined ($permission) && defined ($users)){
    print $usage;
    exit;
}
my $conf = {
	users => $userList,
	new_permission => $permission,
    workspace => workspace(),
};
my $auth = auth();
$conf->{auth} = $auth if defined($auth);
my $serv  = get_client();
$serv->set_workspace_permissions($conf);