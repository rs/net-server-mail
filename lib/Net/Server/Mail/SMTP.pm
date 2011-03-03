package Net::Server::Mail::SMTP;

use 5.006;
use strict;
use base 'Net::Server::Mail';

our $VERSION = "0.17";

=pod

=head1 NAME

Net::Server::Mail::SMTP - A module to implement the SMTP protocole

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
        $conn->close()
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

        my $msgid = add_queue($sender, \@recipients, $data)
          or return(0);

        return(1, 250, "message queued $msgid");
    }

=head1 DESCRIPTION

This class implement the SMTP (RFC 821) protocol. Notice that it don't
implement the extension mechanism introduce in RFC 2821. You have to
use Net::Server::Mail::ESMTP if you want this capability.

This class inherit from Net::Server::Mail. Please see
L<Net::Server::Mail> for documentation of common methods.

=head1 METHODS

SMTP specific methods.

=cut

sub init
{
    my($self, @args) = @_;
    my $rv = $self->SUPER::init(@args);
    return $rv unless $rv eq $self;

    $self->def_verb(HELO => 'helo');
    $self->def_verb(VRFY => 'vrfy');
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

    # handle data after the end of data indicator (.)
    $self->{data_handle_more_data} = 0;

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
        # initialise data container
        if(not $bool)
        {
            $self->{_data} = '';
        }
    }

    return $self->{maildata_path};
}

sub get_protoname
{
    return 'SMTP';
}

=pod

=head2 get_sender

Returns the sender of the current session. Return undefined if the
reverse path step is not complete.

=cut

sub get_sender
{
    my($self) = @_;
    my $sender = $self->step_reverse_path();
    return($sender ? $sender : undef);
}

=pod

=head2 get_recipients

Returns the list of recipients supplied by client. Returns undef if
forward_path step is not engaged. Returns an empty list if not
recipients succeed.

=cut

sub get_recipients
{
    my($self) = @_;
    my $recipients = $self->step_forward_path();
    return(ref $recipients ? @$recipients : undef)
}

=pod

=head1 EVENTS

Descriptions of callback who's can be used with set_callback
method. All handle takes the Net::Server::Mail::SMTP object as first
argument and specific callback's arguments.

=head2 HELO

Takes the hostname given as argument. Engage the reverse path step on
success.

    sub helo_handle
    {
        my($session, $hostname) = @_;

        if($hostname eq 'localhost')
        {
            return(0, 553, q(I don't like this hostname, try again.));
        }

        # don't forgot to return a success reply if you are happy with
        # command's value
        return 1;
    }

=cut

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
            # according to the RFC, HELO ensures "that both the SMTP client
            # and the SMTP server are in the initial state"
            $self->step_reverse_path(1);
            $self->step_forward_path(0);
            $self->step_maildata_path(0);
        },
        success_reply => [250, 'Requested mail action okay, completed'],
    );

    return;
}

=pod

=head2 NOOP

This handler takes no argument

=cut

sub noop
{
    my($self) = @_;
    $self->make_event(name => 'NOOP');
    return;
}

=pod

=head2 EXPN

Command not yet implemented.

Handler takes address as argument.

=cut

sub expn
{
    my($self, $address) = @_;
    $self->make_event
      (
       name => 'EXPN',
       arguments => [$address],
       default_reply => [502, 'Command not implemented']
      );
    return;
}

=pod

=head2 EXPN

Command not implemented, deprecated by RFC 2821

Handler takes no argument.

=cut

sub turn
{
    # deprecated in RFC 2821
    my($self) = @_;
    $self->reply(502, 'Command not implemented');
    $self->make_event
      (
       name => 'TURN',
       default_reply => [502, 'Command not implemented']
      );
    return;
}

=pod

=head2 VRFY

Command not yet implemented.

Handler takes address as argument.

=cut

sub vrfy
{
    my($self, $address) = @_;
    $self->make_event
      (
       name => 'VRFY',
       arguments => [$address],
       default_reply => [502, 'Command not implemented']
      );
    return;
}

=pod

=head2 HELP

Command not yet implemented.

Handler takes a command name as argument.

=cut

sub help
{
    my($self, $command) = @_;
    $self->make_event
      (
       name => 'HELP',
       arguments => [$command],
       default_reply => [502, 'Command not implemented']
      );
    return;
}

=pod

=head2 MAIL

Handler takes address as argument. On success, engage the forward path
step and keep the given address for later use (get it with
get_sender() method).

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

=pod

=head2 RCPT

Handler takes address as argument. On success, engage the mail data path step and
push the given address into the recipient list for later use (get it
with get_recipients() method).

=cut

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

=pod

=head2 SEND

Command not implemented.

Handler takes no argument.

=cut

# we overwrite a perl command... we shouldn't need it in this class,
# but take care.
sub send
{
    my($self) = @_;
    $self->make_event
      (
       name => 'SEND',
       default_reply => [502, 'Command not implemented']
      );
    return;
}

=pod

=head2 SOML

Command not implemented.

Handler takes no argument.

=cut

sub soml
{
    my($self) = @_;
    $self->make_event
      (
       name => 'SOML',
       default_reply => [502, 'Command not implemented']
      );
    return;
}

=pod

=head2 SAML

Command not implemented.

Handler takes no argument.

=cut

sub saml
{
    my($self) = @_;
    $self->make_event
      (
       name => 'SAML',
       default_reply => [502, 'Command not implemented']
      );
    return;
}

=pod

=head2 DATA

This handler is called after the final . sent by client. It takes data
as argument in a scalar reference. You should queue the message and
reply with the queue ID.

=head2 DATA-INIT

This handler is called before enter in the "waiting for data" step. The
default success reply is a 354 code telling the client to send the
mail content.

=head2 DATA-PART

This handler is called at each parts of mail content sent. It takes as
argument a scalar reference to the part of data received. It is
deprecated to change the contents of this scalar.

=cut

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

    $self->{last_chunk} = '';
    $self->make_event
      (
       name => 'DATA-INIT',
       on_success => sub {$self->next_input_to(\&data_part);},
       success_reply => [354, 'Start mail input; end with <CRLF>.<CRLF>']
      );

    return;
}

# Because data is cutted into pieces (4096 bytes), we have to search
# "\r\n.\r\n" sequence in 2 consecutive pieces. $self->{last_chunk}
# contains the last 5 bytes.
sub data_part
{
    my($self, $data) = @_;

    # search for end of data indicator
    if("$self->{last_chunk}$data" =~ /\r?\n\.\r?\n/s )
    {
        my $more_data = $';
        if(length $more_data)
        {
            # Client sent a command after the end of data indicator ".".
            if(!$self->{data_handle_more_data})
            {
                $self->reply(453, "Command received prior to completion of".
                                  " previous command sequence");
                return;
            }
        }
        
        # RFC 821 compliance.
        ($data = "$self->{last_chunk}$data") =~ s/(\r?\n)\.\r?\n(QUIT\r?\n)?$/$1/s;
        $self->{_data} .= $data;
        # RFC 2821 by the letter
        $self->{_data} =~ s/^\.(.+\015\012)(?!\n)/$1/gm;
        return $self->data_finished($more_data);
    }

    my $tmp = $self->{last_chunk};
    $self->{last_chunk} = substr $data, -5;
    $data = $tmp . substr $data, 0, -5;
    $self->make_event
      (
       name => 'DATA-PART',
       arguments => [\$data],
       on_success => sub
       {
           $self->{_data} .= $data;
           # please, recall me soon !
           $self->next_input_to(\&data_part);
       },
       success_reply => '', # don't send any reply !
      );

    return;
}

sub data_finished
{
    my($self, $more_data) = @_;

    $self->make_event
    (
        name => 'DATA',
        arguments => [\$self->{_data}],
        success_reply => [250, 'message sent'],
    );

    # reinitiate the connection
    $self->step_reverse_path(1);
    $self->step_forward_path(0);
    $self->step_maildata_path(0);

    # if more data, handle it
    if($more_data)
    {
        return $self->{process_operation}($self, $more_data);
    }
    else
    {
        return;
    }
}

=pod

=head2 RSET

Handler takes no argument.

On success, all step are initialized and sender/recipients list are
flushed.

=cut

sub rset
{
    my($self) = @_;

    $self->make_event
    (
        name => 'RSET',
        on_success => sub
        {
            $self->step_reverse_path(1)
              if($self->step_reverse_path());
            $self->step_forward_path(0);
            $self->step_maildata_path(0);
        },
        success_reply => [250, 'Requested mail action okay, completed'],
    );

    return;
}

=pod

=head2 QUIT

Handler takes no argument.

Connection is closed after this command. This behavior may change in
future, you will probably be able to control the closing of
connection.

=cut

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

=pod

=head1 SEE ALSO

Please, see L<Net::Server::Mail>, L<Net::Server::Mail::ESMTP>
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

<<<<<<< HEAD:lib/Net/Server/Mail/SMTP.pm
Copyright (C) 2002 - Olivier Poitrey
=======
Copyright (C) 2002 - Olivier Poitrey, 2007 - Xavier Guimard
>>>>>>> new/master:lib/Net/Server/Mail/SMTP.pm

=cut

1;
