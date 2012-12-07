#!/usr/bin/env perl
# List the contents of the current workspace
use strict;
use warnings;
use JSON;
use Getopt::Long::Descriptive;
use Text::Table;
use Bio::KBase::workspaceService::Helpers qw(workspace get_client auth);
my ($opts, $usage) = describe_options(
    'kb_has_object <type> <id> %o',
    [ 'help|h|?',     'Print this usage information' ],
 );

my ($type, $id) = @ARGV;
print($usage->text), exit unless defined $type && defined $id;
my $serv = get_client();
my $conf = {
    id => $id,
    type => $type,
    workspace => workspace(),
};
my $auth = auth();
$conf->{auth} = $auth if defined $auth;
my ($result) = $serv->has_object($conf);
if ($result == 0) {
	print "Object not found!\n";
} else {
	print "Object exists!\n";
}
