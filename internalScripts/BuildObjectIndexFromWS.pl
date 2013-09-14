#!/usr/bin/perl -w

use strict;
use warnings;
use Config::Simple;
use Bio::KBase::workspaceService::Client;
use Bio::KBase::fbaModelServices::Impl;

$|=1;
my $config = $ARGV[0];
my $filename = $ARGV[1];
my $overwrite = 0;
if (!defined($config)) {
	print STDERR "No config file provided!\n";
	exit(-1);
}
if (!-e $config) {
	print STDERR "Config file ".$config." not found!\n";
	exit(-1);
}
#Params: writesbml.wsurl, writesbml.fbaurl, writesbml.auth
my $c = Config::Simple->new();
$c->read($config);
my $wss = Bio::KBase::workspaceService::Client->new($c->param("kbclientconfig.wsurl"));

my $typeCount = {};
open(my $fh, ">".$filename); 
print $fh "ID\tWorkspace\tType\tInstance\tRef\tCommand\tModdate\tOwner\n";
my $workspace_list = $wss->list_workspaces({auth => $c->param("kbclientconfig.auth")});
foreach my $workspace (@{$workspace_list}) {
	my $wsid = $workspace->[0];
	my $object_list = $wss->list_workspace_objects({auth => $c->param("kbclientconfig.auth")});
	foreach my $object (@{$object_list}) {
		if (!defined($typeCount->{$object->[1]})) {
			$typeCount->{$object->[1]} = 0;
		}
		$typeCount->{$object->[1]}++;
		print $fh $object->[0]."\t".$wsid."\t".$object->[1]."\t".$object->[3]."\t".$object->[8]."\t".$object->[4]."\t".$object->[2]."\t".$object->[6]."\n";
	}
}
close($fh);

print "Type\tCount\n";
foreach my $type (keys(%{$typeCount})) {
	print $type."\t".$typeCount->{$type}."\n";
}

1;
