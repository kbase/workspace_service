package Bio::KBase::workspaceService::Server;

use Data::Dumper;
use Moose;
use JSON;
use Bio::KBase::Log;
use Bio::KBase::AuthToken;

extends 'RPC::Any::Server::JSONRPC::PSGI';

has 'instance_dispatch' => (is => 'ro', isa => 'HashRef');
has 'user_auth' => (is => 'ro', isa => 'UserAuth');
has 'valid_methods' => (is => 'ro', isa => 'HashRef', lazy => 1,
			builder => '_build_valid_methods');
has 'loggers' => (is => 'ro', required => 1, builder => '_build_loggers');

our $CallContext;

our %return_counts = (
        'load_media_from_bio' => 1,
        'import_bio' => 1,
        'import_map' => 1,
        'save_object' => 1,
        'delete_object' => 1,
        'delete_object_permanently' => 1,
        'get_object' => 1,
        'get_objects' => 1,
        'get_object_by_ref' => 1,
        'save_object_by_ref' => 1,
        'get_objectmeta' => 1,
        'get_objectmeta_by_ref' => 1,
        'revert_object' => 1,
        'copy_object' => 1,
        'move_object' => 1,
        'has_object' => 1,
        'object_history' => 1,
        'create_workspace' => 1,
        'get_workspacemeta' => 1,
        'get_workspacepermissions' => 1,
        'delete_workspace' => 1,
        'clone_workspace' => 1,
        'list_workspaces' => 1,
        'list_workspace_objects' => 1,
        'set_global_workspace_permissions' => 1,
        'set_workspace_permissions' => 1,
        'get_user_settings' => 1,
        'set_user_settings' => 1,
        'queue_job' => 1,
        'set_job_status' => 1,
        'get_jobs' => 1,
        'get_types' => 1,
        'add_type' => 1,
        'remove_type' => 1,
        'patch' => 1,
        'version' => 1,
);

our %method_authentication = (
        'load_media_from_bio' => 'optional',
        'import_bio' => 'optional',
        'import_map' => 'optional',
        'save_object' => 'optional',
        'delete_object' => 'optional',
        'delete_object_permanently' => 'optional',
        'get_object' => 'optional',
        'get_objects' => 'optional',
        'get_object_by_ref' => 'optional',
        'save_object_by_ref' => 'optional',
        'get_objectmeta' => 'optional',
        'get_objectmeta_by_ref' => 'optional',
        'revert_object' => 'optional',
        'copy_object' => 'optional',
        'move_object' => 'optional',
        'has_object' => 'optional',
        'object_history' => 'optional',
        'create_workspace' => 'optional',
        'get_workspacemeta' => 'optional',
        'get_workspacepermissions' => 'optional',
        'delete_workspace' => 'optional',
        'clone_workspace' => 'optional',
        'list_workspaces' => 'optional',
        'list_workspace_objects' => 'optional',
        'set_global_workspace_permissions' => 'optional',
        'set_workspace_permissions' => 'optional',
        'get_user_settings' => 'optional',
        'set_user_settings' => 'optional',
        'queue_job' => 'optional',
        'set_job_status' => 'optional',
        'get_jobs' => 'optional',
        'get_types' => 'none',
        'add_type' => 'optional',
        'remove_type' => 'optional',
        'patch' => 'optional',
);


sub _build_valid_methods
{
    my($self) = @_;
    my $methods = {
        'load_media_from_bio' => 1,
        'import_bio' => 1,
        'import_map' => 1,
        'save_object' => 1,
        'delete_object' => 1,
        'delete_object_permanently' => 1,
        'get_object' => 1,
        'get_objects' => 1,
        'get_object_by_ref' => 1,
        'save_object_by_ref' => 1,
        'get_objectmeta' => 1,
        'get_objectmeta_by_ref' => 1,
        'revert_object' => 1,
        'copy_object' => 1,
        'move_object' => 1,
        'has_object' => 1,
        'object_history' => 1,
        'create_workspace' => 1,
        'get_workspacemeta' => 1,
        'get_workspacepermissions' => 1,
        'delete_workspace' => 1,
        'clone_workspace' => 1,
        'list_workspaces' => 1,
        'list_workspace_objects' => 1,
        'set_global_workspace_permissions' => 1,
        'set_workspace_permissions' => 1,
        'get_user_settings' => 1,
        'set_user_settings' => 1,
        'queue_job' => 1,
        'set_job_status' => 1,
        'get_jobs' => 1,
        'get_types' => 1,
        'add_type' => 1,
        'remove_type' => 1,
        'patch' => 1,
        'version' => 1,
    };
    return $methods;
}

my $DEPLOY = 'KB_DEPLOYMENT_CONFIG';
my $SERVICE = 'KB_SERVICE_NAME';

sub get_config_file
{
    my ($self) = @_;
    if(!defined $ENV{$DEPLOY}) {
        return undef;
    }
    return $ENV{$DEPLOY};
}

sub get_service_name
{
    my ($self) = @_;
    if(!defined $ENV{$SERVICE}) {
        return undef;
    }
    return $ENV{$SERVICE};
}

sub logcallback
{
    my ($self) = @_;
    $self->loggers()->{serverlog}->set_log_file(
        $self->{loggers}->{userlog}->get_log_file());
}

sub log
{
    my ($self, $level, $context, $message) = @_;
    my $user = defined($context->user_id()) ? $context->user_id(): undef; 
    $self->loggers()->{serverlog}->log_message($level, $message, $user, 
        $context->module(), $context->method(), $context->call_id(),
        $context->client_ip());
}

sub _build_loggers
{
    my ($self) = @_;
    my $submod = $self->get_service_name() || 'workspaceService';
    my $loggers = {};
    my $callback = sub {$self->logcallback();};
    $loggers->{userlog} = Bio::KBase::Log->new(
            $submod, {}, {ip_address => 1, authuser => 1, module => 1,
            method => 1, call_id => 1, changecallback => $callback,
            config => $self->get_config_file()});
    $loggers->{serverlog} = Bio::KBase::Log->new(
            $submod, {}, {ip_address => 1, authuser => 1, module => 1,
            method => 1, call_id => 1,
            logfile => $loggers->{userlog}->get_log_file()});
    $loggers->{serverlog}->set_log_level(6);
    return $loggers;
}

#override of RPC::Any::Server
sub handle_error {
    my ($self, $error) = @_;
    
    unless (ref($error) eq 'HASH' ||
           (blessed $error and $error->isa('RPC::Any::Exception'))) {
        $error = RPC::Any::Exception::PerlError->new(message => $error);
    }
    my $output;
    eval {
        my $encoded_error = $self->encode_output_from_exception($error);
        $output = $self->produce_output($encoded_error);
    };
    
    return $output if $output;
    
    die "$error\n\nAlso, an error was encountered while trying to send"
        . " this error: $@\n";
}

#override of RPC::Any::JSONRPC
sub encode_output_from_exception {
    my ($self, $exception) = @_;
    my %error_params;
    if (ref($exception) eq 'HASH') {
        %error_params = %{$exception};
        if(defined($error_params{context})) {
            my @errlines;
            $errlines[0] = $error_params{message};
            push @errlines, split("\n", $error_params{data});
            $self->log($Bio::KBase::Log::ERR, $error_params{context}, \@errlines);
            delete $error_params{context};
        }
    } else {
        %error_params = (
            message => $exception->message,
            code    => $exception->code,
        );
    }
    my $json_error;
    if ($self->_last_call) {
        $json_error = $self->_last_call->return_error(%error_params);
    }
    # Default to default_version. This happens when we throw an exception
    # before inbound parsing is complete.
    else {
        $json_error = $self->_default_error(%error_params);
    }
    return $self->encode_output_from_object($json_error);
}

sub call_method {
    my ($self, $data, $method_info) = @_;

    my ($module, $method, $modname) = @$method_info{qw(module method modname)};
    
    my $ctx = Bio::KBase::workspaceService::ServerContext->new($self->{loggers}->{userlog},
                           client_ip => $self->_plack_req->address);
    $ctx->module($modname);
    $ctx->method($method);
    $ctx->call_id($self->{_last_call}->{id});
    
    my $args = $data->{arguments};

{
    # Service workspaceService requires authentication.

    my $method_auth = $method_authentication{$method};
    $ctx->authenticated(0);
    if ($method_auth eq 'none')
    {
	# No authentication required here. Move along.
    }
    else
    {
	my $token = $self->_plack_req->header("Authorization");

	if (!$token && $method_auth eq 'required')
	{
	    $self->exception('PerlError', "Authentication required for workspaceService but no authentication header was passed");
	}

	my $auth_token = Bio::KBase::AuthToken->new(token => $token, ignore_authrc => 1);
	my $valid = $auth_token->validate();
	# Only throw an exception if authentication was required and it fails
	if ($method_auth eq 'required' && !$valid)
	{
	    $self->exception('PerlError', "Token validation failed: " . $auth_token->error_message);
	} elsif ($valid) {
	    $ctx->authenticated(1);
	    $ctx->user_id($auth_token->user_id);
	    $ctx->token( $token);
	}
    }
}
    my $new_isa = $self->get_package_isa($module);
    no strict 'refs';
    local @{"${module}::ISA"} = @$new_isa;
    local $CallContext = $ctx;
    my @result;
    {
        my $err;
        eval {
            $self->log($Bio::KBase::Log::INFO, $ctx, "start method");
            @result = $module->$method(@{ $data->{arguments} });
            $self->log($Bio::KBase::Log::INFO, $ctx, "end method");
        };
        if ($@)
        {
            my $err = $@;
            my $nicerr;
            if(ref($err) eq "Bio::KBase::Exceptions::KBaseException") {
                $nicerr = {code => -32603, # perl error from RPC::Any::Exception
                           message => $err->error,
                           data => $err->trace->as_string,
                           context => $ctx
                           };
            } else {
                my $str = "$err";
                $str =~ s/Bio::KBase::CDMI::Service::call_method.*//s; # is this still necessary? not sure
                my $msg = $str;
                $msg =~ s/ at [^\s]+.pm line \d+.\n$//;
                $nicerr =  {code => -32603, # perl error from RPC::Any::Exception
                            message => $msg,
                            data => $str,
                            context => $ctx
                            };
            }
            die $nicerr;
        }
    }
    my $result;
    if ($return_counts{$method} == 1)
    {
        $result = [[$result[0]]];
    }
    else
    {
        $result = \@result;
    }
    return $result;
}


sub get_method
{
    my ($self, $data) = @_;
    
    my $full_name = $data->{method};
    
    $full_name =~ /^(\S+)\.([^\.]+)$/;
    my ($package, $method) = ($1, $2);
    
    if (!$package || !$method) {
	$self->exception('NoSuchMethod',
			 "'$full_name' is not a valid method. It must"
			 . " contain a package name, followed by a period,"
			 . " followed by a method name.");
    }

    if (!$self->valid_methods->{$method})
    {
	$self->exception('NoSuchMethod',
			 "'$method' is not a valid method in service workspaceService.");
    }
	
    my $inst = $self->instance_dispatch->{$package};
    my $module;
    if ($inst)
    {
	$module = $inst;
    }
    else
    {
	$module = $self->get_module($package);
	if (!$module) {
	    $self->exception('NoSuchMethod',
			     "There is no method package named '$package'.");
	}
	
	Class::MOP::load_class($module);
    }
    
    if (!$module->can($method)) {
	$self->exception('NoSuchMethod',
			 "There is no method named '$method' in the"
			 . " '$package' package.");
    }
    
    return { module => $module, method => $method, modname => $package };
}

package Bio::KBase::workspaceService::ServerContext;

use strict;

=head1 NAME

Bio::KBase::workspaceService::ServerContext

head1 DESCRIPTION

A KB RPC context contains information about the invoker of this
service. If it is an authenticated service the authenticated user
record is available via $context->user. The client IP address
is available via $context->client_ip.

=cut

use base 'Class::Accessor';

__PACKAGE__->mk_accessors(qw(user_id client_ip authenticated token
                             module method call_id));

sub new
{
    my($class, $logger, %opts) = @_;
    
    my $self = {
        %opts,
    };
    $self->{_logger} = $logger;
    $self->{_debug_levels} = {7 => 1, 8 => 1, 9 => 1,
                              'DEBUG' => 1, 'DEBUG2' => 1, 'DEBUG3' => 1};
    return bless $self, $class;
}

sub _get_user
{
    my ($self) = @_;
    return defined($self->user_id()) ? $self->user_id(): undef; 
}

sub _log
{
    my ($self, $level, $message) = @_;
    $self->{_logger}->log_message($level, $message, $self->_get_user(),
        $self->module(), $self->method(), $self->call_id(),
        $self->client_ip());
}

sub log_err
{
    my ($self, $message) = @_;
    $self->_log($Bio::KBase::Log::ERR, $message);
}

sub log_info
{
    my ($self, $message) = @_;
    $self->_log($Bio::KBase::Log::INFO, $message);
}

sub log_debug
{
    my ($self, $message, $level) = @_;
    if(!defined($level)) {
        $level = 1;
    }
    if($self->{_debug_levels}->{$level}) {
    } else {
        if ($level =~ /\D/ || $level < 1 || $level > 3) {
            die "Invalid log level: $level";
        }
        $level += 6;
    }
    $self->_log($level, $message);
}

sub set_log_level
{
    my ($self, $level) = @_;
    $self->{_logger}->set_log_level($level);
}

sub get_log_level
{
    my ($self) = @_;
    return $self->{_logger}->get_log_level();
}

sub clear_log_level
{
    my ($self) = @_;
    $self->{_logger}->clear_user_log_level();
}

1;
