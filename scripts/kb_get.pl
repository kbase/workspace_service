#!/usr/bin/env perl
# List the contents of the current workspace
use strict;
use warnings;
use Getopt::Long::Descriptive;
use Text::Table;
use Bio::KBase::workspaceService::Helpers qw(workspace get_client auth);
my $usage = "Usage: kb_get <id> <type> [options] > data";
my $id = shift;
my $type = shift;
unless ( defined $type && defined $id) {
    print $usage;
    exit;
}
my $serv = get_client();
my $conf = {
    id => $id,
    type => $type,
    workspace => workspace(),
};
my $auth = auth();
$conf->{authentication} = $auth if defined $auth;
my ($rtv) = $serv->get_object($conf);
print STDOUT $rtv->{data} if defined $rtv->{data};
