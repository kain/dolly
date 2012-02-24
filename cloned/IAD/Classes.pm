package IAD::Classes;

use common::sense;
use Storable qw/dclone/;
use Data::Dumper;

sub new {
	my($class) = @_;

	my $self = {
		'db' => $DI::db,
		'classes' => {},
		'computers' => {},
		'computersInClasses' => {},
		'macToId' => {},
	};
	$self = bless $self, $class;
	$self->init();
	return $self;
};

sub init {
	my($self) = @_;
	my $data = $self->{'db'}->{'dbh'}->selectall_arrayref('SELECT * FROM classes');
	$self->{'classes'} = { map { @{$_} } @$data };
	my $data = $self->{'db'}->{'dbh'}->selectall_arrayref('SELECT * FROM computers');
	foreach my $row(@$data)
	{
		$self->{'computers'}->{$row->[0]} = {
			'classId' => $row->[1],
			'name' => $row->[2],
			'mac' => $row->[3],
			'ip' => $row->[4],
			'updateDate' => $row->[5],
			'imageId' => $row->[6],
		};
		$self->{'computersInClasses'}->{$row->[1]} ||= {};
		$self->{'computersInClasses'}->{$row->[1]}->{$row->[0]} = 1;
		$self->{'macToId'}->{$row->[3]} = $row->[0];
	};
};

sub getMap {
	my($self) = @_;

	my $map = [];
	
	foreach my $classId (sort keys %{$self->{'classes'}}) {
		push(@$map, $self->getClassStruct($classId,'withChildrens' => 1));
	};
	return $map;
};

sub getClassStruct {
	my($self, $classId, %opts) = @_;
	my $classStruct = {'classId' => $classId, 'name' => $self->{'classes'}->{$classId}, 'children' => []};
	if($opts{'withChildrens'}) {
		if(exists $self->{'computersInClasses'}->{$classId}) {
			foreach (sort keys %{$self->{'computersInClasses'}->{$classId}}) {
				push(@{$classStruct->{'children'}}, $self->getComputerStruct($_));
			};
		};
	};
	return $classStruct;
};

sub getComputerStruct {
	my($self, $computerId) = @_;
	
	my $computerStruct = {%{$self->{'computers'}->{$computerId}},
						  'computerId' => $computerId,
						  };
	if(defined $computerStruct->{'imageId'}) {
		$computerStruct->{'imageName'} = $DI::images->{'images'}->{$computerStruct->{'imageId'}}->{'name'};
	};
	return $computerStruct;
};

sub getMac {
	my($self, $computerId) = @_;
	return $self->{'computers'}->{$computerId}->{'mac'};
};

sub macExists {
	my($self, $mac) = @_;
	return exists $self->{'macToId'}->{$mac} ? $self->{'macToId'}->{$mac} : undef;
};

sub addClass {
	my($self, $name) = @_;
	my $classId = $self->{'db'}->addClass($name);
	$self->{'classes'}->{$classId} = $name;
	return $classId;
};

sub deleteClass {
	my($self, $classId) = @_;
	if(exists $self->{'computersInClasses'}->{$classId}) {
		foreach(keys %{$self->{'computersInClasses'}->{$classId}}) {
			$self->deleteComputer($classId, $_);
		};
		delete $self->{'computersInClasses'}->{$classId};
	};
	$self->{'db'}->deleteClass($classId);
	delete $self->{'classes'}->{$classId};
	
	if(defined $IAD::Config::add_new_to_group && $IAD::Config::add_new_to_group == $classId) {
		IAD::Config::set({'add_new_to_group' => undef});
		IAD::Config::save();
	};
	
};

sub updateClass {
	my($self, $classId, $name) = @_;
	if(!exists $self->{'classes'}->{$classId}) {
		return undef;
	}
	else {
		$self->{'classes'}->{$classId} = $name;
		$self->{'db'}->updateClass($classId, $name);
	};
};

sub addComputer {
	my($self, $classId, $name, $plainMac, $ip) = @_;
	if(!exists $self->{'classes'}->{$classId}) {
		warn 'addComputer: classId ', $classId, ' not exists';
		return undef;
	};
	my $mac;
	unless($mac = $self->parseMac($plainMac)) {
		die 'wrong mac ', $plainMac;
	};
	if($self->macExists($mac)) {
		die 'doublicate mac';
	};
	if(defined $ip && length($ip) && !defined $self->parseIp($ip)) {
		die 'wrong ip';
	};
	my $computerId = $self->{'db'}->addComputer($classId, $name, $mac, $ip);
	return undef if !defined $computerId;
	$self->{'computers'}->{$computerId} = {
										   'classId' => $classId,
										   'name' => $name,
										   'mac' => $mac ,
										   'ip' => $ip,
										   'updateDate' => undef,
										   'imageId' => undef,
										   };
	$self->{'computersInClasses'}->{$classId} ||= {};
	$self->{'computersInClasses'}->{$classId}->{$computerId} = 1;
	$self->{'macToId'}->{$mac} = $computerId;
	return $computerId;
};

sub deleteComputer {
	my($self, $classId, $computerId) = @_;
	$self->{'db'}->deleteComputer($computerId);
	delete $self->{'computersInClasses'}->{$classId}->{$computerId};
	delete $self->{'macToId'}->{$self->{'computers'}->{$computerId}->{'mac'}};
	delete $self->{'computers'}->{$computerId};
	
};

sub updateComputer {
	my($self, $computerId, %opts) = @_;
	my $computer = $self->{'computers'}->{$computerId};
	if(!defined $computer) {
		return undef;
	}
	else {
		if(exists $opts{'mac'} && $opts{'mac'} != $computer->{'mac'}) {
			if($self->macExists($opts{'mac'})) {
				die 'doublicate MAC';
			};
			delete $self->{'macToId'}->{$computer->{'mac'}};
			$self->{'macToId'}->{$opts{'mac'}} = $computerId;
		};
		
		if(exists $opts{'classId'} && $opts{'classId'} != $computer->{'classId'}) {
			delete $self->{'computersInClasses'}->{$computer->{'classId'}}->{$computerId};
			$self->{'computersInClasses'}->{$opts{'classId'}}->{$computerId} = 1;
		};
		
		foreach(keys%opts) {
			$computer->{$_} = $opts{$_};
		};
		$self->{'db'}->updateComputer($computerId, map { $computer->{$_} } 
			('classId', 'name', 'mac', 'ip', 'updateDate', 'imageId'));
	};
};
sub updateComputerByMac {
	my($self, $mac, %opts) = @_;
	my $computerId = $self->{'macToId'}->{$mac};
	if(!defined $computerId) {
		return undef;
	}
	else {
		return $self->updateComputer($computerId, %opts);
	};
};

sub addIfNotExists {
	my($self, $mac, $ip) = @_;
	if(!defined $IAD::Config::add_new_to_group || $self->macExists($mac)) {
		return undef;
	}
	else {
		warn 'automaticaly add new computer';
		my $computerId = $self->addComputer($IAD::Config::add_new_to_group, '', $mac, $ip);
		if(defined $computerId) {
			$DI::adminAPI->addNotice('computerAdded', $self->getComputerStruct($computerId));
		};
	};
};

sub parseMac {
	my($self, $mac) = @_;
	$mac = lc $mac;
	$mac =~ s/-/:/g;
	while($mac =~ s/:0?:/:00:/g) {};
	$mac =~ s/^0?:/00:/;
	$mac =~ s/:0?$/:00/;
	return $mac =~ /^(?:[a-f0-9]{2}:){5}[a-f0-9]{2}$/ ? $mac : undef;
};

sub parseIp {
	my($self, $ip) = @_;
	return $ip =~ /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/
		? $ip
		: undef;
};

#
#package IAD::Classes::Class;
#sub new {
#	my($class, $name, $classId) = @_;
#	my $self = {
#		'name' => $name,
#		'classId' => $classId,
#		'computers' => [],
#	};
#};
#
#sub addComputer {
#	my($self, $name, $mac) = @_;
#	
#	my $computerId = $self->{'db'}->addComputer($classId, $name, $mac);
#	
#	$self->{'computers'}->{$computerId} = {'name' => $name, 'mac' => $mac , 'updateDate' => undef, 'imageId' => undef};
#	$self->{'computersInClasses'}->{$classId} ||= {};
#	$self->{'computersInClasses'}->{$classId}->{$computerId} = 1;
#	return $computerId;
#};
#
#sub clone {
#	my($self, $withComputers) = @_;
#	
#};
#
#package IAD::Classes::Computer;
#
#sub new {
#	my($class, $computerId, $name, $mac, $updateDate, $imageId) = @_;
#	my $self = {
#};

1;