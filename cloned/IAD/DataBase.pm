package IAD::DataBase;
##!!rewrite to AE::DBI
use common::sense;
use DBI;


sub new {
	my($class, $dbfile) = @_;
	my $self = bless {'dbfile' => $dbfile}, $class;
	$self->init();
	return $self;
};

sub init {
	my($self) = @_;
	$self->{'dbh'} = DBI->connect("dbi:SQLite:dbname=" . $self->{'dbfile'}, "", "") || die $!;
	#$self->{'queries'} = {};
	foreach(['addClass', 'INSERT INTO `classes` (name) VALUES (?)'],
			['addComputer', 'INSERT INTO `computers` (classId, name, mac, ip) VALUES (?,?,?,?)'],
			['addImage', 'INSERT INTO `images` (name, path, addDate) VALUES (?,?,?)'],
			['addConfig', 'INSERT INTO `config` (name, value) VALUES (?,?)']) {
		my $sth = $self->{'dbh'}->prepare($_->[1]);
		*{$_->[0]} = sub { 
			my $self = shift;
			$sth->execute(@_);
			return $self->lastInsertId(); 
		};
	};
	
	foreach(['updateClass', 'UPDATE `classes` SET name = ? WHERE classID = ?'],
			['updateComputer', 'UPDATE `computers` SET classId = ?, name = ?, mac = ?, ip = ?, updateDate = ?, imageId = ? WHERE computerId = ?'],
			['updateImage', 'UPDATE `images` SET name = ?, path = ?, addDate = ? WHERE imageId = ?'],
			['updateConfig', 'UPDATE `config` SET value = ? WHERE name = ?']) {
		my $sth = $self->{'dbh'}->prepare($_->[1]);
		*{$_->[0]} = sub { 
			my $self = shift;
			push @_, shift @_; # place id to end
			return $sth->execute(@_);
		};
	};
	
	foreach(['deleteComputer', 'DELETE FROM `computers` WHERE computerId = ?'],
			['deleteClass', 'DELETE FROM `classes` WHERE classId = ?'],
			['deleteImage', 'DELETE FROM `images` WHERE imageId = ?']) {
		my $sth = $self->{'dbh'}->prepare($_->[1]);
		*{$_->[0]} = sub { 
			my $self = shift;
			return $sth->execute(@_);
		};
	};
	
	foreach(['getAllClasses', 'SELECT * FROM classes'],
			['getAllComputers', 'SELECT * FROM computers'],
			['getAllImages', 'SELECT * FROM images'],
			['getConfig', 'SELECT * FROM config']) {
		my $query = $_->[1];
		*{$_->[0]} = sub { 
			my $self = shift;
			return $self->{'dbh'}->selectall_arrayref($query);
		};
	};

};

sub createDataBase {
	my($self) = @_;
	#$self->{'dbh'}->do('DROP TABLE IF EXISTS `classes`');
};

sub lastInsertId {
	my($self) = @_;
	return $self->{'dbh'}->sqlite_last_insert_rowid();
};

1;