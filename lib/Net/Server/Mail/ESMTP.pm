package Net::Server::Mail::ESMTP;

use 5.006;
use strict;
use Carp;
use base qw(Net::Server::Mail::SMTP);

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

    $self->make_event
    (
        name => 'EHLO',
        arguments => [$hostname, \@extends],
        on_success => sub
        {
            # conforming to RFC, HELO ensure "that both the SMTP client and the
            # SMTP server are in the initial state"
            $self->{extend_mode} = 1;
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

sub rset
{
    my($self) = @_;
    $self->{extend_mode} = 0;
    $self->SUPER::rset();
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

1;
