#!/usr/bin/env perl 
# List workspaces that the user can see
use strict;
use warnings;
use Bio::KBase::workspaceService::Helpers qw(auth get_client);
my $usage = "Usage: kb_create_workspace <workspace_name>";
my $workspace = shift @ARGV;
unless(defined ($workspace)){
    print $usage;
    exit;
}
my $serv  = get_client();

my $conf = {
    workspace => $workspace,
    default_permission => "n",
};
my $auth = auth();
$conf->{authorization} = $auth if defined($auth);
$serv->create_workspace($conf);
