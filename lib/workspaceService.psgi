use Bio::KBase::workspaceService::Impl;

use Bio::KBase::workspaceService::Service;
use Plack::Middleware::CrossOrigin;



my @dispatch;

{
    my $obj = Bio::KBase::workspaceService::Impl->new;
    push(@dispatch, 'workspaceService' => $obj);
}


my $server = Bio::KBase::workspaceService::Service->new(instance_dispatch => { @dispatch },
				allow_get => 0,
			       );

my $handler = sub { $server->handle_input(@_) };

$handler = Plack::Middleware::CrossOrigin->wrap( $handler, origins => "*", headers => "*");
