#!/usr/bin/env perl 
# List workspaces that the user can see
use strict;
use warnings;
use Getopt::Long::Descriptive;
use Text::Table;
use Bio::KBase::workspaceService::Helpers qw(auth workspace get_client);
my ($opt, $usage) = describe_options(
    'kb_list_workspaces %o',
    [ 'verbose|v', 'Print metadata associated with workspace' ],
    [ 'help|h|?', 'Print this usage information' ],
);
print($usage->text), exit if $opt->help;
my $serv  = get_client();
my $conf = {};
my $auth = auth();
$conf->{authentication} = $auth if defined($auth);
my ($ws_metas) = $serv->list_workspaces($conf);
if ($opt->verbose) {
    _verbose($ws_metas);
} else {
    print join("\n", map { $_->[0] } @$ws_metas ) . "\n";
}

sub _verbose {
    my $metas = shift;
    my $table = Text::Table->new(
        'ID', 'Owner', 'Last Modified', 'Objects', 'U', 'G'
    );
    $table->load(@$metas);
    print $table;
}
