use Test::Simple 'no_plan';
use IAD::Cloning;

my $cloning = IAD::Cloning->new();
#genTicket
my $testSeq = {	map { $_ => 0 } ('a'..'f', 0..9) };
for(1..1024) {
	foreach(split//,$cloning->genTicket) {
		exists $testSeq->{$_} ? $testSeq->{$_}++ : do {
			ok(0, 'unknown symbol ' . $_);
			last;
		};
	};
};
