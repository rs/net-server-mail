package Net::Server::Mail;

use 5.006;
use strict;
use Sys::Hostname;
use IO::Select;
use Carp;

$Net::Server::Mail::VERSION = '0.01';

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
    croak "odd number of arguments" if(@_ % 2);
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

    return unless
    (
        (defined $options->{handle_in} && defined $options->{handle_out})
        || defined $options->{socket}
    );

    $self->reset_sender;
    $self->reset_recipient;
    $self->reset_data;

    return $self;
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

    $msg = $code >= 400 ? 'Failure' : 'Ok'
        unless defined $msg;

    my @lines = split(/\n\r?/, $msg);
    for(my $i = 0; $i < @lines; $i++)
    {
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

sub get_sender
{
    my($self) = @_;
    return $self->{sender};
}

sub set_sender
{
    my($self, $sender) = @_;
    $self->{sender} = $sender;
}

sub reset_sender
{
    my($self, $sender) = @_;
    $self->{sender} = '';
}

sub get_recipient
{
    my($self) = @_;
    return @{$self->{recipient}};
}

sub push_recipient
{
    my($self, @rcpt) = @_;
    push @{$self->{recipient}}, @rcpt;
}

sub reset_recipient
{
    my($self) = @_;
    $self->{recipient} = [];
}

sub get_data
{
    my($self) = @_;
    return $self->{data};
}

sub put_data
{
    my($self, $data) = @_;
    $self->{data} .= $data;
}

sub reset_data
{
    my($self, $date) = @_;
    $self->{data} = '';
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

    $self->reply(220, $str);
}

sub timeout
{
    my($self) = @_;
    $self->reply(421, 'Error: timeout exceeded');
    return 1;
}

1;
