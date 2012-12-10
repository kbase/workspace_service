#!/usr/bin/env perl 
# List workspaces that the user can see
use strict;
use warnings;
use Getopt::Long::Descriptive;
use Bio::KBase::workspaceService::Helpers qw(workspace auth get_client);
my ($opts, $usage) = describe_options(
    'kb_delete_object <type> <object id> %o',
    [ 'permanent|p', 'Permanently delete object (cannot recover)' ],
    [ 'help|h|?',     'Print this usage information' ],
);
my $auth = auth();
my $type = shift @ARGV;
my $id = shift @ARGV;
unless(defined ($type) && defined ($id)){
    print $usage;
    exit;
}
my $serv = get_client();
my $conf = {
    id => $id,
    type => $type,
    workspace => workspace(),
};
$conf->{auth} = $auth if defined $auth;
if ($serv->has_object($conf) == 1 && $serv->get_objectmeta($conf)->[4] ne "deleted") {
	$serv->delete_object($conf);
}
if ($opts->{permanent} == 1) {
	$serv->delete_object_permanently($conf);
}