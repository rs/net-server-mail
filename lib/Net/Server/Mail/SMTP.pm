package Net::Server::Mail::SMTP;

use 5.006;
use strict;
use base 'Net::Server::Mail';

sub init
{
    my($self, @args) = @_;
    my $rv = $self->SUPER::init(@args);
    return $rv unless $rv eq $self;

    $self->def_verb(HELO => 'helo');
    $self->def_verb(VEFY => 'vrfy');
    $self->def_verb(EXPN => 'expn');
    $self->def_verb(TURN => 'turn');
    $self->def_verb(HELP => 'help');
    $self->def_verb(NOOP => 'noop');
    $self->def_verb(MAIL => 'mail');
    $self->def_verb(RCPT => 'rcpt');
    $self->def_verb(SEND => 'send');
    $self->def_verb(SOML => 'soml');
    $self->def_verb(SAML => 'saml');
    $self->def_verb(DATA => 'data');
    $self->def_verb(RSET => 'rset');
    $self->def_verb(QUIT => 'quit');

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
        $self->reply(501, 'Syntax error in parameters or arguments');
        return;
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
        success_reply => [250, 'Requested mail action okay, completed'],
    );

    return;
}

sub noop
{
    my($self) = @_;
    $self->make_event(name => 'NOOP');
    return;
}

sub expn
{
    my($self, $address) = @_;
    $self->reply(502, 'Command not implemented');
    return;
}

sub turn
{
    # deprecated in RFC 2821
    my($self) = @_;
    $self->reply(502, 'Command not implemented');
    return;
}

sub vrfy
{
    my($self, $address) = @_;
    $self->reply(502, 'Command not implemented');
    return;
}

sub help
{
    my($self, $command) = @_;
    $self->reply(502, 'Command not implemented');
    return;
}

=pod

=head2 Callback MAIL

    ($success, [$code, [$msg]]) = callback($address);

=cut

sub mail
{
    my($self, $args) = @_;

    unless($self->step_reverse_path)
    {
        $self->reply(503, 'Bad sequence of commands');
        return;
    }


    unless($args =~ s/^from:\s*//i)
    {
        $self->reply(501, 'Syntax error in parameters or arguments');
        return;
    }

    if($self->step_forward_path)
    {
        $self->reply(503, 'Bad sequence of commands');
        return;
    }

    my($address, @options) = split(' ', $args);

    unless($self->handle_options('MAIL', $address, @options))
    {
        return;
    }

    $self->make_event
    (
        name => 'MAIL',
        arguments => [$address],
        on_success => sub
        {
            $self->step_reverse_path($address);
            $self->step_forward_path(1);
        },
        success_reply => [250, "sender $address OK"],
        failure_reply => [550, 'Failure'],
    );

    return;
}

sub rcpt
{
    my($self, $args) = @_;

    unless($self->step_forward_path)
    {
        $self->reply(503, 'Bad sequence of commands');
        return;
    }
    
    unless($args =~ s/^to:\s*//i)
    {
        $self->reply(501, 'Syntax error in parameters or arguments');
        return;
    }

    my($address, @options) = split(' ', $args);

    unless($self->handle_options('RCPT', $address, @options))
    {
        return;
    }

    $self->make_event
    (
        name => 'RCPT',
        arguments => [$address],
        on_success => sub
        {
            my $buffer = $self->step_forward_path();
            $buffer = [] unless ref $buffer eq 'ARRAY';
            push(@$buffer, $address);
            $self->step_forward_path($buffer);
            $self->step_maildata_path(1);
        },
        success_reply => [250, "recipient $address OK"],
        failure_reply => [550, 'Failure'],
    );

    return;
}

sub send
{
    my($self) = @_;
    $self->reply(502, 'Command not implemented');
    return;
}

sub soml
{
    my($self) = @_;
    $self->reply(502, 'Command not implemented');
    return;
}

sub saml
{
    my($self) = @_;
    $self->reply(502, 'Command not implemented');
    return;
}

sub data
{
    my($self, $args) = @_;

    unless($self->step_maildata_path)
    {
        $self->reply(503, 'Bad sequence of commands');
        return;
    }
    
    if(defined $args && length $args)
    {
        $self->reply(501, 'Syntax error in parameters or arguments');
        return;
    }

    $self->reply(354, 'Start mail input; end with <CRLF>.<CRLF>');

    my $in = $self->{in};

    my $data;
    while($_=<$in>)
    {
        last if(/^\.\r?\n$/);
        
        # RFC 821 compliance.
        s/^\.//;
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
        success_reply => [250, 'message sent'],
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
        success_reply => [250, 'Requested mail action okay, completed'],
    );

    return;
}

sub quit
{
    my($self) = @_;
    
    $self->make_event
    (
        name => 'QUIT',
        success_reply => [221, $self->get_hostname . ' Service closing transmission channel'],
    );

    return 1; # close cnx
}

##########################################################################

sub handle_options
{
    # handle options for verb MAIL and RCPT
    my($self, $verb, $address, @options) = @_;

    if(@options)
    {
        $self->reply(555, "Unsupported option: $options[0]");
        return 0;
    }

    return 1;
}

1;
