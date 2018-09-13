package Net::Server::Mail::ESMTP::8BITMIME;

use 5.006;
use strict;
use warnings;
use base qw(Net::Server::Mail::ESMTP::Extension);

our $VERSION = "0.24";

sub keyword {
    return '8BITMIME';
}

sub option {
    return ( [ 'MAIL', BODY => \&option_mail_body ], );
}

sub option_mail_body {
    return;
}

1;
