package Net::Server::Mail::ESMTP;

use 5.006;
use strict;
use Carp;
use base qw(Net::Server::Mail::SMTP);

our $VERSION = "0.16";

=pod

=head1 NAME

Net::Server::Mail::ESMTP - A module to implement the ESMTP protocole

=head1 SYNOPSIS

    use Net::Server::Mail::ESMTP;

    my @local_domains = qw(example.com example.org);
    my $server = new IO::Socket::INET Listen => 1, LocalPort => 25;

    my $conn;
    while($conn = $server->accept)
    {
        my $esmtp = new Net::Server::Mail::ESMTP socket => $conn;
        # activate some extensions
        $esmtp->register('Net::Server::Mail::ESMTP::8BITMIME');
        $esmtp->register('Net::Server::Mail::ESMTP::PIPELINING');
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

This class implement the ESMTP (RFC 2821) protocol.

This class inherit from Net::Server::Mail::SMTP. Please see
L<Net::Server::Mail::SMTP> for documentation of common methods.

=head1 METHODS

ESMTP specific methods.

=cut

sub init
{
    my($self, @args) = @_;
    my $rv = $self->SUPER::init(@args);
    return $rv unless $rv eq $self;

    $self->def_verb(EHLO => 'ehlo');

    $self->{extend_mode} = 0;

    return $self;
}

sub get_protoname
{
    return 'ESMTP';
}

sub get_extensions
{
    my($self) = @_;
    return(@{$self->{extensions} || []});
}

=pod

=head2 register

Activate an ESMTP extension. This method takes a module's name as
argument. This module must implement certain methods. See
L<Net::Server::Mail::ESMTP::Extension> for more details.

=cut

sub register
{
    my($self, $class) = @_;
    # try to import class
    eval "require $class" or croak("can't register module `$class'");
    # test mandatory methods
    foreach my $method (qw(new verb keyword parameter option reply))
    {
        confess("Extension class `$class' doesn't implement mandatory method `$method'")
            unless($class->can($method));
    }

    my $extend = new $class $self or return;
    foreach my $verb_def ($extend->verb)
    {
        $self->def_verb(@$verb_def) or return;
    }

    foreach my $option_def ($extend->option)
    {
        $self->sub_option(@$option_def);
    }

    foreach my $reply_def ($extend->reply)
    {
        $self->sub_reply(@$reply_def);
    }

    push(@{$self->{extensions}}, $extend);
    return 1;
}

sub sub_option
{
    my($self, $verb, $option_key, $code) = @_;
    confess("can't subscribe to option for verb `$verb'")
        unless($verb eq 'MAIL' or $verb eq 'RCPT');
    confess("allready subscribed `$option_key'")
        if(exists $self->{xoption}->{$verb}->{$option_key});
    $self->{xoption}->{$verb}->{$option_key} = $code;
}

sub sub_reply
{
    my($self, $verb, $code) = @_;
    confess("trying to subscribe to an unsupported verb `$verb'")
        unless(grep($verb eq $_, $self->list_verb));
    push(@{$self->{xreply}->{$verb}}, $code);
}

sub extend_mode
{
    my($self, $mode) = @_;
    $self->{extend_mode} = $mode;
    for my $extend (@{$self->{extensions}})
    {
        if($extend->can('extend_mode'))
        {
            $extend->extend_mode($mode);
        }
    }
}

=pod

=head1 EVENTS

Descriptions of callback who's can be used with set_callback
method. All handle takes the Net::Server::Mail::ESMTP object as first
argument and specific callback's arguments.

=head2 EHLO

Takes the hostname given as argument. Engage the reverse path step on
success. RFC 2821 require thats EHLO command return the list of
supported extension. Default success reply implement this, so it is
deprecated to override this reply.

You can rebuild extension list with get_extensions() method.

Exemple:

    my @extends;
    foreach my $extend ($esmtp->get_extensions())
    {
        push(@extends, join(' ', $extend->keyword(), $extend->parameter()));
    }
    my $extends_string = join("\n", @extends);

=cut

sub ehlo
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
        name => 'EHLO',
        arguments => [$hostname, \@extends],
        on_success => sub
        {
            # according to the RFC, EHLO ensures "that both the SMTP client
            # and the SMTP server are in the initial state"
            $self->step_reverse_path(1);
            $self->step_forward_path(0);
            $self->step_maildata_path(0);
        },
        success_reply => [250, [$response, @extends]],
    );

    return;
}

sub helo
{
    my($self, $hostname) = @_;
    $self->{extend_mode} = 0;
    $self->SUPER::helo($hostname);
}

sub handle_options
{
    my($self, $verb, $address, @options) = @_;

    if(@options && !$self->{extend_mode})
    {
        $self->reply(555, "Unsupported option: $options[0]");
        return 0;
    }

    for(my $i = $#options; $i >= 0; $i--)
    {
        my($key, $value) = split(/=/, $options[$i], 2);
        my $handler = $self->{xoption}->{$verb}->{$key};
        if(defined $handler)
        {
            no strict "refs";
            &$handler($self, $verb, $address, $key, $value);
        }
        else
        {
            $self->reply(555, "Unsupported option: $key");
            return 0;
        }
    }
    
    return 1;
}

sub handle_reply
{
    my($self, $verb, $success, $code, $msg) = @_;

    if($self->{extend_mode} && exists $self->{xreply}->{$verb})
    {
        foreach my $handler (@{$self->{xreply}->{$verb}})
        {
            ($code, $msg) = &$handler($self, $verb, $success, $code, $msg);
        }
    }

    $self->reply($code, $msg);
}

=pod

=head1 SEE ALSO

Please, see L<Net::Server::Mail>, L<Net::Server::Mail::SMTP>
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
