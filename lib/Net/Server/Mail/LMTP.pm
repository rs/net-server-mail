package Net::Server::Mail::LMTP;

use 5.006;
use strict;
use base qw(Net::Server::Mail::ESMTP);

sub init
{
    my($self, @args) = @_;
    my $rv = $self->SUPER::init(@args);
    return $rv unless $rv eq $self;

    $self->del_cmd('HELO');
    $self->del_cmd('EHLO');

    $self->set_cmd(LHLO => \&lhlo);

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
            success_reply => [250, 'Requested mail action okay, completed'],
            failure_reply => [550, "$forward_path Failed"],
        );
    }

    return;
}

1;
