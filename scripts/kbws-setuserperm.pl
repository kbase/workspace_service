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
use Bio::KBase::workspaceService::Helpers qw(auth get_ws_client workspace workspaceURL parseObjectMeta parseWorkspaceMeta);

my $serv = get_ws_client();
#Defining globals describing behavior
my $primaryArgs = ["users","new permission"];
my $servercommand = "set_workspace_permissions";
my $translation = {
    users => "users",
	"new permission" => "new_permission",
};
#Defining usage and options
my ($opt, $usage) = describe_options(
    'kbws-setuserperm <'.join("> <",@{$primaryArgs}).'> %o',
    [ 'workspace|w:s', 'ID for workspace', {"default" => workspace()} ],
    [ 'help|h|?', 'Print this usage information' ]
    
);
$opt->{command} = "kb_load";
#Processing primary arguments
foreach my $arg (@{$primaryArgs}) {
	$opt->{$arg} = shift @ARGV;
	if (!defined($opt->{$arg})) {
		print $usage;
    	exit;
	}
}
#Instantiating parameters
my $params = {
	auth => auth(),
};
foreach my $key (keys(%{$translation})) {
	if (defined($opt->{$key})) {
		$params->{$translation->{$key}} = $opt->{$key};
	}
}
#Calling the server
my $output;
eval {
	$output = $serv->$servercommand($params);
};
#Checking output and report results
if (!defined($output)) {
	print "Can not set user permissions\n";
} else {
	my $obj = parseWorkspaceMeta($output);
	print "User permissions set for '".$obj->{id}."";
}
