package Net::Server::Mail::LMTP;

use 5.006;
use strict;
use base qw(Net::Server::Mail::ESMTP);

sub init
{
    my($self, @args) = @_;
    my $rv = $self->SUPER::init(@args);
    return $rv unless $rv eq $self;

    $self->undef_verb('HELO');
    $self->undef_verb('EHLO');

    $self->def_verb(LHLO => 'lhlo');

    return $self;
}

sub lhlo
{
    shift->ehlo(@_);
}

sub data_finished
{
    my($self, $data) = @_;
    
    my $recipients = $self->step_forward_path();

    foreach my $forward_path (@$recipients)
    {
        $self->make_event
        (
            name => 'DATA',
            arguments => [$data, $forward_path],
            success_reply => [250, 'Ok'],
            failure_reply => [550, "$forward_path Failed"],
        );
    }

    return;
}

1;
