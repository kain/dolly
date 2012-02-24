use Time::HiRes qw/time/;
$|++;
open my $fp, $ARGV[0];

while(<$fp>) {
	print $_;
	select undef, undef, undef, rand 1;
};

close $fp;