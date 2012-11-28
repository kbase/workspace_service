#!/usr/bin/env perl
# List the contents of the current workspace
use strict;
use warnings;
use JSON;
use Getopt::Long::Descriptive;
use Try::Tiny;
use Bio::KBase::workspaceService::Helpers qw(workspace get_client auth);
my ($opts, $usage) = describe_options(
    'kb_put %o <type> <id>',
    [ 'filename|f:s', 'Pass in data from a named file'],
    [ 'metadata|m:s', 'Set metadata from a named JSON file'],
    [ 'help|h|?',     'Print this usage information' ],
);
my ($type, $id)  = @ARGV;
my $data = try_decode_data(get_data($opts));
print($usage->text), exit if $opts->help;
print($usage->text), exit unless defined $type && defined $id;
print($usage->text), exit unless defined $data;
my $serv = get_client();
my $conf = {
    id => $id,
    type => $type,
    data => $data,
    workspace => workspace(),
    command => "save_object",
};
my $auth = auth();
$conf->{authentication} = $auth if defined $auth;
# Populate the metadata if the user provided a file containing that
$conf->{metadata} = decode_json get_from_file($opts->metadata) if defined $opts->metadata;
$serv->save_object($conf);

# Try to decode data as JSON, otherwise return the string
sub try_decode_data {
    my $str = shift;
    my $json;
    try {
        $json = decode_json $str;
    };
    return $json if defined $json;
    return $str;
}

sub get_data {
    my $opts = shift;
    if (defined $opts->filename ) {
        return get_from_file($opts->filename);
    } elsif( !-t STDIN ) {
        my $data = "";
        while ( <STDIN> ) {
            $data .= $_;
        }
        return $data;
    } else {

    }
}

sub get_from_file {
    my $file = shift;
    my $str;
    {
        open(my $fh, "<", $file) 
            || die "Unable to open $file: $!";
        local $/;
        $str = <$fh>;
        close($fh);  
    }
    return $str;
}
