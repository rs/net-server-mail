#use strict;
#use warnings;

use IO::Socket::INET;
use Net::Server::Mail::ESMTP;
use Net::Server::Mail::ESMTP::STARTTLS;
use IO::Socket::SSL qw(1.831 SSL_VERIFY_NONE);

use Net::SMTP;
use Net::Cmd;

use Test::Most tests => 15;

use constant {
	OK       => 250,
	DEFER    => 450,
	NORETRY  => 250, # Drop the message silently so that it doesn't bounce
};

use strict;
use warnings;

my (@tests, @socks);

my $host = '127.0.0.1';
my $port = 9988;
my $sender = 'sender@example.com';
my $recip1 = 'recip1@example.com';
my $recip2 = 'recip2@example.com';

my $data =<< "EOS";
Subject: test message
From: <$sender>
To: <$recip1>
To: <$recip2>

hello world.

EOS

push @tests, [ 'STARTTLS support', sub {
	my $s = Net::SMTP->new($host, Port => $port, Hello => 'localhost');

	$s->peerhost eq $host
		or die "peerport is not $host";
	$s->peerport eq $port
		or die "peerport is not $port";

	defined $s->supports('STARTTLS', 500, [ "'STARTTLS' is not supported" ])
		or die "starttls is not supported";

	$s->command("STARTTLS")->response == Net::Cmd::CMD_OK
		or die "Cannot start command";

	# cause the server to close the connetion
	$s->command("hello");
	$s->command("bye");

	$s->quit;

       return 1;
}, {
}];


push @tests, [ 'STARTTLS invalid parameters', sub {
	my $s = Net::SMTP->new($host, Port => $port, Hello => 'localhost');

	$s->peerhost eq $host
		or die "peerport is not $host";
	$s->peerport eq $port
		or die "peerport is not $port";

	defined $s->supports('STARTTLS', 500, [ "'STARTTLS' is not supported" ])
		or die "starttls is not supported";

	$s->command("STARTTLS HELLO WORLD")->response == Net::Cmd::CMD_ERROR
		or die "Invalid paramter accepted";

	$s->quit;

       return 1;
}, {
}];

push @tests, [ 'STARTTLS handshake', sub {
	my $s = Net::SMTP->new($host, Port => $port, Hello => 'localhost');

	$s->peerhost eq $host
		or die "peerport is not $host";
	$s->peerport eq $port
		or die "peerport is not $port";

	defined $s->supports('STARTTLS', 500, [ "'STARTTLS' is not supported" ])
		or die "starttls is not supported";

	$s->command("STARTTLS")->response == Net::Cmd::CMD_OK
		or die "Cannot start command";

	my $rv = IO::Socket::SSL->start_SSL($s,
		SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
	);

	(defined $rv && ref $rv eq 'IO::Socket::SSL')
		or die "TLS handeshake failed";

	$s->close;

	return 1;
}, {
}];

push @tests, [ 'STARTTLS handshake failed in SSL_VERIFY_PEER', sub {
	my $s = Net::SMTP->new($host, Port => $port, Hello => 'localhost');

	$s->peerhost eq $host
		or die "peerport is not $host";
	$s->peerport eq $port
		or die "peerport is not $port";

	defined $s->supports('STARTTLS', 500, [ "'STARTTLS' is not supported" ])
		or die "starttls is not supported";

	$s->command("STARTTLS")->response == Net::Cmd::CMD_OK
		or die "Cannot start command";

	my $rv = IO::Socket::SSL->start_SSL($s,
		SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_PEER,
	);

	!(defined $rv && ref $rv eq 'IO::Socket::SSL')
		or die "TLS handeshake failed";

	$s->close;

	return 1;
}, {
}];


push @tests, [ 'SMTP Plain', sub {
	my $s = Net::SMTP->new($host, Port => $port, Hello => 'localhost');

	$s->peerhost eq $host
		or die "peerport is not $host";
	$s->peerport eq $port
		or die "peerport is not $port";

	$s->mail($sender);
	$s->to($recip1, $recip2);
	$s->data();
	$s->datasend($data);
	$s->dataend();
	$s->quit;

       return 1;
}, { DATA => sub {
	# processing
	my ( $session, $message ) = @_;

	my $s = $session->get_sender();

	ok ($s eq $sender, "Sender");
	my @recipients = $session->get_recipients();
	my %recips = map { $_ => 1 } @recipients;

	ok ($recips{$recip1}, "found $recip1");
	ok ($recips{$recip2}, "found $recip2");

	ok ($$message, "found message");

	return (1, OK, 'Success!');
}}];

sub upgrade_to_tls {
	my $s = shift;
	defined $s->supports('STARTTLS', 500, [ "'STARTTLS' is not supported" ])
		or die "starttls is not supported";

	$s->command("STARTTLS")->response == Net::Cmd::CMD_OK
		or die "Cannot start command";

	my $rv = IO::Socket::SSL->start_SSL(
		$s, { SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE }
	) or die "Cannot upgrade to tls";

	# $s is IO::Socket::SSL now
	Net::Cmd::command($s, 'EHLO localhost') or die "Cannot send EHLO localhost command";
	Net::Cmd::response($s) == Net::Cmd::CMD_OK or die "EHLO failed after upgrading to TLS";
}

push @tests, [ 'TLS and quit', sub {
	my $s = _Net::SMTPS->new($host, Port => $port, Hello => 'localhost');

	$s->quit;

	return 1;
}, { # No server verification
}] ;

push @tests, [ 'TLS and send message', sub {
	my $s = _Net::SMTPS->new($host, Port => $port);
	$s->mail($sender);
	$s->to($recip1, $recip2);
	$s->data();
	$s->datasend($data);
	$s->dataend();
	$s->quit;
	return 1;
}, { DATA => sub {
	# processing
	my ( $session, $message ) = @_;

	my $s = $session->get_sender();

	ok ($s eq $sender, "Sender");
	my @recipients = $session->get_recipients();
	my %recips = map { $_ => 1 } @recipients;

	ok ($recips{$recip1}, "found $recip1");
	ok ($recips{$recip2}, "found $recip2");

	ok ($$message, "found message");

	return (1, OK, 'Success!');
}} ];

sub process_test {
	my $sock	= shift;
	my $tc_id	= shift;
	my $test	= shift;

	my $client = $sock->accept;
	push @socks, $client;
	my $smtp = new Net::Server::Mail::ESMTP(
		socket       => $client,
		idle_timeout => 300,
		SSL_config => {
				SSL_cert_file	=> 't/certs/server-cert.pem',
				SSL_key_file	=> 't/certs/server-key.pem',
		},
	) or die "Cannot create ESMTP";

	ok ($smtp, "Accepted client for $tc_id: " . $test->[0]);

	$smtp->register('Net::Server::Mail::ESMTP::STARTTLS');

	$smtp->set_callback( DATA => $test->[2]{DATA} || sub {} );

	diag("Processing");

	$smtp->process();

	diag("Done");

	$client->close;
	shift @socks;
}

my $ppid = $$;
my $pid = fork();
if (!defined $pid) {
	die $!;
} elsif ($pid) {
	# child process - server
	my $sock = IO::Socket::INET->new(
		Listen		=> 1,
		LocalAddr	=> $host,
	        LocalPort	=> $port,
		Proto		=> 'tcp',
		Timeout		=> 5,
	);
	if (!$sock) {
		kill 9, $pid;
		diag("kill 9 $pid (child)");
		die "Cannot create sock: $!";
	}

	push @socks, $sock;

	my $id = 0;
	for (@tests) {
		$id++;
		my $tc = sprintf("Test%02d", $id);
		process_test($sock, $tc, $_);
	}

	wait;
	$sock->close;

	done_testing;
	exit;
} else {
	# child
	sleep 1; # to give server time to set up sock
	for my $test (@tests) {
		my $rv;
		eval {
			local $SIG{__DIE__};
			$rv = $test->[1]->();
		};
		if ($@ || !$rv) {
			# kill the server
			diag ("Error: $@");
			diag ("kill 9, $ppid (server)");
			kill 9, $ppid;
			exit;
		}
	}

	exit;

}

BEGIN {
package _Net::SMTPS;

use strict;
use warnings;
use IO::Socket::SSL;

use Net::Cmd;

use Sys::Hostname;

our @ISA = qw(IO::Socket::SSL Net::SMTP);

sub new {
	my $class = shift;
	my $host = shift;

	my %args = @_;
	my $s = Net::SMTP->new($host, %args);

	if (defined $s->supports('STARTTLS', 500, [ "Command unknown: 'STARTTLS'" ])) {
		# OK, TLS is advertised as supported. Let's try it.
		if ($s->command('STARTTLS')->response == CMD_OK) {
			# The STARTTLS command was accepted, now begin SSL negotiation.
			# Net::SMTP::TLS is hardcoded! This will break
			# future inheritance
			my $rv = _Net::SMTPS->start_SSL(
				$s,
				SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
				%args,
			);
			# $self has been blessed to $class
			return undef unless ref $rv;

			$s->hello($args{Hello} || Sys::Hostname::hostname);
			return $s;
		}
	}

	return undef;
}

1;

}

END {
	$_->close for @socks;
}
