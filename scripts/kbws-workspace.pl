#!/usr/bin/env perl
########################################################################
# Authors: Christopher Henry, Scott Devoid, Paul Frybarger
# Contact email: chenry@mcs.anl.gov
# Development location: Mathematics and Computer Science Division, Argonne National Lab
########################################################################
use strict;
use warnings;
use Getopt::Long::Descriptive;
use Text::Table;
use Bio::KBase::workspaceService::Helpers qw(auth get_ws_client workspace workspaceURL parseObjectMeta parseWorkspaceMeta printObjectMeta);
#Defining globals describing behavior
my $primaryArgs = ["New workspace"];
#Defining usage and options
my ($opt, $usage) = describe_options(
    'kbws-workspace <'.join("> <",@{$primaryArgs}).'> %o',
    [ 'help|h|?', 'Print this usage information' ],
);
my $workspace = workspace($ARGV[0]);
if (defined($workspace)) {
	print "Current workspace is:\n".$workspace."\n";
} else {
	print "No workspace currently selected!\n";
}

