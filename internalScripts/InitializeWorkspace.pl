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
use Bio::KBase::workspaceService::Helpers qw(printObjectMeta auth get_ws_client workspace workspaceURL parseObjectMeta parseWorkspaceMeta);

my ($opt, $usage) = describe_options(
    'InitializeWorkspace %o',
    [ 'bio|b', 'Import biochemistry' ],
    [ 'testbio|t', 'Import test biochemistry' ],
    [ 'map|m', 'Import mapping' ],
    [ 'testmap|e', 'Import test mapping' ],
    [ 'media|d', 'Load media from biochemistry' ],
    [ 'overwrite|o', 'Overwrite on import' ],
    [ 'help|h|?', 'Print this usage information' ]
);

if (defined($opt->{help})) {
	print $usage;
    exit;
}

my $serv = get_ws_client();
my $output;
if (defined($opt->{bio})) {
$output = $serv->import_bio({
	auth => auth(),
	overwrite => $opt->{overwrite}
});
if (!defined($output)) {
	print "Biochemistry could not be imported!\n";
} else {
	print "Biochemistry saved:\n".printObjectMeta($output)."\n";
}
}
if (defined($opt->{testbio})) {
	$output = $serv->import_bio({
		bioid => "testdefault",
		url => "http://bioseed.mcs.anl.gov/~chenry/KbaseFiles/biochemistry.test.json",
		compressed => 0,
		auth => auth(),
		overwrite => $opt->{overwrite}
	});
	if (!defined($output)) {
		print "Test biochemistry could not be imported!\n";
	} else {
		print "Test biochemistry saved:\n".printObjectMeta($output)."\n";
	}
}
if (defined($opt->{"map"})) {
	$output = $serv->import_map({
		auth => auth(),
		overwrite => $opt->{overwrite}
	});
	if (!defined($output)) {
		print "Mapping could not be imported!\n";
	} else {
		print "Mapping saved:\n".printObjectMeta($output)."\n";
	}
}
if (defined($opt->{testmap})) {
	$output = $serv->import_map({
		bioid => "testdefault",
		mapid => "testdefault",
		url => "http://bioseed.mcs.anl.gov/~chenry/KbaseFiles/mapping.test.json",
		compressed => 0,
		auth => auth(),
		overwrite => $opt->{overwrite}
	});
	if (!defined($output)) {
		print "Test mapping could not be imported!\n";
	} else {
		print "Test mapping saved:\n".printObjectMeta($output)."\n";
	}
}
if (defined($opt->{media})) {
	$output = $serv->load_media_from_bio({
		auth => auth(),
		overwrite => $opt->{overwrite}
	});
	if (!defined($output)) {
		print "Media load failed!\n";
	} else {
		print @{$output}." media loaded!\n";
	}
}