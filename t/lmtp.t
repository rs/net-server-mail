use strict;
use Test;
use IO::Socket;
eval('use Net::LMTP');

if($@)
{
    print STDERR "\n*** You don't seem to have Net::LMTP instaled on your system\n";
    plan tests => 0;
    exit
}

plan tests => 11;

use Net::Server::Mail::LMTP;
ok(1);

my $server_port = 2525;
my $server;

while(not defined $server && $server_port < 4000)
{
    $server = new IO::Socket::INET
    (
        Listen      => 1,
        LocalPort   => ++$server_port,
    );
}

my $pid = fork;
if(!$pid)
{
    while(my $conn = $server->accept)
    {
        my $m = new Net::Server::Mail::LMTP socket => $conn, idle_timeout => 5
            or die "can't start server on port 2525";
        $m->set_callback('DATA', sub {return $_[1] !~ /bad/});
        $m->process;
    }
}

my $lmtp = new Net::LMTP 'localhost', $server_port, Debug => 0;
ok(defined $lmtp);

ok($lmtp->mail("test\@bla.com"));
ok(!$lmtp->mail("test\@bla.com"));
ok($lmtp->to('bad'));
ok($lmtp->to('postmaster'));
ok($lmtp->data);
ok($lmtp->datasend('To: postmaster'));
ok(!$lmtp->dataend);
ok($lmtp->response);
ok($lmtp->quit);

kill 1, $pid;
wait;
