#!/usr/bin/env perl
# List the contents of the current workspace
use strict;
use warnings;
use JSON;
use Getopt::Long::Descriptive;
use Text::Table;
use Bio::KBase::workspaceService::Helpers qw(workspace get_client auth);
my ($opts, $usage) = describe_options(
    'kb_get %o <type> <id>',
    [ 'filename|f:s', 'Print data out to named file' ],
    #[ 'metadata|m:s', 'Print metadata out to named file' ],
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
$conf->{authentication} = $auth if defined $auth;
my ($rtv) = $serv->get_object($conf);
# If we haven't printed data or metadata to a file
# print the data to STDOUT
my $done = 0;
if ($opts->filename) {
    print_file($rtv->{data}, $opts->filename);
    $done = 1;
}
#if ($opts->metadata) {
#    print_file($rtv->{meta}, $opts->metadata);
#    $done = 1;
#}
unless($done) {
    print STDOUT encode_data($rtv->{data}) if defined $rtv->{data};
}

sub print_file {
    my ($str, $file) = @_;
    return unless defined $str;
    $str = encode_data($str);
    # If the $str is a ref, encode as JSON
    open(my $fh, ">", $file) || die "Could not open $file: $!";
    print $fh $str;
    close($fh);
}

sub encode_data {
    my ($str) = @_;
    if (ref($str)) {
        $str = encode_json $str;
    }
    return $str;
}

