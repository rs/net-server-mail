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
use Net::SMTP;


my %opts = (p => 25, h => 'localhost', r => '', d => 0);
getopts('dp:h:r:', \%opts);

my $remote = $opts{r};
unless($remote)
{
    print STDERR "Needs a remote server (-r option)\n";
    exit 1;
}

unless($opts{d})
{
    # become a daemon
    fork and exit;
    setsid;
}

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
            $new->blocking(0);
            my $smtpout = new Net::SMTP $remote, Debug => $opts{d} or do
            {
                $new->print("Service unavailable\n");
                $new->close();
            };
            my $smtpin = new Net::Server::Mail::ESMTP socket => $new
              or die "can't start server on port $opts{p}";
            $smtpin->register('Net::Server::Mail::ESMTP::PIPELINING');
            $smtpin->register('Net::Server::Mail::ESMTP::8BITMIME');
            $smtpin->set_callback(HELO => \&gate_helo, $smtpout);
            $smtpin->set_callback(MAIL => \&gate_mail, $smtpout);
            $smtpin->set_callback(RCPT => \&gate_rcpt, $smtpout);
            $smtpin->set_callback('DATA-INIT' => \&gate_datainit, $smtpout);
            $smtpin->set_callback('DATA-PART' => \&gate_datapart, $smtpout);
            $smtpin->set_callback(DATA => \&gate_dataend, $smtpout);
            $smtpin->set_callback(QUIT => \&gate_quit, $smtpout);
            $smtpin->banner();
            $session_pool{$new} = $smtpin;
            $select->add($new);
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

sub gate_helo
{
    # Net::SMTP send HELO by himself
    return;
}

sub gate_mail
{
    my($session, $address) = @_;
    my $smtpout = $session->get_context();
    return $smtpout->mail($address);
}

sub gate_rcpt
{
    my($session, $address) = @_;
    my $smtpout = $session->get_context();
    return $smtpout->to($address);
}

sub gate_datainit
{
    my($session) = @_;
    my $smtpout = $session->get_context();
    return $smtpout->data();
}

sub gate_datapart
{
    my($session, $dataref) = @_;
    my $smtpout = $session->get_context();
    return $smtpout->datasend($$dataref);
}

sub gate_dataend
{
    my($session, $dataref) = @_;
    my $smtpout = $session->get_context();
    return $smtpout->dataend();
}

sub gate_quit
{
    my($session) = @_;
    my $smtpout = $session->get_context();
    return $smtpout->quit();
}
