package Bio::KBase::workspaceService::Client;

use JSON::RPC::Client;
use strict;
use Data::Dumper;
use URI;
use Bio::KBase::Exceptions;

# Client version should match Impl version
# This is a Semantic Version number,
# http://semver.org
our $VERSION = "0.1.0";

=head1 NAME

Bio::KBase::workspaceService::Client

=head1 DESCRIPTION


=head1 workspaceService

API for accessing and writing documents objects to a workspace.


=cut

sub new
{
    my($class, $url, @args) = @_;

    my $self = {
	client => Bio::KBase::workspaceService::Client::RpcClient->new,
	url => $url,
    };


    my $ua = $self->{client}->ua;	 
    my $timeout = $ENV{CDMI_TIMEOUT} || (30 * 60);	 
    $ua->timeout($timeout);
    bless $self, $class;
    #    $self->_validate_version();
    return $self;
}




=head2 save_object

  $metadata = $obj->save_object($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a save_object_params
$metadata is an object_metadata
save_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	data has a value which is an ObjectData
	workspace has a value which is a workspace_id
	command has a value which is a string
	metadata has a value which is a reference to a hash where the key is a string and the value is a string
	auth has a value which is a string
	json has a value which is a bool
	compressed has a value which is a bool
	retrieveFromURL has a value which is a bool
object_id is a string
object_type is a string
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a save_object_params
$metadata is an object_metadata
save_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	data has a value which is an ObjectData
	workspace has a value which is a workspace_id
	command has a value which is a string
	metadata has a value which is a reference to a hash where the key is a string and the value is a string
	auth has a value which is a string
	json has a value which is a bool
	compressed has a value which is a bool
	retrieveFromURL has a value which is a bool
object_id is a string
object_type is a string
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text

=item Description



=back

=cut

sub save_object
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function save_object (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to save_object:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'save_object');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.save_object",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'save_object',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method save_object",
					    status_line => $self->{client}->status_line,
					    method_name => 'save_object',
				       );
    }
}



=head2 delete_object

  $metadata = $obj->delete_object($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a delete_object_params
$metadata is an object_metadata
delete_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a delete_object_params
$metadata is an object_metadata
delete_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text

=item Description



=back

=cut

sub delete_object
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function delete_object (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to delete_object:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'delete_object');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.delete_object",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'delete_object',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method delete_object",
					    status_line => $self->{client}->status_line,
					    method_name => 'delete_object',
				       );
    }
}



=head2 delete_object_permanently

  $metadata = $obj->delete_object_permanently($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a delete_object_permanently_params
$metadata is an object_metadata
delete_object_permanently_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a delete_object_permanently_params
$metadata is an object_metadata
delete_object_permanently_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text

=item Description



=back

=cut

sub delete_object_permanently
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function delete_object_permanently (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to delete_object_permanently:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'delete_object_permanently');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.delete_object_permanently",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'delete_object_permanently',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method delete_object_permanently",
					    status_line => $self->{client}->status_line,
					    method_name => 'delete_object_permanently',
				       );
    }
}



=head2 get_object

  $output = $obj->get_object($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_object_params
$output is a get_object_output
get_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	instance has a value which is an int
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
get_object_output is a reference to a hash where the following keys are defined:
	data has a value which is an ObjectData
	metadata has a value which is an object_metadata
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a get_object_params
$output is a get_object_output
get_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	instance has a value which is an int
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
get_object_output is a reference to a hash where the following keys are defined:
	data has a value which is an ObjectData
	metadata has a value which is an object_metadata
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text

=item Description



=back

=cut

sub get_object
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function get_object (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to get_object:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'get_object');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.get_object",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'get_object',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method get_object",
					    status_line => $self->{client}->status_line,
					    method_name => 'get_object',
				       );
    }
}



=head2 get_objectmeta

  $metadata = $obj->get_objectmeta($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_objectmeta_params
$metadata is an object_metadata
get_objectmeta_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	instance has a value which is an int
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a get_objectmeta_params
$metadata is an object_metadata
get_objectmeta_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	instance has a value which is an int
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text

=item Description



=back

=cut

sub get_objectmeta
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function get_objectmeta (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to get_objectmeta:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'get_objectmeta');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.get_objectmeta",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'get_objectmeta',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method get_objectmeta",
					    status_line => $self->{client}->status_line,
					    method_name => 'get_objectmeta',
				       );
    }
}



=head2 revert_object

  $metadata = $obj->revert_object($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a revert_object_params
$metadata is an object_metadata
revert_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	instance has a value which is an int
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a revert_object_params
$metadata is an object_metadata
revert_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	instance has a value which is an int
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text

=item Description



=back

=cut

sub revert_object
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function revert_object (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to revert_object:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'revert_object');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.revert_object",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'revert_object',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method revert_object",
					    status_line => $self->{client}->status_line,
					    method_name => 'revert_object',
				       );
    }
}



=head2 copy_object

  $metadata = $obj->copy_object($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a copy_object_params
$metadata is an object_metadata
copy_object_params is a reference to a hash where the following keys are defined:
	new_id has a value which is an object_id
	new_workspace has a value which is a workspace_id
	source_id has a value which is an object_id
	instance has a value which is an int
	type has a value which is an object_type
	source_workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
workspace_id is a string
object_type is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a copy_object_params
$metadata is an object_metadata
copy_object_params is a reference to a hash where the following keys are defined:
	new_id has a value which is an object_id
	new_workspace has a value which is a workspace_id
	source_id has a value which is an object_id
	instance has a value which is an int
	type has a value which is an object_type
	source_workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
workspace_id is a string
object_type is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text

=item Description



=back

=cut

sub copy_object
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function copy_object (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to copy_object:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'copy_object');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.copy_object",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'copy_object',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method copy_object",
					    status_line => $self->{client}->status_line,
					    method_name => 'copy_object',
				       );
    }
}



=head2 move_object

  $metadata = $obj->move_object($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a move_object_params
$metadata is an object_metadata
move_object_params is a reference to a hash where the following keys are defined:
	new_id has a value which is an object_id
	new_workspace has a value which is a workspace_id
	source_id has a value which is an object_id
	type has a value which is an object_type
	source_workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
workspace_id is a string
object_type is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a move_object_params
$metadata is an object_metadata
move_object_params is a reference to a hash where the following keys are defined:
	new_id has a value which is an object_id
	new_workspace has a value which is a workspace_id
	source_id has a value which is an object_id
	type has a value which is an object_type
	source_workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
workspace_id is a string
object_type is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text

=item Description



=back

=cut

sub move_object
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function move_object (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to move_object:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'move_object');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.move_object",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'move_object',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method move_object",
					    status_line => $self->{client}->status_line,
					    method_name => 'move_object',
				       );
    }
}



=head2 has_object

  $object_present = $obj->has_object($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a has_object_params
$object_present is a bool
has_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	instance has a value which is an int
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
bool is an int

</pre>

=end html

=begin text

$params is a has_object_params
$object_present is a bool
has_object_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	instance has a value which is an int
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
bool is an int


=end text

=item Description



=back

=cut

sub has_object
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function has_object (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to has_object:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'has_object');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.has_object",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'has_object',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method has_object",
					    status_line => $self->{client}->status_line,
					    method_name => 'has_object',
				       );
    }
}



=head2 object_history

  $metadatas = $obj->object_history($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is an object_history_params
$metadatas is a reference to a list where each element is an object_metadata
object_history_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is an object_history_params
$metadatas is a reference to a list where each element is an object_metadata
object_history_params is a reference to a hash where the following keys are defined:
	id has a value which is an object_id
	type has a value which is an object_type
	workspace has a value which is a workspace_id
	auth has a value which is a string
object_id is a string
object_type is a string
workspace_id is a string
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
timestamp is a string
username is a string
workspace_ref is a string


=end text

=item Description



=back

=cut

sub object_history
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function object_history (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to object_history:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'object_history');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.object_history",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'object_history',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method object_history",
					    status_line => $self->{client}->status_line,
					    method_name => 'object_history',
				       );
    }
}



=head2 create_workspace

  $metadata = $obj->create_workspace($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a create_workspace_params
$metadata is a workspace_metadata
create_workspace_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	default_permission has a value which is a permission
	auth has a value which is a string
workspace_id is a string
permission is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string

</pre>

=end html

=begin text

$params is a create_workspace_params
$metadata is a workspace_metadata
create_workspace_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	default_permission has a value which is a permission
	auth has a value which is a string
workspace_id is a string
permission is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string


=end text

=item Description



=back

=cut

sub create_workspace
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function create_workspace (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to create_workspace:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'create_workspace');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.create_workspace",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'create_workspace',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method create_workspace",
					    status_line => $self->{client}->status_line,
					    method_name => 'create_workspace',
				       );
    }
}



=head2 get_workspacemeta

  $metadata = $obj->get_workspacemeta($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_workspacemeta_params
$metadata is a workspace_metadata
get_workspacemeta_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	auth has a value which is a string
workspace_id is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string
permission is a string

</pre>

=end html

=begin text

$params is a get_workspacemeta_params
$metadata is a workspace_metadata
get_workspacemeta_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	auth has a value which is a string
workspace_id is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string
permission is a string


=end text

=item Description



=back

=cut

sub get_workspacemeta
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function get_workspacemeta (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to get_workspacemeta:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'get_workspacemeta');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.get_workspacemeta",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'get_workspacemeta',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method get_workspacemeta",
					    status_line => $self->{client}->status_line,
					    method_name => 'get_workspacemeta',
				       );
    }
}



=head2 get_workspacepermissions

  $user_permissions = $obj->get_workspacepermissions($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_workspacepermissions_params
$user_permissions is a reference to a hash where the key is a username and the value is a permission
get_workspacepermissions_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	auth has a value which is a string
workspace_id is a string
username is a string
permission is a string

</pre>

=end html

=begin text

$params is a get_workspacepermissions_params
$user_permissions is a reference to a hash where the key is a username and the value is a permission
get_workspacepermissions_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	auth has a value which is a string
workspace_id is a string
username is a string
permission is a string


=end text

=item Description



=back

=cut

sub get_workspacepermissions
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function get_workspacepermissions (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to get_workspacepermissions:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'get_workspacepermissions');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.get_workspacepermissions",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'get_workspacepermissions',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method get_workspacepermissions",
					    status_line => $self->{client}->status_line,
					    method_name => 'get_workspacepermissions',
				       );
    }
}



=head2 delete_workspace

  $metadata = $obj->delete_workspace($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a delete_workspace_params
$metadata is a workspace_metadata
delete_workspace_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	auth has a value which is a string
workspace_id is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string
permission is a string

</pre>

=end html

=begin text

$params is a delete_workspace_params
$metadata is a workspace_metadata
delete_workspace_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	auth has a value which is a string
workspace_id is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string
permission is a string


=end text

=item Description



=back

=cut

sub delete_workspace
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function delete_workspace (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to delete_workspace:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'delete_workspace');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.delete_workspace",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'delete_workspace',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method delete_workspace",
					    status_line => $self->{client}->status_line,
					    method_name => 'delete_workspace',
				       );
    }
}



=head2 clone_workspace

  $metadata = $obj->clone_workspace($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a clone_workspace_params
$metadata is a workspace_metadata
clone_workspace_params is a reference to a hash where the following keys are defined:
	new_workspace has a value which is a workspace_id
	current_workspace has a value which is a workspace_id
	default_permission has a value which is a permission
	auth has a value which is a string
workspace_id is a string
permission is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string

</pre>

=end html

=begin text

$params is a clone_workspace_params
$metadata is a workspace_metadata
clone_workspace_params is a reference to a hash where the following keys are defined:
	new_workspace has a value which is a workspace_id
	current_workspace has a value which is a workspace_id
	default_permission has a value which is a permission
	auth has a value which is a string
workspace_id is a string
permission is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string


=end text

=item Description



=back

=cut

sub clone_workspace
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function clone_workspace (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to clone_workspace:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'clone_workspace');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.clone_workspace",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'clone_workspace',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method clone_workspace",
					    status_line => $self->{client}->status_line,
					    method_name => 'clone_workspace',
				       );
    }
}



=head2 list_workspaces

  $workspaces = $obj->list_workspaces($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a list_workspaces_params
$workspaces is a reference to a list where each element is a workspace_metadata
list_workspaces_params is a reference to a hash where the following keys are defined:
	auth has a value which is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
workspace_id is a string
username is a string
timestamp is a string
permission is a string

</pre>

=end html

=begin text

$params is a list_workspaces_params
$workspaces is a reference to a list where each element is a workspace_metadata
list_workspaces_params is a reference to a hash where the following keys are defined:
	auth has a value which is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
workspace_id is a string
username is a string
timestamp is a string
permission is a string


=end text

=item Description



=back

=cut

sub list_workspaces
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function list_workspaces (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to list_workspaces:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'list_workspaces');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.list_workspaces",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'list_workspaces',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method list_workspaces",
					    status_line => $self->{client}->status_line,
					    method_name => 'list_workspaces',
				       );
    }
}



=head2 list_workspace_objects

  $objects = $obj->list_workspace_objects($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a list_workspace_objects_params
$objects is a reference to a list where each element is an object_metadata
list_workspace_objects_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	type has a value which is a string
	showDeletedObject has a value which is a bool
	auth has a value which is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
object_id is a string
object_type is a string
timestamp is a string
username is a string
workspace_ref is a string

</pre>

=end html

=begin text

$params is a list_workspace_objects_params
$objects is a reference to a list where each element is an object_metadata
list_workspace_objects_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a workspace_id
	type has a value which is a string
	showDeletedObject has a value which is a bool
	auth has a value which is a string
workspace_id is a string
bool is an int
object_metadata is a reference to a list containing 9 items:
	0: an object_id
	1: an object_type
	2: a timestamp
	3: an int
	4: a string
	5: a username
	6: a username
	7: a workspace_id
	8: a workspace_ref
object_id is a string
object_type is a string
timestamp is a string
username is a string
workspace_ref is a string


=end text

=item Description



=back

=cut

sub list_workspace_objects
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function list_workspace_objects (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to list_workspace_objects:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'list_workspace_objects');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.list_workspace_objects",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'list_workspace_objects',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method list_workspace_objects",
					    status_line => $self->{client}->status_line,
					    method_name => 'list_workspace_objects',
				       );
    }
}



=head2 set_global_workspace_permissions

  $metadata = $obj->set_global_workspace_permissions($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a set_global_workspace_permissions_params
$metadata is a workspace_metadata
set_global_workspace_permissions_params is a reference to a hash where the following keys are defined:
	new_permission has a value which is a permission
	workspace has a value which is a workspace_id
	auth has a value which is a string
permission is a string
workspace_id is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string

</pre>

=end html

=begin text

$params is a set_global_workspace_permissions_params
$metadata is a workspace_metadata
set_global_workspace_permissions_params is a reference to a hash where the following keys are defined:
	new_permission has a value which is a permission
	workspace has a value which is a workspace_id
	auth has a value which is a string
permission is a string
workspace_id is a string
workspace_metadata is a reference to a list containing 6 items:
	0: a workspace_id
	1: a username
	2: a timestamp
	3: an int
	4: a permission
	5: a permission
username is a string
timestamp is a string


=end text

=item Description



=back

=cut

sub set_global_workspace_permissions
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function set_global_workspace_permissions (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to set_global_workspace_permissions:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'set_global_workspace_permissions');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.set_global_workspace_permissions",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'set_global_workspace_permissions',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method set_global_workspace_permissions",
					    status_line => $self->{client}->status_line,
					    method_name => 'set_global_workspace_permissions',
				       );
    }
}



=head2 set_workspace_permissions

  $success = $obj->set_workspace_permissions($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a set_workspace_permissions_params
$success is a bool
set_workspace_permissions_params is a reference to a hash where the following keys are defined:
	users has a value which is a reference to a list where each element is a username
	new_permission has a value which is a permission
	workspace has a value which is a workspace_id
	auth has a value which is a string
username is a string
permission is a string
workspace_id is a string
bool is an int

</pre>

=end html

=begin text

$params is a set_workspace_permissions_params
$success is a bool
set_workspace_permissions_params is a reference to a hash where the following keys are defined:
	users has a value which is a reference to a list where each element is a username
	new_permission has a value which is a permission
	workspace has a value which is a workspace_id
	auth has a value which is a string
username is a string
permission is a string
workspace_id is a string
bool is an int


=end text

=item Description



=back

=cut

sub set_workspace_permissions
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function set_workspace_permissions (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to set_workspace_permissions:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'set_workspace_permissions');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.set_workspace_permissions",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'set_workspace_permissions',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method set_workspace_permissions",
					    status_line => $self->{client}->status_line,
					    method_name => 'set_workspace_permissions',
				       );
    }
}



=head2 queue_job

  $success = $obj->queue_job($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a queue_job_params
$success is a bool
queue_job_params is a reference to a hash where the following keys are defined:
	jobid has a value which is a string
	jobws has a value which is a string
	auth has a value which is a string
bool is an int

</pre>

=end html

=begin text

$params is a queue_job_params
$success is a bool
queue_job_params is a reference to a hash where the following keys are defined:
	jobid has a value which is a string
	jobws has a value which is a string
	auth has a value which is a string
bool is an int


=end text

=item Description



=back

=cut

sub queue_job
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function queue_job (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to queue_job:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'queue_job');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.queue_job",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'queue_job',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method queue_job",
					    status_line => $self->{client}->status_line,
					    method_name => 'queue_job',
				       );
    }
}



=head2 set_job_status

  $success = $obj->set_job_status($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a set_job_status_params
$success is a bool
set_job_status_params is a reference to a hash where the following keys are defined:
	jobid has a value which is a string
	jobws has a value which is a string
	status has a value which is a string
	auth has a value which is a string
bool is an int

</pre>

=end html

=begin text

$params is a set_job_status_params
$success is a bool
set_job_status_params is a reference to a hash where the following keys are defined:
	jobid has a value which is a string
	jobws has a value which is a string
	status has a value which is a string
	auth has a value which is a string
bool is an int


=end text

=item Description



=back

=cut

sub set_job_status
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function set_job_status (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to set_job_status:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'set_job_status');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.set_job_status",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'set_job_status',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method set_job_status",
					    status_line => $self->{client}->status_line,
					    method_name => 'set_job_status',
				       );
    }
}



=head2 get_jobs

  $jobs = $obj->get_jobs($params)

=over 4

=item Parameter and return types

=begin html

<pre>
$params is a get_jobs_params
$jobs is a reference to a list where each element is an ObjectData
get_jobs_params is a reference to a hash where the following keys are defined:
	status has a value which is a string
	auth has a value which is a string
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int

</pre>

=end html

=begin text

$params is a get_jobs_params
$jobs is a reference to a list where each element is an ObjectData
get_jobs_params is a reference to a hash where the following keys are defined:
	status has a value which is a string
	auth has a value which is a string
ObjectData is a reference to a hash where the following keys are defined:
	version has a value which is an int


=end text

=item Description



=back

=cut

sub get_jobs
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function get_jobs (received $n, expecting 1)");
    }
    {
	my($params) = @args;

	my @_bad_arguments;
        (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"params\" (value was \"$params\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to get_jobs:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'get_jobs');
	}
    }

    my $result = $self->{client}->call($self->{url}, {
	method => "workspaceService.get_jobs",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{code},
					       method_name => 'get_jobs',
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method get_jobs",
					    status_line => $self->{client}->status_line,
					    method_name => 'get_jobs',
				       );
    }
}



sub version {
    my ($self) = @_;
    my $result = $self->{client}->call($self->{url}, {
        method => "workspaceService.version",
        params => [],
    });
    if ($result) {
        if ($result->is_error) {
            Bio::KBase::Exceptions::JSONRPC->throw(
                error => $result->error_message,
                code => $result->content->{code},
                method_name => 'get_jobs',
            );
        } else {
            return wantarray ? @{$result->result} : $result->result->[0];
        }
    } else {
        Bio::KBase::Exceptions::HTTP->throw(
            error => "Error invoking method get_jobs",
            status_line => $self->{client}->status_line,
            method_name => 'get_jobs',
        );
    }
}

sub _validate_version {
    my ($self) = @_;
    my $svr_version = $self->version();
    my $client_version = $VERSION;
    my ($cMajor, $cMinor) = split(/\./, $client_version);
    my ($sMajor, $sMinor) = split(/\./, $svr_version);
    if ($sMajor != $cMajor) {
        Bio::KBase::Exceptions::ClientServerIncompatible->throw(
            error => "Major version numbers differ.",
            server_version => $svr_version,
            client_version => $client_version
        );
    }
    if ($sMinor < $cMinor) {
        Bio::KBase::Exceptions::ClientServerIncompatible->throw(
            error => "Client minor version greater than Server minor version.",
            server_version => $svr_version,
            client_version => $client_version
        );
    }
    if ($sMinor > $cMinor) {
        warn "New client version available for Bio::KBase::workspaceService::Client\n";
    }
    if ($sMajor == 0) {
        warn "Bio::KBase::workspaceService::Client version is $svr_version. API subject to change.\n";
    }
}

=head1 TYPES



=head2 bool

=over 4



=item Definition

=begin html

<pre>
an int
</pre>

=end html

=begin text

an int

=end text

=back



=head2 workspace_id

=over 4



=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 object_type

=over 4



=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 object_id

=over 4



=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 permission

=over 4



=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 username

=over 4



=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 timestamp

=over 4



=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 workspace_ref

=over 4



=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 ObjectData

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
version has a value which is an int

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
version has a value which is an int


=end text

=back



=head2 WorkspaceData

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
version has a value which is an int

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
version has a value which is an int


=end text

=back



=head2 object_metadata

=over 4



=item Definition

=begin html

<pre>
a reference to a list containing 9 items:
0: an object_id
1: an object_type
2: a timestamp
3: an int
4: a string
5: a username
6: a username
7: a workspace_id
8: a workspace_ref

</pre>

=end html

=begin text

a reference to a list containing 9 items:
0: an object_id
1: an object_type
2: a timestamp
3: an int
4: a string
5: a username
6: a username
7: a workspace_id
8: a workspace_ref


=end text

=back



=head2 workspace_metadata

=over 4



=item Definition

=begin html

<pre>
a reference to a list containing 6 items:
0: a workspace_id
1: a username
2: a timestamp
3: an int
4: a permission
5: a permission

</pre>

=end html

=begin text

a reference to a list containing 6 items:
0: a workspace_id
1: a username
2: a timestamp
3: an int
4: a permission
5: a permission


=end text

=back



=head2 save_object_params

=over 4



=item Description

Object management routines


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
data has a value which is an ObjectData
workspace has a value which is a workspace_id
command has a value which is a string
metadata has a value which is a reference to a hash where the key is a string and the value is a string
auth has a value which is a string
json has a value which is a bool
compressed has a value which is a bool
retrieveFromURL has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
data has a value which is an ObjectData
workspace has a value which is a workspace_id
command has a value which is a string
metadata has a value which is a reference to a hash where the key is a string and the value is a string
auth has a value which is a string
json has a value which is a bool
compressed has a value which is a bool
retrieveFromURL has a value which is a bool


=end text

=back



=head2 delete_object_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 delete_object_permanently_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 get_object_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string


=end text

=back



=head2 get_object_output

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
data has a value which is an ObjectData
metadata has a value which is an object_metadata

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
data has a value which is an ObjectData
metadata has a value which is an object_metadata


=end text

=back



=head2 get_objectmeta_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string


=end text

=back



=head2 revert_object_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
instance has a value which is an int
auth has a value which is a string


=end text

=back



=head2 copy_object_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_id has a value which is an object_id
new_workspace has a value which is a workspace_id
source_id has a value which is an object_id
instance has a value which is an int
type has a value which is an object_type
source_workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_id has a value which is an object_id
new_workspace has a value which is a workspace_id
source_id has a value which is an object_id
instance has a value which is an int
type has a value which is an object_type
source_workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 move_object_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_id has a value which is an object_id
new_workspace has a value which is a workspace_id
source_id has a value which is an object_id
type has a value which is an object_type
source_workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_id has a value which is an object_id
new_workspace has a value which is a workspace_id
source_id has a value which is an object_id
type has a value which is an object_type
source_workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 has_object_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
instance has a value which is an int
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
instance has a value which is an int
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 object_history_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an object_id
type has a value which is an object_type
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 create_workspace_params

=over 4



=item Description

Workspace management routines


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
default_permission has a value which is a permission
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
default_permission has a value which is a permission
auth has a value which is a string


=end text

=back



=head2 get_workspacemeta_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 get_workspacepermissions_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 delete_workspace_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 clone_workspace_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_workspace has a value which is a workspace_id
current_workspace has a value which is a workspace_id
default_permission has a value which is a permission
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_workspace has a value which is a workspace_id
current_workspace has a value which is a workspace_id
default_permission has a value which is a permission
auth has a value which is a string


=end text

=back



=head2 list_workspaces_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
auth has a value which is a string


=end text

=back



=head2 list_workspace_objects_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
type has a value which is a string
showDeletedObject has a value which is a bool
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a workspace_id
type has a value which is a string
showDeletedObject has a value which is a bool
auth has a value which is a string


=end text

=back



=head2 set_global_workspace_permissions_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
new_permission has a value which is a permission
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
new_permission has a value which is a permission
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 set_workspace_permissions_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
users has a value which is a reference to a list where each element is a username
new_permission has a value which is a permission
workspace has a value which is a workspace_id
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
users has a value which is a reference to a list where each element is a username
new_permission has a value which is a permission
workspace has a value which is a workspace_id
auth has a value which is a string


=end text

=back



=head2 queue_job_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
jobid has a value which is a string
jobws has a value which is a string
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
jobid has a value which is a string
jobws has a value which is a string
auth has a value which is a string


=end text

=back



=head2 set_job_status_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
jobid has a value which is a string
jobws has a value which is a string
status has a value which is a string
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
jobid has a value which is a string
jobws has a value which is a string
status has a value which is a string
auth has a value which is a string


=end text

=back



=head2 get_jobs_params

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
status has a value which is a string
auth has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
status has a value which is a string
auth has a value which is a string


=end text

=back



=cut

package Bio::KBase::workspaceService::Client::RpcClient;
use base 'JSON::RPC::Client';

#
# Override JSON::RPC::Client::call because it doesn't handle error returns properly.
#

sub call {
    my ($self, $uri, $obj) = @_;
    my $result;

    if ($uri =~ /\?/) {
       $result = $self->_get($uri);
    }
    else {
        Carp::croak "not hashref." unless (ref $obj eq 'HASH');
        $result = $self->_post($uri, $obj);
    }

    my $service = $obj->{method} =~ /^system\./ if ( $obj );

    $self->status_line($result->status_line);

    if ($result->is_success) {

        return unless($result->content); # notification?

        if ($service) {
            return JSON::RPC::ServiceObject->new($result, $self->json);
        }

        return JSON::RPC::ReturnObject->new($result, $self->json);
    }
    elsif ($result->content_type eq 'application/json')
    {
        return JSON::RPC::ReturnObject->new($result, $self->json);
    }
    else {
        return;
    }
}


sub _post {
    my ($self, $uri, $obj) = @_;
    my $json = $self->json;

    $obj->{version} ||= $self->{version} || '1.1';

    if ($obj->{version} eq '1.0') {
        delete $obj->{version};
        if (exists $obj->{id}) {
            $self->id($obj->{id}) if ($obj->{id}); # if undef, it is notification.
        }
        else {
            $obj->{id} = $self->id || ($self->id('JSON::RPC::Client'));
        }
    }
    else {
        $obj->{id} = $self->id if (defined $self->id);
    }

    my $content = $json->encode($obj);

    $self->ua->post(
        $uri,
        Content_Type   => $self->{content_type},
        Content        => $content,
        Accept         => 'application/json',
	($self->{token} ? (Authorization => $self->{token}) : ()),
    );
}



1;
