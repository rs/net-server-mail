package Net::Server::Mail::ESMTP::Extension;

use 5.006;
use strict;

sub new
{
    my($proto) = @_;
    my $class  = ref $proto || $proto;
    my $self   = {};
    bless($self, $class);
    return $self;
}

sub verb
{
    return ();
}

sub keyword
{
    return 'XNOTOVERLOADED';
}

sub parameter
{
    return ();
}

sub option
{
    return ();
}

sub reply
{
    return ();
}

1;
