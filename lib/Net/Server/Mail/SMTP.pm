package Net::Server::Mail::SMTP;

use 5.006;
use strict;
use base 'Net::Server::Mail';

sub init
{
    my($self, @args) = @_;
    $self->SUPER::init(@args);

    $self->set_cmd(HELO => \&helo);
    $self->set_cmd(NOOP => \&noop);
    $self->set_cmd(MAIL => \&mail);
    $self->set_cmd(RCPT => \&rcpt);
    $self->set_cmd(DATA => \&data);
    $self->set_cmd(RSET => \&rset);
    $self->set_cmd(QUIT => \&quit);

    # go to the initial step
    $self->step_reverse_path(0);
    $self->step_forward_path(0);
    $self->step_maildata_path(0);

    return $self;
}

sub step_reverse_path
{
    my($self, $bool) = @_;
    if(defined $bool)
    {
        $self->{reverse_path} = $bool;
    }   
    
    return $self->{reverse_path};
}   

sub step_forward_path
{
    my($self, $bool) = @_;
    if(defined $bool)
    {
        $self->{forward_path} = $bool;
    }   
    
    return $self->{forward_path};
}   

sub step_maildata_path
{
    my($self, $bool) = @_;
    if(defined $bool)
    {
        $self->{maildata_path} = $bool;
    }   
    
    return $self->{maildata_path};
}   

sub get_protoname
{   
    my($self) = @_;
    return 'SMTP';
}


sub helo
{
    my($self, $hostname) = @_;
    
    unless(defined $hostname && length $hostname)
    {
        $self->reply(501, 'Syntax: HELO hostname');
    }
    
    $self->make_event
    (
        name => 'HELO',
        arguments => [$hostname],
        on_success => sub
        {
            # conforming to RFC, HELO ensure "that both the SMTP client and the
            # SMTP server are in the initial state"
            $self->step_reverse_path(1);
            $self->step_forward_path(0);
            $self->step_maildata_path(0);
        },
        success_reply => [250, 'Ok'],
    );

    return;
}

sub noop
{
    my($self) = @_;

    $self->make_event(name => 'NOOP');

    return;
}

=pod

=head2 Callback MAIL

    ($success, [$code, [$msg]]) = callback($address);

=cut

sub mail
{
    my($self, $from, $address, @options) = @_;

    unless($self->step_reverse_path)
    {
        $self->reply(503, 'Error: need HELO command');
        return;
    }

    unless(defined $from && lc $from eq 'from:')
    {
        $self->reply(501, 'Syntax: MAIL FROM: <address>');
        return;
    }

    if($self->step_forward_path)
    {
        $self->reply(503, 'Error: nested MAIL command');
        return;
    }

    unless($self->mail_options)
    {
        return;
    }

    $self->make_event
    (
        name => 'MAIL',
        arguments => [$address],
        on_success => sub
        {
            $self->step_forward_path(1);
        },
        success_reply => [250, 'Ok'],
        failure_reply => [550, 'Failure'],
    );

    return;
}

sub mail_options
{
    my($self, @options) = @_;

    if(@options)
    {
        $self->reply(555, "Unsupported option: $options[0]");
        return 0;
    }

    return 1;
}

=pod

=head2 Callback RCPT

    ($success, [$code, [$msg]]) = callback($address);

=cut


sub rcpt
{
    my($self, $to, $address, @options) = @_;
    unless($self->step_forward_path)
    {
        $self->reply(503, 'Error: need MAIL command');
        return;
    }
    
    unless(defined $to && lc $to eq 'to:')
    {
        $self->reply(501, 'Syntax: RCPT TO: <address>');
        return;
    }

    unless($self->mail_options)
    {
        return;
    }

    $self->make_event
    (
        name => 'RCPT',
        arguments => [$address],
        on_success => sub
        {
            $self->step_maildata_path(1);
        },
        success_reply => [250, 'Ok'],
        failure_reply => [550, 'Failure'],
    );

    return;
}

sub rcpt_options
{
    my($self, @options) = @_;

    if(@options)
    {
        $self->reply(555, "Unsupported option: $options[0]");
        return 0;
    }

    return 1;
}

sub data
{
    my($self, @args) = @_;

    unless($self->step_maildata_path)
    {
        $self->reply(503, 'Error: need RCPT command');
        return;
    }
    
    if(@args)
    {
        $self->reply(501, 'Syntax: DATA');
        return;
    }

    $self->reply(354, 'End data with <CR><LF>.<CR><LF>');

    my $in = $self->get_in;

    my $data;
    while(<$in>)
    {
        last if(/^\.\n\r?$/);
        
        # RFC 821 compliance.
        s/^\.\./\./;
        $data .= $_;
    }

    return $self->data_finished($data);
}

sub data_finished
{
    my($self, $data) = @_;

    $self->make_event
    (
        name => 'DATA',
        arguments => [$data],
        success_reply => [250, 'Ok'],
    );

    return;
}

sub rset
{
    my($self) = @_;

    $self->make_event
    (
        name => 'RSET',
        on_success => sub
        {
            $self->step_reverse_path(0);
            $self->step_forward_path(0);
            $self->step_maildata_path(0);
        },
        success_reply => [250, 'Ok'],
    );

    return;
}

sub quit
{
    my($self) = @_;
    
    $self->make_event
    (
        name => 'QUIT',
        success_reply => [221, 'Bye'],
    );

    return 1; # close cnx
}

1;
