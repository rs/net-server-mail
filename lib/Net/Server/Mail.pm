package Net::Server::Mail;

use 5.006;
use strict;
use Sys::Hostname;
use IO::Select;
use Carp;

use constant HOSTNAME => hostname();

$Net::Server::Mail::VERSION = '0.01';

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
        $smtp->process;
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
        elsif(grep $domain eq $_, @local_domains)
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

This class is the base class for mail service protocols such as
B<Net::Server::Mail::SMTP>, B<Net::Server::Mail::ESMTP> and
B<Net::Server::Mail::LMTP>. Refer to the documentation provided
with each of these modules.

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
        $self->{in}  = $options->{handle_in};
        $self->{out} = $options->{handle_out};
    }
    elsif(defined $options->{'socket'})
    {
        $self->{in}  = $options->{'socket'};
        $self->{out} = $options->{'socket'};
    }
    else
    {
        $self->{in}  = \*STDIN;
        $self->{out} = \*STDOUT;
    }

    $self->{process_operation} = \&process_operation;

    return $self;
}

sub make_event
{
    my $self = shift;
    confess('odd number of arguments') if(@_ % 2);
    my %args = @_;

    my $name = $args{'name'} || confess('missing argument: \'name\'');
    my $args = defined $args{'arguments'} && ref $args{'arguments'} eq 'ARRAY'
        ? $args{'arguments'} : [];
    
    my($success, $code, $msg) = $self->callback($name, @{$args});

    if(defined $success && defined $args{'on_success'})
    {
        if(ref $args{'on_success'} eq 'CODE')
        {
            &{$args{'on_success'}};
        }
    }

    unless(defined $code)
    {
        if(defined $success && $success)
        {
            if(defined $args{'success_reply'} && ref $args{'success_reply'} eq 'ARRAY')
            {
                ($code, $msg) = @{$args{'success_reply'}};
            }
            else
            {
                $code = 250;
            }
        }
        else
        {
            if(defined $args{'failure_reply'} && ref $args{'failure_reply'} eq 'ARRAY')
            {
                ($code, $msg) = @{$args{'failure_reply'}};
            }
            else
            {
                $code = 550;
            }
        }
    }

    $self->handle_reply($name, $success, $code, $msg);

    return;
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
            @rv = &{$self->{callback}->{$name}}(@args);
        };
        if($@)
        {
            confess $@;
        }
        return @rv;
    }

    return 1;
}

=pod

=head2 set_callback

  ($success, $code, $msg) = $obj->set_callback(VERB, \&function)>

Sets the callback code to be called on a particular event. The function should
return 1 to 3 values: (success, [return_code, ["message"]]).

    $mailserver->set_callback
    (
        'RCPT', sub
        {
            my($address) = @_;
            if(is_relayed($address))
            {
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
    my($self, $name, $code) = @_;
    confess('bad callback() invocation')
        unless defined $code && ref $code eq 'CODE';
    $self->{callback}->{$name} = $code;
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
    while($sel->can_read($self->{options}->{idle_timeout} || undef))
    {
        # switch to non-blocking socket to handle PIPELINING
        # ESMTP extension. See RFC 2920 for more details.
        $in->blocking(0);
        $_ = join '', <$in>;
        $in->blocking(1);
        next unless defined;
        my $rv = $self->{process_operation}($self, $_);
        # if $rv is defined, we have to close the connection
        return $rv if defined $rv;
    }

    $self->timeout;
}

sub process_operation
{
    my($self, $operation) = @_;
    my($verb, $params) = $self->tokenize_command($operation);
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

sub banner
{
    my($self) = @_;
    
    my $hostname  = $self->get_hostname  || '';
    my $protoname = $self->get_protoname || '';
    my $appname   = $self->get_appname   || '';
    
    my $str;
    $str  = $hostname.' '  if length $hostname;
    $str .= $protoname.' ' if length $protoname;
    $str .= $appname.' '   if length $appname;
    $str .= 'Service ready';

    $self->make_event
    (
        name => 'banner',
        success_reply => [220, $str],
        failure_reply => ['',''],
    );
}

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

1;
