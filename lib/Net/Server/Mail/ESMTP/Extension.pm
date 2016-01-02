package Net::Server::Mail::ESMTP::Extension;

use 5.006;
use strict;
use warnings;

our $VERSION = "0.14";

=pod

=head1 NAME

Net::Server::Mail::ESMTP::Extension - The base class for ESMTP extension system

=head1 DESCRIPTION

=cut

sub new {
    my ( $proto, $parent ) = @_;
    my $class = ref $proto || $proto;
    my $self = {};
    bless( $self, $class );
    return $self->init($parent);
}

=pod

=head1 init

  ($self) = $obj->init($parent);

You can override this method to do something at the
initialisation. The method takes the $smtp object as parameter.

=cut

sub init {
    my ( $self, $parent ) = @_;
    return $self;
}

=pod

=head1 verb

=cut

sub verb {
    return ();
}

=pod

=head1 keyword

=cut

sub keyword {
    return 'XNOTOVERLOADED';
}

=pod

=head1 parameter

=cut

sub parameter {
    return ();
}

=pod

=head1 option

=cut

sub option {
    return ();
}

=pod

=head1 reply

=cut

sub reply {
    return ();
}

1;
