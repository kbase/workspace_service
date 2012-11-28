#!/usr/bin/env perl 
# Get or set the current workspace
use strict;
use warnings;
use Bio::KBase::workspaceService::Helpers qw(workspace);
my $usage = "Usage: kb_workspace [<workspace_name>]";
my $set_workspace = shift @ARGV;
my $workspace;
if ( defined $set_workspace ) {
    $workspace = workspace($set_workspace) . "\n";
} else {
    $workspace = workspace();
}
$workspace = "" unless defined $workspace;
print "$workspace\n";
