#!/usr/bin/env perl 
# List workspaces that the user can see
use strict;
use warnings;
use Bio::KBase::workspaceService::Helpers qw(auth workspace get_client);
my $usage = "Usage: kb_list_workspaces";
my $serv  = get_client();
my $conf = {};
my $auth = auth();
$conf->{authorization} = $auth if defined($auth);
my ($ws_metas) = $serv->list_workspaces($conf);
print join("\n", map { $_->[0] } @$ws_metas ) . "\n";
