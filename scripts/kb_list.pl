#!/usr/bin/env perl 
# List the contents of the current workspace
use strict;
use warnings;
use Getopt::Long::Descriptive;
use Text::Table;
use Bio::KBase::workspaceService::Helpers qw(workspace get_client auth);
my ($opts, $usage) = describe_options(
    'kb_list %o',
    [ 'type|t:s',   'List only objects that match a specific type' ],
    [ 'verbose|v',  'Print detailed metadata about each object in the workspace'],
    [ 'help|h|?',   'Print this usage information' ],
);
print($usage->text), exit if $opts->help;

my $serv = get_client();
my $conf = {
    workspace => workspace(),
};
my $auth = auth();
$conf->{authentication} = $auth if defined $auth;
$conf->{type} = $opts->type if defined $opts->type;
my ($metas) = $serv->list_workspace_objects($conf);
if ($opts->verbose) {
    _verbose($metas);
} else {
    print join("\t", qw(type id) ) . "\n";
    print join("\n", map { $_->[1] . "\t" . $_->[0] } @$metas) . "\n";
}

sub _verbose {
    my $metas = shift;
    my $table = Text::Table->new(
        'ID', 'Type', 'Last Modified', 'Version', 'Command', 'Modified By', 'Owner'
    );
    $table->load(@$metas);
    print $table;
}
