package Net::Server::Mail::LMTP;

use 5.006;
use strict;
use base qw(Net::Server::Mail::ESMTP);

our $VERSION = "0.16";

=pod

=head1 NAME

Net::Server::Mail::LMTP - A module to implement the LMTP protocole
  

=head1 SYNOPSIS

    use Net::Server::Mail::LMTP;

    my @local_domains = qw(example.com example.org);
    my $server = new IO::Socket::INET Listen => 1, LocalPort => 25;

    my $conn;
    while($conn = $server->accept)
    {
        my $esmtp = new Net::Server::Mail::LMTP socket => $conn;
        # adding some handlers
        $esmtp->set_callback(RCPT => \&validate_recipient);
        $esmtp->set_callback(DATA => \&queue_message);
        $esmtp->process();
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

This class implement the LMTP (RFC 2033) protocol.

This class inherit from Net::Server::Mail::ESMTP. Please see
L<Net::Server::Mail::ESMTP> for documentation of common methods.

=cut

sub init
{
    my($self, @args) = @_;
    my $rv = $self->SUPER::init(@args);
    return $rv unless $rv eq $self;

    $self->undef_verb('HELO');
    $self->undef_verb('EHLO');

    $self->def_verb(LHLO => 'lhlo');

    # Required by RFC
    $self->register('Net::Server::Mail::ESMTP::PIPELINING');

    return $self;
}

sub get_protoname
{
    return 'LMTP';
}

=pod

=head1 EVENTS

Descriptions of callback who's can be used with set_callback
method. All handle takes the Net::Server::Mail::ESMTP object as first
argument and specific callback's arguments.

=head2 LHLO

Same as ESMTP EHLO, please see L<Net::Server::Mail::ESMTP>.

=cut

sub lhlo
{
    my($self, $hostname) = @_;

    unless(defined $hostname && length $hostname)
    {
        $self->reply(501, 'Syntax error in parameters or arguments');
        return;
    }

    my $response = $self->get_hostname . ' Service ready';

    my @extends;
    foreach my $extend ($self->get_extensions)
    {
        push(@extends, join(' ', $extend->keyword, $extend->parameter));
    }

    $self->extend_mode(1);
    $self->make_event
    (
        name => 'LHLO',
        arguments => [$hostname, \@extends],
        on_success => sub
        {
            # according to the RFC, LHLO ensures "that both the SMTP client
            # and the SMTP server are in the initial state"
            $self->{extend_mode} = 1;
            $self->step_reverse_path(1);
            $self->step_forward_path(0);
            $self->step_maildata_path(0);
        },
        success_reply => [250, [$response, @extends]],
    );

    return;
}

=pod

=head2 DATA

Overide the default DATA event by a per recipient response. It will
be called for each recipients with data (in a scalar reference) as 
first argument followed by the current recipient.

=cut

sub data_finished
{
    my($self) = @_;
    
    my $recipients = $self->step_forward_path();

    foreach my $forward_path (@$recipients)
    {
        $self->make_event
        (
            name => 'DATA',
            arguments => [\$self->{_data}, $forward_path],
            success_reply => [250, 'Ok'],
            failure_reply => [550, "$forward_path Failed"],
        );
    }

    # reinitiate the connection
    $self->step_reverse_path(1);
    $self->step_forward_path(0);
    $self->step_maildata_path(0);

    return;
}

=pod

=head1 SEE ALSO

Please, see L<Net::Server::Mail>, L<Net::Server::Mail::SMTP>
and L<Net::Server::Mail::ESMTP>.

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
