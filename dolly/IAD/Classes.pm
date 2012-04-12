package IAD::Classes;
#Класс реализующий логику групп\компьютеров
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

#Инициализация, запрос к базе о текущем состоянии сети
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

#Получение информации о всех группах\компьютерах
sub getMap {
	my($self) = @_;

	my $map = [];
	
	foreach my $classId (sort keys %{$self->{'classes'}}) {
		push(@$map, $self->getClassStruct($classId,'withChildrens' => 1));
	};
	return $map;
};

#Получение информации о группе по ID группы
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

#Получение информации о компьютере по ID
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

#Получение MAC адреса по ID компьютера
sub getMac {
	my($self, $computerId) = @_;
	return $self->{'computers'}->{$computerId}->{'mac'};
};

#Проверка существования MAC адреса в текущем состоянии сети
sub macExists {
	my($self, $mac) = @_;
	return exists $self->{'macToId'}->{$mac} ? $self->{'macToId'}->{$mac} : undef;
};

#Добавление новой группы
sub addClass {
	my($self, $name) = @_;
	my $classId = $self->{'db'}->addClass($name);
	$self->{'classes'}->{$classId} = $name;
	return $classId;
};

#Удаление
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

#Обновление информации о группе
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

#Добавления компьютера
sub addComputer {
	my($self, $classId, $name, $plainMac, $ip) = @_;
	if(!exists $self->{'classes'}->{$classId}) {
		warn $self->{'DEBUGGER'}->make_error('ERROR', $self, "Tried add computer to class:<$classId> but it seems not exists.");
		return undef;
	};
	my $mac;
	unless($mac = $self->parseMac($plainMac)) {
		die $self->{'DEBUGGER'}->make_error('FATAL_ERROR', $self, "Tried to add computer with wrong mac:<$plainMac>.");
	};
	if($self->macExists($mac)) {
		die $self->{'DEBUGGER'}->make_error('FATAL_ERROR', $self, "Tried to add computer with mac that already in DB:<$mac>");
	};
	if(defined $ip && length($ip) && !defined $self->parseIp($ip)) {
		die $self->{'DEBUGGER'}->make_error('FATAL_ERROR', $self, "Tried to add computer with wrong IP.<$ip>");
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

#Удаление
sub deleteComputer {
	my($self, $classId, $computerId) = @_;
	$self->{'db'}->deleteComputer($computerId);
	delete $self->{'computersInClasses'}->{$classId}->{$computerId};
	delete $self->{'macToId'}->{$self->{'computers'}->{$computerId}->{'mac'}};
	delete $self->{'computers'}->{$computerId};
	
};

#Обновление информации о компьютере
sub updateComputer {
	my($self, $computerId, %opts) = @_;
	my $computer = $self->{'computers'}->{$computerId};
	if(!defined $computer) {
		return undef;
	}
	else {
		if(exists $opts{'mac'} && $opts{'mac'} != $computer->{'mac'}) {
			if($self->macExists($opts{'mac'})) {
				die "<FATAL_ERROR> ".$self->{'DEBUGGER'}->make_message($self, "Tried to update computer with mac that already in DB:<$opts{'mac'}>");
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

#Автоматическое добавление нового компьютера если он не существует и если задана соответсвующая опция
sub addIfNotExists {
	my($self, $mac, $ip) = @_;
	if(!defined $IAD::Config::add_new_to_group || $self->macExists($mac)) {
		return undef;
	}
	else {
		$self->{'DEBUGGER'}->print_message($self, "Adding new computer automaticaly.");
		my $computerId = $self->addComputer($IAD::Config::add_new_to_group, '', $mac, $ip);
		if(defined $computerId) {
			$DI::adminAPI->addNotice('computerAdded', $self->getComputerStruct($computerId));
		};
	};
};

#Проверка MAC адреса и приведение к стандартному виду
#0:::::ff, 00-00-00-00-00-FF -> 00:00:00:00:00:FF
sub parseMac {
	my($self, $mac) = @_;
	$mac = lc $mac;
	$mac =~ s/-/:/g;
	while($mac =~ s/:0?:/:00:/g) {};
	$mac =~ s/^0?:/00:/;
	$mac =~ s/:0?$/:00/;
	return $mac =~ /^(?:[a-f0-9]{2}:){5}[a-f0-9]{2}$/ ? $mac : undef;
};

#Проверка IP адреса
sub parseIp {
	my($self, $ip) = @_;
	return $ip =~ /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/
		? $ip
		: undef;
};

1;