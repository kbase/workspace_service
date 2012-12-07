#!/usr/bin/env perl 
# List workspaces that the user can see
use strict;
use warnings;
use Bio::KBase::workspaceService::Helpers qw(auth get_client);
my $usage = "Usage: kb_create_workspace <workspace_name> <global permission>\n";
my $workspace = shift @ARGV;
my $permission = shift @ARGV;
unless(defined ($workspace) && defined ($permission)){
    print $usage;
    exit;
}
my $serv  = get_client();

my $conf = {
    workspace => $workspace,
    default_permission => $permission,
};
my $auth = auth();
$conf->{auth} = $auth if defined($auth);
$serv->create_workspace($conf);
