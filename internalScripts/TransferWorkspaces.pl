#!/usr/bin/perl -w

use strict;
use Config::Simple;
use JSON::XS;
use Bio::KBase::workspace::Client;

my $directory = $ARGV[0];
my $conffile = $ARGV[1];
if (!defined($conffile)) {
	$conffile = "~/.kbase_config";
}
if (!-e $conffile) {
	print STDERR "Config file ".$conffile." not found!\n";
	exit(-1);
}

my $c = Config::Simple->new();
$c->read($conffile);

my $wsderv = Bio::KBase::workspace::Client->new($c->param("workspace_deluxe.wsdurl"),$c->param("authentication.token"));

open( my $fh, "<", $directory."workspaces.list");
my $workspaces;
{
    local $/;
    my $str = <$fh>;
    $workspaces = decode_json $str;
}
close($fh);

foreach my $workspace (@{$workspaces}) {
	eval {
		$wsderv->administer({"command" => "createWorkspace", "user" => $workspace->{owner}, "params" => {"workspace" => $workspace->{id}, 'globalread' => $workspace->{defaultPermissions}}});
		print "Success:".$workspace->{owner}.":".$workspace->{id}.":".$workspace->{defaultPermissions}."\n";
	}; print "Failed:".$workspace->{owner}.":".$workspace->{id}.":".$workspace->{defaultPermissions}."\n" if $@;
}

1;
