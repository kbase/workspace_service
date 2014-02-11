package Bio::KBase::workspaceService::Helpers;
use strict;
use warnings;
use Bio::KBase::Auth;
use Bio::KBase::workspaceService::Client;
use Exporter;
use parent qw(Exporter);
our @EXPORT_OK = qw( auth get_ws_client workspaceURL printJobData);
our $defaultURL = "http://kbase.us/services/workspace/";

my $CurrentWorkspace;
my $CurrentURL;

sub getKBaseCfg {
	my $kbConfPath = $Bio::KBase::Auth::ConfPath;
	if (!-e $kbConfPath) {
		my $newcfg = new Config::Simple(syntax=>'ini') or die Config::Simple->error();
		$newcfg->param("oldworkspace.url",$defaultURL);
		$newcfg->write($kbConfPath);
		$newcfg->close();
	}
	my $cfg = new Config::Simple(filename=>$kbConfPath) or die Config::Simple->error();
	return $cfg;
}

sub get_ws_client {
	my $url = shift;
	if (!defined($url)) {
		$url = workspaceURL();
	}
	if ($url eq "impl") {
		$Bio::KBase::workspaceService::Server::CallContext = {token => auth()};
		require "Bio/KBase/workspaceService/Impl.pm";
		return Bio::KBase::workspaceService::Impl->new();
	}
	my $client = Bio::KBase::workspaceService::Client->new($url);
	$client->{token} = auth();
	$client->{client}->{token} = auth();
    return $client;
}

sub auth {
	my $token='';
	my $kbConfPath = $Bio::KBase::Auth::ConfPath;
	if (defined($ENV{KB_RUNNING_IN_IRIS})) {
		$token = $ENV{KB_AUTH_TOKEN};
	} elsif ( -e $kbConfPath ) {
		my $cfg = new Config::Simple($kbConfPath);
		$token = $cfg->param("authentication.token");
		$cfg->close();
	}
	return $token;
}

sub workspaceURL {
	my $newUrl = shift;
	my $currentURL;
	if (defined($newUrl)) {
		if ($newUrl eq "default") {
			$newUrl = $defaultURL;
		} elsif ($newUrl eq "localhost") {
			$newUrl = "http://localhost:7035";
		}
		$currentURL = $newUrl;
		if (!defined($ENV{KB_RUNNING_IN_IRIS})) {
			my $cfg = getKBaseCfg();
			$cfg->param("oldworkspace.url",$newUrl);
			$cfg->save();
			$cfg->close();
		} elsif ($ENV{KB_OLDWORKSPACEURL}) {
			$ENV{KB_OLDWORKSPACEURL} = $currentURL;
		}
	} else {
		if (!defined($ENV{KB_RUNNING_IN_IRIS})) {
			my $cfg = getKBaseCfg();
			$currentURL = $cfg->param("oldworkspace.url");
			if (!defined($currentURL)) {
				$cfg->param("oldworkspace.url",$defaultURL);
				$cfg->save();
				$currentURL=$defaultURL;
			}
			$cfg->close();
		} else {
			$currentURL = $ENV{KB_OLDWORKSPACEURL};
		}
	}
	return $currentURL;
}

sub printJobData {
	my $job = shift;
	print "Job ID: ".$job->{id}."\n";
	print "Job Type: ".$job->{type}."\n";
	print "Job Owner: ".$job->{owner}."\n";
	print "Command: ".$job->{queuecommand}."\n";
	print "Queue time: ".$job->{queuetime}."\n";
	if (defined($job->{starttime})) {
		print "Start time: ".$job->{starttime}."\n";
	}
	if (defined($job->{completetime})) {
		print "Complete time: ".$job->{completetime}."\n";
	}
	print "Job Status: ".$job->{status}."\n";
	if (defined($job->{jobdata}->{postprocess_args}->[0]->{model_workspace})) {
		print "Model: ".$job->{jobdata}->{postprocess_args}->[0]->{model_workspace}."/".$job->{jobdata}->{postprocess_args}->[0]->{model}."\n";
	}
	if (defined($job->{jobdata}->{postprocess_args}->[0]->{formulation}->{formulation}->{media})) {
		print "Media: ".$job->{jobdata}->{postprocess_args}->[0]->{formulation}->{formulation}->{media}."\n";
	}
	if (defined($job->{jobdata}->{postprocess_args}->[0]->{formulation}->{media})) {
		print "Media: ".$job->{jobdata}->{postprocess_args}->[0]->{formulation}->{media}."\n";
	}
	if (defined($job->{jobdata}->{qsubid})) {
		print "Qsub ID: ".$job->{jobdata}->{qsubid}."\n";
	}
	if (defined($job->{jobdata}->{error})) {
		print "Error: ".$job->{jobdata}->{error}."\n";
	}
}

1;