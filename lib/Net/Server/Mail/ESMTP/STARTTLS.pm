#
# Copyright 2013 Mytram <r.mytram@gmail.com>. All rights reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#

package Net::Server::Mail::ESMTP::STARTTLS;

use 5.006;
use strict;
use warnings;

# IO::Socket::SSL v1.831 fixed a readline() behavioural deviation in
# list context on nonblocking sockets, which caused Net::Server::Mail
# to fail to read commands correctly

use IO::Socket::SSL 1.831;
use Net::Server::Mail::ESMTP::Extension;
our @ISA = qw(Net::Server::Mail::ESMTP::Extension);

our $VERSION = 0.23;

use constant {
    REPLY_READY_TO_START => 220,
    REPLY_SYNTAX_ERROR   => 502,
    REPLY_NOT_AVAILABLE  => 454,
};

# https://tools.ietf.org/html/rfc2487

sub verb {
    my $self = shift;
    return ( [ 'STARTTLS' => \&starttls ] );
}

sub keyword { 'STARTTLS' }

# Return a non undef to signal the server to close the socket.
sub starttls {
    my $server = shift;
    my $args   = shift;

    if ($args) {

        # No parameter verb
        $server->reply( REPLY_SYNTAX_ERROR,
            'Syntax error (no parameters allowed)' );
        return;
    }

    my $ssl_config = $server->{options}{ssl_config}
      if exists $server->{options}{ssl_config};
    if ( !$ssl_config || ref $ssl_config ne 'HASH' ) {
        $server->reply( REPLY_NOT_AVAILABLE,
            'TLS not available due to temporary reason' );
        return;
    }

    $server->reply( REPLY_READY_TO_START, 'Ready to start TLS' );

    my $ssl_socket = IO::Socket::SSL->start_SSL( $server->{options}{socket},
        %$ssl_config, SSL_server => 1, );

    # Use SSL_startHandshake to control nonblocking behaviour
    # See perldoc IO::Socket::SSL for more

    if ( !$ssl_socket || !$ssl_socket->isa('IO::Socket::SSL') ) {
        $server->reply( REPLY_NOT_AVAILABLE,
                'TLS not available due to temporary reason ['
              . IO::Socket::SSL::errstr()
              . ']' );
        return 0;    # to single the server to close the socket
    }

    my $ref = $server->{callback}->{STARTTLS};
    if ( defined $ref && ref $ref eq 'ARRAY' && ref $ref->[0] eq 'CODE' ) {
        my $code = $ref->[0];
        &$code($server);
    }

    return ();
}

1;

=head1 NAME

Net::Server::Mail::ESMTP::STARTTLS - A module to support the STARTTLS command in Net::Server::Mail::ESMTP

=head1 SYNOPSIS

   use strict;
   use Net::Server::Mail::ESMTP;

   my @local_domains = qw(example.com example.org);
   my $server = IO::Socket::INET->new( Listen => 1, LocalPort => 25 );

   my $conn;
   while($conn = $server->accept)
   {
       my $esmtp = Net::Server::Mail::ESMTP->new(
            socket => $conn,
            SSL_config => {
                SSL_cert_file => 'your_cert.pem',
                SSL_key_file => 'your_key.key',
                # Any other options taken by IO::Socket::SSL
            }
       );
       
       # activate some extensions
       $esmtp->register('Net::Server::Mail::ESMTP::STARTTLS');
       
       # adding optional STARTTLS handler
       $esmtp->set_callback(STARTTLS => \&tls_started);
       $esmtp->process();
       $conn->close();
   }
   
   sub tls_started {
       my ($session) = @_;

       # Now, allow authentication
       $session->register('Net::Server::Mail::ESMTP::AUTH');
   }

=head1 DESCRIPTION

This module conducts a TLS handshake with the client upon receiving
the STARTTLS command. It uses IO::Socket::SSL, requiring 1.831+, to
perform the handshake and secure traffic.

An additional option, SSL_config, is passed to
Net::Server::Mail::ESMTP's constructor. It contains options for
IO::Socket::SSL's constructor. Please refer to IO::Socket::SSL's
perldoc for details.

=head1 SEE ALSO

Please, see L<Net::Server::Mail>

=head1 AUTHOR

This module has been written by Xavier Guimard <x.guimard@free.fr> using libs
written by:

=over

=item Mytram <rmytram@gmail.com>

=item Dan Moore C<< <dan at moore.cx> >>

=back

=head1 AVAILABILITY

Available on CPAN.

anonymous Git repository:

git clone git://github.com/rs/net-server-mail.git

Git repository on the web:

L<https://github.com/rs/net-server-mail>

=head1 BUGS

Please use CPAN system to report a bug (http://rt.cpan.org/).

=head1 LICENSE AND COPYRIGHT

=over

=item Copyright (C) 2009 - Dan Moore <dan at moore.cx>

=item Copyright (C) 2013 - Mytram <rmytram@gmail.com>

=item Copyright (C) 2013 - Xavier Guimard <x.guimard@free.fr>

=back

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut
