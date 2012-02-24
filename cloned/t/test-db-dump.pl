use DBI;
use JSON::XS;
use common::sense;

my $dbh = DBI->connect("dbi:SQLite:dbname=iad.s3db", "", "") || die $!;

my $data;
foreach(['classes','classId'],['computers','computerId'],['images','imageId']) {
	$data = $dbh->selectall_hashref('SELECT * FROM ' . $_->[0], $_->[1]);
	say 'TABLE ', $_->[0];
	foreach my $key(sort keys %$data) {
		say 'id: ', $key, ', ', encode_json($data->{$key});
	};
};