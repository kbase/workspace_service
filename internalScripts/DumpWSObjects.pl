#!/usr/bin/perl -w

use strict;
use warnings;
use Config::Simple;
use Bio::KBase::workspaceService::Client;
use Bio::KBase::fbaModelServices::Impl;
use JSON -support_by_pp;
use File::Path;

$|=1;
my $config = $ARGV[0];
my $filename = $ARGV[1];
my $directory = $ARGV[2];
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

my $types = {
	Genome => 1,
	PhenotypeSimulationSet => 1,
	PhenotypeSet => 1,
	ProbAnno => 1
};
open(my $fh, "<".$filename);
my $line = <$fh>;
while ($line = <$fh>) {
	my $array = [split(/\t/,$line)];
	if (defined($types->{$array->[2]})) {
		print $array->[2]."/".$array->[1]."/".$array->[0]."\n";
		my $output;
		while(!defined($output)) {
			eval {
				$output = $wss->get_object({
					id => $array->[0],
					type => $array->[2],
					workspace => $array->[1],
					auth => $c->param("kbclientconfig.auth")
				});
			};
		}
		my $data = $output->{data};
		delete($data->{_wsWS});
		delete($data->{contigs_uuid});
		delete($data->{_wsType});
		delete($data->{_wsID});
		delete($data->{_wsUUID});
		delete($data->{contigs});
		my $path = $directory."/".$array->[1]."/".$array->[2]."/";
		File::Path::mkpath ($path);
		open(my $fho, ">".$path.$array->[0]);
		print $fho $array->[2]."/".$array->[1]."/".$array->[0]."\n";
		print $fho to_json( $data, { utf8 => 1, pretty => 0 } )."\n";
		close($fho);
	}
}
close ($fh);

1;
