use Bio::KBase::workspaceService::Impl;

use Bio::KBase::workspaceService::Service;



my @dispatch;

{
    my $obj = Bio::KBase::workspaceService::Impl->new;
    push(@dispatch, 'workspaceService' => $obj);
}


my $server = Bio::KBase::workspaceService::Service->new(instance_dispatch => { @dispatch },
				allow_get => 0,
			       );

my $handler = sub { $server->handle_input(@_) };

$handler;
