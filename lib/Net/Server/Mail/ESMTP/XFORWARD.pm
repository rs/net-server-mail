package Net::Server::Mail::ESMTP::XFORWARD;

use 5.006;
use strict;
use warnings;
use Scalar::Util qw(weaken);

our $VERSION = '0.22';

use base qw(Net::Server::Mail::ESMTP::Extension);

sub init {
    my ( $self, $parent ) = @_;
    $self->{parent} = $parent;
    weaken( $self->{parent} );
    return $self;
}

sub verb {
    my $self = shift;
    return [ 'XFORWARD' => 'xforward' ];
}

sub keyword {
    return 'XFORWARD';
}

sub parameter {
    my $self = shift;
    return "NAME ADDR PROTO HELO SOURCE";
}

sub xforward {
    my $self = shift;
    my $args = shift;
    my %h    = ( $args =~ /(NAME|ADDR|PROTO|HELO|SOURCE)=([^\s]+)\s*/g );
    $args =~ s/(?:NAME|ADDR|PROTO|HELO|SOURCE)=[^\s]+\s*//g;
    if ( $args !~ /^\s*$/ ) {
        $args =~ s/=.*$//;
        $self->reply( 501, "5.5.4 Bad XFORWARD attribute name: $args" );
    }
    else {
        $self->{"xforward"}->{ lc($_) } = $h{$_} foreach ( keys %h );
        $self->make_event(
            name       => 'XFORWARD',
            arguments  => [ $self->{"xforward"} ],
            on_success => sub {

                #my $buffer = $self->step_forward_path();
                #$buffer = [] unless ref $buffer eq 'ARRAY';
                #push(@$buffer, $address);
                #$self->step_forward_path($buffer);
                #$self->step_maildata_path(1);
            },
            success_reply => [ 250, "OK" ],
            failure_reply => [ 550, 'Failure' ],
        );
    }
    return;
}

sub get_forwarded_values {
    my $self = shift;
    return $self->{xforward};
}

sub get_forwarded_name {
    my $self = shift;
    return $self->{xforward}->{name};
}

sub get_forwarded_address {
    my $self = shift;
    return $self->{xforward}->{addr};
}

sub get_forwarded_proto {
    my $self = shift;
    return $self->{xforward}->{proto};
}

sub get_forwarded_helo {
    my $self = shift;
    return $self->{xforward}->{helo};
}

sub get_forwarded_source {
    my $self = shift;
    return $self->{xforward}->{source};
}

# New subroutines in Net::Server::Mail::ESMTP space
*Net::Server::Mail::ESMTP::xforward              = \&xforward;
*Net::Server::Mail::ESMTP::get_forwarded_values  = \&get_forwarded_values;
*Net::Server::Mail::ESMTP::get_forwarded_name    = \&get_forwarded_name;
*Net::Server::Mail::ESMTP::get_forwarded_address = \&get_forwarded_address;
*Net::Server::Mail::ESMTP::get_forwarded_proto   = \&get_forwarded_proto;
*Net::Server::Mail::ESMTP::get_forwarded_helo    = \&get_forwarded_helo;
*Net::Server::Mail::ESMTP::get_forwarded_source  = \&get_forwarded_source;

1;
__END__

=head1 NAME

Net::Server::Mail::ESMTP::XFORWARD - A module to add support to the XFORWARD command in Net::Server::Mail::ESMTP

=head1 SYNOPSIS

    use Net::Server::Mail::ESMTP;
    
    my @local_domains = qw(example.com example.org);
    my $server = IO::Socket::INET->new( Listen => 1, LocalPort => 25 );
    
    my $conn;
    while($conn = $server->accept)
    {
        my $esmtp = Net::Server::Mail::ESMTP->new( socket => $conn );
        
        # activate XFORWARD extension if remote client is localhost
        $esmtp->register('Net::Server::Mail::ESMTP::XFORWARD')
           if($server->get_property('peeraddr') =~ /^127/);
        # adding some handlers
        $esmtp->set_callback(RCPT => \&validate_recipient);
        # adding XFORWARD handler
        $esmtp->set_callback(XFORWARD => \&xforward);
        $esmtp->process();
        $conn->close();
    }
    
    sub xforward {
        my $self = shift;
        # Reject non IPV4 addresses
        return 0 unless( $self->get_forwarded_address =~ /^\d+\.\d+\.\d+\.\d+$/ );
        1;
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
        elsif(not(grep $domain eq $_, @local_domains) && $session->get_forwarded_addr != "10.1.1.1")
        {
            return(0, 554, "$recipient: Recipient address rejected: Relay access denied");
        }
    
        return(1);
    }

=head1 DESCRIPTION

When using a Net::Server::Mail::ESMTP script inside a MTA and not in front of
Internet, values like client IP address are not accessible to the script and
when the script returns mail to another instance of smtpd daemon, it logs
"localhost" as incoming address. To solve this problem, some administrators use
the XFORWARD command. This module gives the ability to read and store XFORWARD
information.

=head2 METHODS

These methods return the values set by the upstream MTA without modifying them
so they can be set to undef or "[UNVAILABLE]". See Postfix documentation for
more.

=over

=item * get_forwarded_values : returns a hash reference containing all values forwarded (keys in lower case).

=item * get_forwarded_name : returns the up-stream hostname. The hostname may
be a non-DNS hostname.

=item * get_forwarded_address : returns the up-stream network address. Address
information is not enclosed with []. The address may be a non-IP address.

=item * get_forwarded_source : returns LOCAL or REMOTE.

=item * get_forwarded_helo : returns the hostname that the up-stream host
announced itself. It may be a non-DNS hostname.

=item * get_forwarded_proto : returns the mail protocol for receiving mail from
the up-stream host. This may be an SMTP or non-SMTP protocol name of up to 64
characters.

=back

=head1 SEE ALSO

L<Net::Server::Mail::ESMTP>, L<http://www.postfix.org/XFORWARD_README.html>

=head1 AUTHOR

Xavier Guimard, E<lt>x.guimard@free.frE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Xavier Guimard

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.6.4 or,
at your option, any later version of Perl 5 you may have available.

