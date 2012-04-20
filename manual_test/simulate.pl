BEGIN { chdir('..'); };
use IAD::DataBase;
use Data::Dumper;
use LWP;
use common::sense;
$|++;

my $db = IAD::DataBase->new('iad.s3db');

my($bootUrl, $readyUrl) = map { 'http://localhost/iad_api/' . $_ . '?' } ('getbootscript', 'iready');
my @ips = map { '192.168.110.' . $_ } (11..12);



my $ua = LWP::UserAgent->new();
my $response;
my $url;

while() {
	say 'select action:
1. cloning
2. new macs
choice:';
	given(<>) {
		cloning() when 1;
		newmacs() when 2;
		default { exit };
	}
};


sub newmacs {
	foreach (1..3) {
		$url = $bootUrl . 'mac=' . randMac() . '&ip=' . randIP();
		$response = $ua->get($url);
		say $url, ' ', $response->status_line();
		say $response->content(), "\n-- end --";
		randWait();
	};
};

sub cloning {
	my $computers = $db->getAllComputers;
	foreach (@$computers) {
		$url = $bootUrl . 'mac=' . $_->[3] . '&ip=' . randIP();
		$response = $ua->get($url);
		say $url, ' ', $response->status_line();
		say $response->content(), "\n-- end --";
		randWait();
	};
	randWait() for(1..3);
	foreach (@$computers) {
		$url = $readyUrl . 'mac=' . $_->[3] . '&ip=' . randIP();
		$response = $ua->get($url);
		say $url, ' ', $response->status_line();
		say $response->content(), "\n-- end --";
		randWait();
	};
};



sub randIP {
	push @ips, $ips[0];
	return shift @ips;
	return '192.168.' . int(rand()*100) . '.' . int(rand()*100);
};

sub randWait {
	select undef, undef, undef, 0.5 + rand(1.5);
};

sub randMac {
	my @symbols = (0..9, 'a'..'f');
	return join ':', map { join '', map { $symbols[int rand @symbols] } 0..1 } 0..5
};