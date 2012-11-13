#!/usr/bin/env perl
# List the contents of the current workspace
use strict;
use warnings;
use Bio::KBase::workspaceService::Helpers qw(workspace get_client auth);
my $usage = "Usage: kb_put <id> <type> [options] < data";
my $id = shift;
my $type = shift;
unless ( defined $type && defined $id && !-t STDIN) {
    print $usage;
    exit;
}
my $serv = get_client();
my $conf = {
    id => $id,
    type => $type,
    data => get_data(),
    workspace => workspace(),
    command => "save_object",
};
my $auth = auth();
$conf->{authorization} = $auth if defined $auth;
$serv->save_object($conf);

sub get_data {
    my $data = "";
    while ( <STDIN> ) {
        $data .= $_;
    }
    return $data;
}
