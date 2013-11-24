#!/usr/bin/env perl
########################################################################
# Authors: Christopher Henry, Scott Devoid, Paul Frybarger
# Contact email: chenry@mcs.anl.gov
# Development location: Mathematics and Computer Science Division, Argonne National Lab
########################################################################
use strict;
use warnings;
use Getopt::Long::Descriptive;
use Bio::KBase::workspaceService::Helpers qw(printObjectMeta auth get_ws_client workspace workspaceURL parseObjectMeta parseWorkspaceMeta);

my ($opt, $usage) = describe_options(
    'InitializeFromSourceWorkspace.pl <URL> %o',
    [ 'help|h|?', 'Print this usage information' ]
);

if (defined($opt->{help})) {
	print $usage;
    exit;
}

my $url = $ARGV[0];
my $source = get_ws_client($url);
my $target = get_ws_client();

my $wslist = [
	"kbase",
	"KBaseMedia",
	"KBasePhenotypeDatasets",
	"KBaseTemplateModels"
];

my $workspaces = $target->list_workspaces({auth => auth()});

for (my $i=0; $i < @{$wslist}; $i++) {
	my $found = 0;
	my $ws = $wslist->[$i];
	for (my $j=0; $j < @{$workspaces}; $j++) {
		if ($workspaces->[$j]->[0] eq $ws) {
			$found = 1;
			last;
		}
	}
	if ($found == 0) {
		$target->create_workspace({
			workspace => $ws,
			default_permission => "r",
			auth => auth()
		});
	}
	my $list = $source->list_workspace_objects({
		workspace => $ws,
	});
	for (my $j=0; $j < @{$list}; $j++) {
		if ($target->has_object({
			id => $list->[$j]->[0],
			type => $list->[$j]->[1],
			workspace => $ws
		}) == 0) {
			my $output = $source->get_object({
				id => $list->[$j]->[0],
				type => $list->[$j]->[1],
				workspace => $ws
			});
			if (defined($output->{data})) {
				$target->save_object({
					id => $list->[$j]->[0],
					type => $list->[$j]->[1],
					data => $output->{data},
					workspace => $ws,
					command => $list->[$j]->[4],
					auth => auth()
				});
			}	
		}
		
	}
}