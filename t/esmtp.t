use strict;
use Test::More;
use IO::Socket;
use Net::SMTP;

plan tests => 10;
use_ok('Net::Server::Mail::ESMTP');

my $server_port = 2525;
my $server;

while ( not defined $server && $server_port < 4000 ) {
    $server = new IO::Socket::INET(
        Listen    => 1,
        LocalPort => ++$server_port,
    );
}

my $pid = fork;
if ( !$pid ) {
    while ( my $conn = $server->accept ) {
        my $m = new Net::Server::Mail::ESMTP
          socket       => $conn,
          idle_timeout => 5
          or die "can't start server on port $server_port";
        $m->register('Net::Server::Mail::ESMTP::PIPELINING');
        $m->register('Net::Server::Mail::ESMTP::XFORWARD');
        $m->process;
    }
}

my $smtp = new Net::SMTP "localhost:$server_port", Debug => 0;
ok( defined $smtp );

ok( $smtp->mail("test\@bla.com") );
ok( !$smtp->mail("test\@bla.com") );
ok( $smtp->to('postmaster') );
ok( $smtp->to('postmaster') );
ok( $smtp->data );
ok( $smtp->datasend('To: postmaster') );
ok( $smtp->dataend );
ok( $smtp->quit );

kill 1, $pid;
wait;
