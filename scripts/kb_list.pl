#!/usr/bin/env perl 
# List the contents of the current workspace
use strict;
use warnings;
use Data::Dumper;
use Bio::KBase::workspaceService::Helpers qw(workspace get_client auth);
my $usage = "Usage: kb_list [options]";
my $serv = get_client();
my $conf = {
    workspace => workspace(),
};
my $auth = auth();
$conf->{authorization} = $auth if defined $auth;
my ($metas) = $serv->list_workspace_objects($conf);
print join("\t", qw(id type) ) . "\n";
print join("\n", map { $_->[0] . "\t" . $_->[1] } @$metas) . "\n";
