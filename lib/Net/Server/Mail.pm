package Net::Server::Mail;

use 5.006;
use strict;
use Sys::Hostname;
use IO::Select;
use Carp;

$Net::Server::Mail::VERSION = '0.01';

=pod

=head1 NAME

Net::Server::Mail - Class to easly create mail server

=head1 DESCRIPTION

This class is the base class for mail service protocols like
SMTP, ESMTP and LMTP. Look at manual page for each of these
sub-modules.

=head1 METHODS

=head2 new

    $instance = new Net::Server::Mail [option => 'value', ...]

options:

=over 4

=item handle_in and handle_out

Tell on which handle server read and write commands.
(defaults are STDIN/STDOUT)

=item socket

Instead of handle, read/write on a socket 

=item error_sleep_time

Number of seconds to wait for before print the error message,
this can avoid some DoS attack by flooding server with bogus
commands. A value of 0 unactivate this feature. (default is 0)

=item idle_timeout

Number of seconds of idle to wait before close connection. A value
of 0 unactivate this feature. (default is 0)

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

    unless((defined $options->{handle_in} && defined $options->{handle_out})
        or defined $options->{socket})
    {
        $options->{handle_in}  = \*STDIN;
        $options->{handle_out} = \*STDOUT;
    }

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

    if(defined $code)
    {
        $self->reply($code, $msg);
    }
    else
    {
        if(defined $success && $success)
        {
            if(defined $args{'success_reply'} && ref $args{'success_reply'} eq 'ARRAY')
            {
                # don't reply anything if code is an empty string
                if(length $args{'success_reply'}->[0])
                {
                    $self->reply(@{$args{'success_reply'}});
                }
            }
            else
            {
                $self->reply(250, 'Ok');
            }
        }
        else
        {
            if(defined $args{'failure_reply'} && ref $args{'failure_reply'} eq 'ARRAY')
            {
                # don't reply anything if code is an empty string
                if(length $args{'failure_reply'}->[0])
                {
                    $self->reply(@{$args{'failure_reply'}});
                }
            }
            else
            {
                $self->reply(550, 'Failure');
            }
        }
    }

    return;
}

sub callback
{
    my($self, $name, @args) = @_;

    if(defined $self->{callback}->{$name})
    {
        my $rv;
        eval
        {
            $rv = &{$self->{callback}->{$name}}(@args);
        };
        if($@)
        {
            confess $@;
        }
        return $rv;
    }

    return 1;
}

=pod

=head2 set_callback

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

Setup callback code to call on a particulare event.

=cut

sub set_callback
{
    my($self, $name, $code) = @_;
    confess('bad callback() invocation')
        unless defined $code && ref $code eq 'CODE';
    $self->{callback}->{$name} = $code;
}

sub set_cmd
{
    my($self, $cmd, $coderef) = @_;
    $self->{cmd}->{uc $cmd} = $coderef;
}

sub del_cmd
{
    my($self, $cmd) = @_;
    delete $self->{cmd}->{$cmd}
        if defined $self->{cmd};
}

=pod

=head2 process

    $mailserver->process;

Begin a new session

=cut

sub process
{
    my($self) = @_;

    my $in  = $self->get_in;
    my $sel = new IO::Select;
    $sel->add($in);
    
    $self->banner;
    while($sel->can_read($self->{options}->{idle_timeout} || undef))
    {
        $_ = <STDIN>;
        chomp;
        s/^\s+|\s+$//g;
        next unless length;
        my($cmd, @args) = split;
        
        if(exists $self->{cmd}->{uc $cmd})
        {
            my $rv = &{$self->{cmd}->{uc $cmd}}($self, @args);
            # close connection if command return something
            return $rv if(defined $rv);
        }
        else
        {
            $self->reply(502, 'Error: command not implemented');
            next;
        }
    }

    $self->timeout;
}

sub reply
{
    my($self, $code, $msg) = @_;
    my $out = $self->get_out;
    # tempo on error
    sleep $self->{options}->{error_sleep_time}
        if($code >= 400 && $self->{options}->{error_sleep_time});

    # default message
    $msg = $code >= 400 ? 'Failure' : 'Ok'
        unless defined $msg;

    # handle multiple lines
    my @lines = split(/\n\r?/, $msg);
    for(my $i = 0; $i < @lines; $i++)
    {
        # RFC say that all lines but the last have to
        # split the code and the message with a dash (-)
        my $sep = $i == $#lines ? ' ' : '-';
        print $out "$code$sep$lines[$i]\n\r";
    }
}

sub get_in
{
    my($self) = @_;
    if(defined $self->{options}->{handle_in})
    {
        return $self->{options}->{handle_in};
    }
    elsif(defined $self->{options}->{socket})
    {
        return $self->{options}->{socket};
    }
    else
    {
        croak "no handle to read";
    }
}

sub get_out
{
    my($self) = @_;
    if(defined $self->{options}->{handle_out})
    {
        return $self->{options}->{handle_out};
    }
    elsif(defined $self->{options}->{socket})
    {
        return $self->{options}->{socket};
    }
    else
    {
        croak "no handle to write";
    }
}

sub get_hostname
{
    my($self) = @_;
    return hostname;
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
    $str .= $appname       if length $appname;

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
        success_reply => [421, 'Error: timeout exceeded'],
    );

    return 1;
}

1;
