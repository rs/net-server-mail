package Net::Server::Mail;

use 5.006;
use strict;
use Sys::Hostname;
use IO::Select;
use IO::Handle;
use Carp;

use constant HOSTNAME => hostname();

$Net::Server::Mail::VERSION = '0.16';

=pod

=head1 NAME

Net::Server::Mail - Class to easily create a mail server

=head1 SYNOPSIS

    use Net::Server::Mail::SMTP;

    my @local_domains = qw(example.com example.org);
    my $server = new IO::Socket::INET Listen => 1, LocalPort => 25;
    
    my $conn;
    while($conn = $server->accept)
    {
        my $smtp = new Net::Server::Mail::SMTP socket => $conn;
        $smtp->set_callback(RCPT => \&validate_recipient);
        $smtp->set_callback(DATA => \&queue_message);
        $smtp->process();
	$conn->close();
    }

    sub validate_recipient
    {
        my($session, $recipient) = @_;
        
        my $domain;
        if($recipient =~ /@(.*)>\s*$/)
        {
            $domain = $1;
        }

        if(not defined $domain)
        {
            return(0, 513, 'Syntax error.');
        }
        elsif(not(grep $domain eq $_, @local_domains))
        {
            return(0, 554, "$recipient: Recipient address rejected: Relay access denied");
        }

        return(1);
    }

    sub queue_message
    {
        my($session, $data) = @_;

        my $sender = $session->get_sender();
        my @recipients = $session->get_recipients();

        return(0, 554, 'Error: no valid recipients')
            unless(@recipients);
        
        my $msgid = add_queue($sender, \@recipients, $data);
          or return(0);

        return(1, 250, "message queued $msgid");
    }

=head1 DESCRIPTION

This module is a versatile and extensible implementation of the SMTP
protocol and its different evolutions like ESMTP and LMTP. The event
driven object-oriented API makes easy to incorporate the SMTP protocol
to your programs.

Other SMTPd implementations don't support useful ESMTP extensions and
the LMTP protocol. Their interface design precludes adding them
later. So I've decided to rewrite a complete implementation with
extensibility in mind.

It provides mechanism to easy addition future or not yet implemented
ESMTP extensions. Developers can hook code at each SMTP session state
and change the module's behaviors by registering event call-backs. The
class is designed to be easily inherited from.

This class is the base class for mail service protocols such axs
B<Net::Server::Mail::SMTP>, B<Net::Server::Mail::ESMTP> and
B<Net::Server::Mail::LMTP>. Refer to the documentation provided with
each of these modules.

=head1 METHODS

=head2 new

    $instance = new Net::Server::Mail [option => 'value', ...]

options:

=over 4

=item handle_in

Sets the input handle, from which the server reads data. Defaults to
STDIN.

=item handle_out

Sets the output handle, to which the server writes data. Defaults to
STDOUT.

=item socket

Sets a socket to be used for server reads and writes instead of
handles.

=item error_sleep_time

Number of seconds to wait for before printing an error message. This
avoids some DoS attacks that attempt to flood the server with bogus
commands. A value of 0 turns this feature off. Defaults to 0.

=item idle_timeout

Number of seconds a connection must remain idle before it is closed.
A value of 0 turns this feature off. Defaults to 0.

=back

=cut

sub new
{
    my($proto, @args) = @_;
    my $class = ref $proto || $proto;
    my $self  = {};
    bless($self, $class);
    return $self->init(@args);
}

sub init
{
    my $self = shift;
    confess("odd number of arguments") if(@_ % 2);
    my $options = $self->{options} =
    {
        handle_in           => undef,
        handle_out          => undef,
        socket              => undef,
        error_sleep_time    => 0,
        idle_timeout        => 0,
    };
    for(my $i = 0; $i < @_; $i += 2)
    {
        $options->{lc($_[$i])} = $_[$i + 1];
    }

    if(defined $options->{handle_in} && defined $options->{handle_out})
    {
        if(UNIVERSAL::isa($options->{handle_in},'IO::Handle'))
        {
            $self->{in} = $options->{handle_in};
        }
        else
        {
            $self->{in} = 
              IO::Handle->new->fdopen(fileno($options->{handle_in}), "r");
        }
        if(UNIVERSAL::isa($options->{handle_out},'IO::Handle'))
        {
            $self->{out} = $options->{handle_out};
        }
        else
        {
            $self->{out} = 
              IO::Handle->new->fdopen(fileno($options->{handle_out}), "w");
        }
    }
    elsif(defined $options->{'socket'})
    {
        $self->{in}  = $options->{'socket'};
        $self->{out} = $options->{'socket'};
    }
    else
    {
        $self->{in}  = IO::Handle->new->fdopen(fileno(STDIN), "r");
        $self->{out} = IO::Handle->new->fdopen(fileno(STDOUT), "w");
    }

    $self->{out}->autoflush(1);
    $self->{process_operation} = \&process_operation;

    return $self;
}

=pod

=head2 dojob

Some command need to do some job after the handler call. Handler may
want to overide this comportement to prevent from this job being
executed.

By calling this method with a (defined) false value as argument,
expected job isn't executed. Defaults to true.

=cut

sub init_dojob {shift->{_dojob} = 1;}
sub dojob
{
    my($self, $bool) = @_;
    $self->{_dojob} = $bool if(defined $bool);
    return $self->{_dojob};
}

sub make_event
{
    my $self = shift;
    confess('odd number of arguments') if(@_ % 2);
    my %args = @_;

    my $name = $args{'name'} || confess('missing argument: \'name\'');
    my $args = defined $args{'arguments'} && ref $args{'arguments'} eq 'ARRAY'
        ? $args{'arguments'} : [];

    $self->init_dojob();
    my($success, $code, $msg) = $self->callback($name, @{$args});

    # we have to take a proper decision if successness is undefined
    if(not defined $success)
    {
        if(exists $args{'default_reply'})
        {
            if(ref $args{'default_reply'} eq 'ARRAY')
            {
                ($success, $code, $msg) = $args{'default_reply'};
                $success = 0 unless defined $success;
            }
            else
            {
                $success = $args{'default_reply'};
            }
        }
        else
        {
            $success = 1; # default
        }
    }

    # command may have some job to do regarding to the result. handler
    # can avoid it by calling dojob() method with a false value.
    if($self->dojob())
    {
        if($success)
        {
            if(defined $args{'on_success'}
               and ref $args{'on_success'} eq 'CODE')
            {
                &{$args{'on_success'}};
            }
        }
        else
        {
            if(defined $args{'on_failure'}
               and ref $args{'on_failure'} eq 'CODE')
            {
                &{$args{'on_failure'}};
            }
        }
    }

    # ensure that a reply is sent, all SMTP command need at most 1 reply.
    unless(defined $code)
    {
        if(defined $success && $success)
        {
            ($code, $msg) =
              $self->get_default_reply($args{'success_reply'}, 250);
        }
        else
        {
            ($code, $msg) =
              $self->get_default_reply($args{'failure_reply'}, 550);
        }
    }

    die "return code `$code' isn't numeric" if($code =~ /\D/);

    $self->handle_reply($name, $success, $code, $msg)
      if defined $code and length $code;

    return $success;
}

sub get_default_reply
{
    my($self, $config, $default) = @_;

    my($code, $msg);
    if(defined $config)
    {
        if(ref $config eq 'ARRAY')
        {
            ($code, $msg) = @$config;
        }
        elsif(not ref $config)
        {
            $code = $config;
        }
        else
        {
            confess("unexpected format for reply");
        }
    }
    else
    {
        $code = $default;
    }

    return($code, $msg);
}

sub handle_reply
{
    my($self, $verb, $success, $code, $msg) = @_;
    # don't reply anything if code is empty
    $self->reply($code, $msg) if(length $code);
}

sub callback
{
    my($self, $name, @args) = @_;

    if(defined $self->{callback}->{$name})
    {
        my @rv;
        eval
        {
            my($code, $context) = @{$self->{callback}->{$name}};
            $self->set_context($context);
            @rv = &{$code}($self, @args);
        };
        if($@)
        {
            confess $@;
        }
        return @rv;
    }

    return 1;
}

sub set_context
{
    my($self, $context) = @_;
    $self->{_context} = $context;
}

sub get_context
{
    my($self) = @_;
    return $self->{_context};
}

=pod

=head2 set_callback

  ($success, $code, $msg) = $obj->set_callback(VERB, \&function, $context)>

Sets the callback code to be called on a particular event. The function should
return 1 to 3 values: (success, [return_code, ["message"]]).

    $mailserver->set_callback
    (
        'RCPT', sub
        {
            my($address) = @_;
            if(is_relayed($address))
            {
                # default success code/message will be used
                return 1;
            }
            else
            {
                return(0, 513, 'Relaying denied.');
            }
        }
    );

=cut

sub set_callback
{
    my($self, $name, $code, $context) = @_;
    confess('bad callback() invocation')
        unless defined $code && ref $code eq 'CODE';
    $self->{callback}->{$name} = [$code, $context];
}

sub def_verb
{
    my($self, $verb, $coderef) = @_;
    $self->{verb}->{uc $verb} = $coderef;
}

sub undef_verb
{
    my($self, $verb) = @_;
    delete $self->{verb}->{$verb}
        if defined $self->{verb};
}

sub list_verb
{
    my($self) = @_;
    return keys %{$self->{verb}};
}


sub next_input_to
{
    my($self, $method_ref) = @_;
    $self->{next_input} = $method_ref
      if(defined $method_ref);
    return $self->{next_input}
}

sub tell_next_input_method
{

    my($self, $input) = @_;
    # calling the method and reinitialize. Note: we have to reinit
    # before calling the code, because code can resetup this variable.
    my $code = $self->{next_input};
    undef $self->{next_input};
    my $rv = &{$code}($self, $input);
    return $rv;
}

=pod

=head2 process

    $mailserver->process;

Start a new session.

=cut

sub process
{
    my($self) = @_;

    my $in  = $self->{in};
    my $sel = new IO::Select;
    $sel->add($in);

    $self->banner;
    # switch to non-blocking socket to handle PIPELINING
    # ESMTP extension. See RFC 2920 for more details.
    if($^O eq 'MSWin32')
    {
        # win32 platforms don't support nonblocking IO
        ioctl($in, 2147772030, 1);
    }
    else
    {
        defined($in->blocking(0)) or die "Couldn't set nonblocking: $^E";
    }
    
    while($sel->can_read($self->{options}->{idle_timeout} || undef))
    {
        if ($^O eq 'MSWin32')
        {
            # see how much data is available to read
            my $size = pack("L",0);
            ioctl($in, 1074030207, $size);
            $size = unpack("L", $size);

            # read the data and put it in the $_ variable
            read($in, $_, $size);
        }
        else
        {
            my @lines = <$in>;
            @lines = grep(defined, @lines);

            if(scalar @lines) {
                $_ = join '', @lines;
            } else {
                $_ = undef;
            }
        }
        
        # do not go into an infinit loop if client close the connection
        last unless defined $_;

        my $rv;
        if(defined $self->next_input_to())
        {
            $rv = $self->tell_next_input_method($_);
        }
        else
        {
            next unless defined;
            $rv = $self->{process_operation}($self, $_);
        }
        # if $rv is defined, we have to close the connection
        return $rv if defined $rv;
    }

    $self->timeout;
}

sub process_once
{
    my($self, $operation) = @_;
    if($self->next_input_to())
    {
        return $self->tell_next_input_method($operation);
    }
    else
    {
        return $self->{process_operation}($self, $operation);
    }
}

sub process_operation
{
    my($self, $operation) = @_;
    my($verb, $params) = $self->tokenize_command($operation);
    if(defined $params && $params =~ /[\r\n]/)
    {
        # doesn't support grouping of operations
        $self->reply(453, "Command received prior to completion of".
                     " previous command sequence");
        return;
    }
    $self->process_command($verb, $params);
}

sub process_command
{
    my($self, $verb, $params) = @_;

    if(exists $self->{verb}->{$verb})
    {
        my $action = $self->{verb}->{$verb};
        my $rv;
        if(ref $action eq 'CODE')
        {
            $rv = &{$self->{verb}->{$verb}}($self, $params);
        }
        else
        {
            $rv = $self->$action($params);
        }
        return $rv;
    }
    else
    {
        $self->reply(500, 'Syntax error: unrecognized command');
        return;
    }
}

sub tokenize_command
{
    my($self, $line) = @_;
    $line =~ s/\r?\n$//s;
    $line =~ s/^\s+|\s+$//g;
    my($verb, $params) = split ' ', $line, 2;
    return(uc($verb), $params);
}

sub reply
{
    my($self, $code, $msg) = @_;
    my $out = $self->{out};
    # tempo on error
    sleep $self->{options}->{error_sleep_time}
        if($code >= 400 && $self->{options}->{error_sleep_time});

    # default message
    $msg = $code >= 400 ? 'Failure' : 'Ok'
        unless defined $msg;

    # handle multiple lines
    my @lines;

    if(ref $msg)
    {
        confess "bad argument" unless ref $msg eq 'ARRAY';
        @lines = @$msg;
    }
    else
    {
        @lines = split(/\r?\n/, $msg);
    }
    for(my $i = 0; $i < @lines; $i++)
    {
        # RFC says that all lines but the last must
        # split the code and the message with a dash (-)
        my $sep = $i == $#lines ? ' ' : '-';
        print $out "$code$sep$lines[$i]\r\n";
    }
}

sub get_hostname
{
    my($self) = @_;
    return HOSTNAME;
}

sub get_protoname
{
    my($self) = @_;
    return 'NOPROTO';
}

sub get_appname
{
    my($self) = @_;
    return 'Net::Server::Mail (Perl)';
}

###########################################################

=pod

=head2 banner

Send the introduction banner. You have to call it manually when are
using process_once() method. Don't use it with process() method.

=head1 EVENTS

=head2 banner

Append at the opening of a new connection.

Handler takes no argument.

=cut

sub banner
{
    my($self) = @_;

    unless(defined $self->{banner_string})
    {
        my $hostname  = $self->get_hostname  || '';
        my $protoname = $self->get_protoname || '';
        my $appname   = $self->get_appname   || '';

        my $str;
        $str  = $hostname.' '  if length $hostname;
        $str .= $protoname.' ' if length $protoname;
        $str .= $appname.' '   if length $appname;
        $str .= 'Service ready';
        $self->{banner_string} = $str;
    }

    $self->make_event
    (
        name => 'banner',
        success_reply => [220, $self->{banner_string}],
        failure_reply => ['',''],
    );
}

=pod

=head2 timeout

This event append where timeout is exeded.

Handler takes no argument.

=cut

sub timeout
{
    my($self) = @_;

    $self->make_event
    (
        name => 'timeout',
        success_reply => 
        [
            421,
            $self->get_hostname . 
                ' Timeout exceeded, closing transmission channel'
        ],
    );

    return 1;
}

=pod

=head1 SEE ALSO

Please, see L<Net::Server::Mail::SMTP>, L<Net::Server::Mail::ESMTP>
and L<Net::Server::Mail::LMTP>.

=head1 AUTHOR

Olivier Poitrey E<lt>rs@rhapsodyk.netE<gt>

=head1 AVAILABILITY

Available on CPAN.

anonymous Git repository:

git clone git://github.com/rs/net-server-mail.git

Git repository on the web:

L<https://github.com/rs/net-server-mail>

=head1 BUGS

Please use CPAN system to report a bug (http://rt.cpan.org/).

=head1 LICENCE

This library is free software; you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as
published by the Free Software Foundation; either version 2.1 of the
License, or (at your option) any later version.

This library is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
USA

=head1 COPYRIGHT

Copyright (C) 2002 - Olivier Poitrey, 2007 - Xavier Guimard

=cut

1;
