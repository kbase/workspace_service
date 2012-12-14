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
my $primaryArgs = ["Object type","Object ID","Filename or URL"];
my $servercommand = "save_object";
my $translation = {
	"Object ID" => "id",
	"Object type" => "type",
    metadata => "metadata",
    compressed => "compressed",
    fromurl => "retrieveFromURL",
    workspace => "workspace"
};
#Defining usage and options
my ($opt, $usage) = describe_options(
    'kbws-load <'.join("> <",@{$primaryArgs}).'> %o',
    [ 'workspace|w=s', 'ID for workspace', {"default" => workspace()} ],
    [ 'metadata|m:s', 'Filename with metadata to associate with object' ],
    [ 'compressed|c', 'Uploaded data will be compressed' , {"default" => 0} ],
    [ 'fromurl|r', 'gets from url' , {"default" =>0} ],
    [ 'showerror|e', 'Set as 1 to show any errors in execution',{"default"=>0}],
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
if ($opt->{showerror} == 0){
    eval {
        $output = $serv->$servercommand($params);
    };
}else{
    $output = $serv->$servercommand($params);
}
#Checking output and report results
if (!defined($output)) {
	print "Object could not be saved!\n";
} else {
	print "Object saved:\n".printObjectMeta($output)."\n";
}
