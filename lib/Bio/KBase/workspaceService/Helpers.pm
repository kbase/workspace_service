package Bio::KBase::workspaceService::Helpers;
use strict;
use warnings;
use Bio::KBase::workspaceService;
use Exporter;
use parent qw(Exporter);
our @EXPORT_OK = qw( auth get_client workspace );
our $SERVICE_URL = "http://140.221.92.150:8080";

sub get_client {
    return Bio::KBase::workspaceService->new($SERVICE_URL);
}

sub auth {
    my $token = shift;
    my $filename = "$ENV{HOME}/.kbase_auth";
    if ( defined $token ) {
        open(my $fh, ">", $filename) || return;
        print $fh $token;
        close($fh);
    } elsif ( -e $filename ) {
        open(my $fh, "<", $filename) || return;
        $token = <$fh>;
        chomp($token);
        close($fh);
    }
    return $token;
}

sub workspace {
    my $set = shift;
    my $workspace;
    my $filename = "$ENV{HOME}/.kbase_workspace";
    if ( defined $set ) {
        open(my $fh, ">", $filename) || return;
        print $fh $set;
        close($fh);
        $workspace = $set;
    } elsif( -e $filename ) {
        open(my $fh, "<", $filename) || return;
        $workspace = <$fh>;
        chomp $workspace;
        close($fh);
    }
    return $workspace;
}

1;
