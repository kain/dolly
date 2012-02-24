use Time::HiRes qw/time/;
$|++;
print "start cloning ", time(), "\n";
print "\$ARGV[$_]: $ARGV[$_]\n" for(0..$#ARGV);
for(1..10) {
	print "cloning ", time(), "\n";
	sleep 5;
};

print "end cloning ", time(), "\n";