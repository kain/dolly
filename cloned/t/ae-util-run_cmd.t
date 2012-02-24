use Test::Simple 'no_plan';
use AE;
BEGIN {
	if($^O =~ /Win/) {
		require AnyEvent::Impl::Perl;
		AnyEvent::Impl::Perl->import();
	};
	*fcntl = sub {};
};
use AnyEvent::Util;

ok(1, "run_cmd probably totaly broken on win32");
exit;
my $timer = AE::timer 1, 2 , sub { warn "timer" };
my $cv;
my $timer2 = AE::timer 0, 0, sub {
	$cv = run_cmd 'perl t\test-cmd.pl', 
	'>' => sub { print @_ };
	
	$cv->cb (sub {
	  #shift->recv and die "openssl failed";
	});
};

AE->cv->recv;