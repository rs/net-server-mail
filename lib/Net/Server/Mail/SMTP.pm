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

    $self->set_callback(MAIL => \&mail_callback);

    return $self;
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
    $self->reply(250, $self->get_hostname);
    return;
}

sub noop
{
    my($self) = @_;
    $self->reply(250, 'Ok');
    return;
}

=pod

=head2 Callback MAIL

    ($success, [$code, [$msg]]) = callback($address);

=cut

sub mail
{
    my($self, $from, $address, @options) = @_;

    unless(defined $from && lc $from eq 'from:')
    {
        $self->reply(501, 'Syntax: MAIL FROM: <address>');
        return;
    }

    if(length $self->get_sender)
    {
        $self->reply(503, 'Error: nested MAIL command');
        return;
    }

    unless($self->mail_options)
    {
        return;
    }

    my($success, $code, $msg) = $self->callback('MAIL', $address);

    if(defined $success && $success)
    {
        $self->set_sender($address);
    }

    if(defined $code)
    {
        $self->reply($code, $msg);
    }
    else
    {
        if(defined $success)
        {
            $self->reply(250, 'Ok');
        }
        else
        {
            $self->reply(550, 'Failure');
        }
    }

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
    unless(length $self->get_sender)
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

    my($success, $code, $msg) = $self->callback('RCPT', $address);

    if(defined $success && $success)
    {
        $self->push_recipient($address);
    }

    if(defined $code)
    {
        $self->reply($code, $msg);
    }
    else
    {
        if(defined $success)
        {
            $self->reply(250, 'Ok');
        }
        else
        {
            $self->reply(550, 'Failure');
        }
    }

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

    unless($self->get_recipient)
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

    while(<$in>)
    {
        last if(/^\.\n\r?$/);
        
        # RFC 821 compliance.
        s/^\.\./\./;
        $self->put_data($_);
    }

    return $self->data_finished;
}

sub data_finished
{
    my($self) = @_;

    my $id = $self->queue;
    $self->reply(250, "Ok queued as $id");
    return;
}

sub rset
{
    my($self) = @_;
    $self->reset_sender;
    $self->reset_recipient;
    $self->reset_data;
    $self->reply(250, 'Ok');
    return;
}

sub quit
{
    my($self) = @_;
    $self->reply(221, 'Bye');
    return 1; # close cnx
}

# queue mechanism, should be in Net::Server::Mail::Queue

sub queue
{
    my($self) = @_;
    
    my $id = $self->generate_id;
    
    my $msg =
    {
        sender      => $self->get_sender,
        recipient   => [$self->get_recipient],
        data        => $self->get_data,
    };  
    
    $self->reset_sender;
    $self->reset_recipient;
    $self->reset_data;
    
    $self->{queue}->{$id} = $msg;
    
    return $id;
}   

sub get_queue
{
    my($self) = @_;
    return $self->{queue};
}   

sub generate_id
{
    my($self) = @_;
    return(join('', map(('A'..'Z', 0..9)[int(rand(36))], 0..9)))
}   


1;
