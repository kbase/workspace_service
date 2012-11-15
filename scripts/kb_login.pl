#!/usr/bin/env perl 
# A simple script to log in and save the bearer token
# to $ENV{HOME}/.kbase_auth
use strict;
use warnings;
use Bio::KBase::AuthToken;
use Term::ReadKey;

my $usage    = "Usage: kb_login <username>";
my $username = shift @ARGV; 

sub get_pass {
    my $key  = 0;
    my $pass = ""; 
    print "Password: ";
    ReadMode(4);
    while ( ord($key = ReadKey(0)) != 10 ) {
        # While Enter has not been pressed
        if (ord($key) == 127 || ord($key) == 8) {
            chop $pass;
            print "\b \b";
        } elsif (ord($key) < 32) {
            # Do nothing with control chars
        } else {
            $pass .= $key;
            print "*";
        }
    }
    ReadMode(0);
    print "\n";
    return $pass;
}

unless (defined($username)) {
    print $usage;
    exit;
}

my $password = get_pass();
my $token = Bio::KBase::AuthToken->new(user_id => $username, password => $password);
if (!defined $token->token() || defined $token->error_message() ) {
    print $token->error_message;
    exit;
}
open(my $fh, ">", "$ENV{HOME}/.kbase_auth") || die "Unable to open file";
print $fh $token->token();
close($fh);
print "Logged in as " . $token->user_id . "\n";
