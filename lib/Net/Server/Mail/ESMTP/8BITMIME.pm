package Net::Server::Mail::ESMTP::8BITMIME;

use 5.006;
use strict;
use base qw(Net::Server::Mail::ESMTP::Extension);

sub keyword
{
    return '8BITMIME';
}

sub option
{
    return
    (
        ['MAIL', BODY => \&option_mail_body],
    );
}
