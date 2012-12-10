#!/usr/bin/env perl 
# List workspaces that the user can see
use strict;
use warnings;
use Bio::KBase::workspaceService::Helpers qw(workspace auth get_client);
my $usage = "Usage: kb_set_permissions <permission>\n";
my $permission = shift @ARGV;
unless(defined ($permission)){
    print $usage;
    exit;
}
my $conf = {
	new_permission => $permission,
    workspace => workspace(),
};
my $auth = auth();
$conf->{auth} = $auth if defined($auth);
my $serv  = get_client();
$serv->set_global_workspace_permissions($conf);