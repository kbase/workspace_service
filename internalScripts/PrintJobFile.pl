#!/usr/bin/perl -w

use strict;
use warnings;
use Config::Simple;
use Bio::KBase::workspaceService::Client;
use JSON -support_by_pp;
use File::Path;

$|=1;
my $config = $ARGV[0];
my $jobdir = $ARGV[1];
my $jobid = $ARGV[2];
my $overwrite = 0;
if (!defined($config)) {
	print STDERR "No config file provided!\n";
	exit(-1);
}
if (!-e $config) {
	print STDERR "Config file ".$config." not found!\n";
	exit(-1);
}
#Params: kbclientconfig.wsurl, kbclientconfig.fbaurl, kbclientconfig.auth
my $c = Config::Simple->new();
$c->read($config);
my $wss = Bio::KBase::workspaceService::Client->new($c->param("kbclientconfig.wsurl"));
my $jobs = $wss->get_jobs({
	jobids => [$jobid],
	auth => $c->param("kbclientconfig.auth")
});

my $JSON = JSON::XS->new();
my $data = $JSON->encode($jobs->[0]);
my $directory = $jobdir."/jobs/".$jobs->[0]->{id}."/";
if (!-d $directory) {
	mkdir $directory;
}
if (-e $directory."jobfile.json") {
	unlink $directory."jobfile.json";
}
if (-e $directory."pid") {
	unlink $directory."pid";
}
open(my $fh, ">", $directory."jobfile.json");
print $fh $data;
close($fh);

1;
