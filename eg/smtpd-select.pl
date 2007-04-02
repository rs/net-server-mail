#!/usr/bin/perl -w
# 
# Olivier Poitrey <rs@rhapsodyk.net>
# 8th november 2002
# 
# smtpd-select.pl: A dummy SMTP server using Net::Server::Mail and
# IO::Select.

require 5.006;
use strict;
use POSIX qw(setsid);
use Getopt::Std;
use IO::Socket;
use IO::Select;
use Net::Server::Mail::ESMTP;


my %opts = (p => 25, h => 'localhost');
getopts('p:h:', \%opts);

# become a daemon
fork and exit;
setsid;

# start to listen
my $server = new IO::Socket::INET
(
    Listen      => 1,
    LocalPort   => $opts{p},
    LocalHost   => $opts{h},
) or die "can't listen $opts{h}:$opts{p}";
my $select = new IO::Select $server;

my(@ready, $fh, %session_pool);
while(@ready = $select->can_read)
{
    foreach $fh (@ready)
    {
        if($fh == $server)
        {
            my $new = $server->accept();
            $select->add($new);
            $new->blocking(0);
            my $smtp = new Net::Server::Mail::ESMTP socket => $new
              or die "can't start server on port $opts{p}";
            $smtp->register('Net::Server::Mail::ESMTP::PIPELINING');
            $smtp->register('Net::Server::Mail::ESMTP::8BITMIME');
            $smtp->banner();
            $session_pool{$new} = $smtp;
        }
        else
        {
            my $operation = join '', <$fh>;
            my $rv = $session_pool{$fh}->process_once($operation);
            if(defined $rv)
            {
                $select->remove($fh);
                delete $session_pool{$fh};
                $fh->close();
            }
        }
    }
}
