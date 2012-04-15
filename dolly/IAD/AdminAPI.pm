package IAD::AdminAPI;
#Класс обработки запросов от веб интерфейса
use common::sense;
use JSON::XS;
use Data::Dumper;

our ($DEBUGGER, @RULES) = ($DI::DEBUGGER, qw/admin all/);

#Создание объекта
sub new {
	my($class) = @_;
	my $self = {
		'classes'  => $DI::classes,
		'images'   => $DI::images,
		'cloning'  => $DI::cloning,
		'ticket'   => undef,
		'notices'  => []
	};
	return bless $self, $class;
};

#обработка запросов
sub handleRequest {
	my($self, $content) = @_;
	push my @R, @RULES;

	my $data = decode_json($content);
	
	if ($DEBUGGER->is_ON){
		push @R, qw/admin_spam/ if $data->{'do'} eq 'getNotices' or $data->{'do'} eq 'getCloningState';
		$DEBUGGER->DEBUG([@R], $self, "Web-interface request: $data->{'do'} (", join (",", %$data), ")");
	}

	my $response = IAD::AdminAPI::Response->new();
	if($data->{'do'} eq 'init') {
		$self->getNotices(); #clear Notices
		$response->ok->add(
			'config' => IAD::Config::get(),
			'classes' => $self->getClassesStruct(),
			'images' => $self->{'images'}->getMap(),
			'isCloning' => $self->{'cloning'}->{'isCloning'},
			'cloningMode' =>  $self->{'cloning'}->{'mode'},
			'cloningStateLog' => $self->getStateLogStruct(),
			'ticket' => $self->genTicket()
		);
		if($self->{'cloning'}->{'isCloning'}) {
			$response->add('cloningClasses' => $self->getCloningClassesStruct());
		};
	}
	elsif(defined $self->{'ticket'} && $data->{'ticket'} eq $self->{'ticket'}) {
		given($data->{'do'}) {
			when('getNotices') {
				$response->ok->add('notices' => $self->getNotices());
			}
			when('updateConfig') {
				IAD::Config::set($data->{'config'});
				IAD::Config::save();
				$response->ok();
			}
			when('resetConfig') {
				my $defaultConfig = IAD::Config::getDefault();
				IAD::Config::set($defaultConfig);
				IAD::Config::save();
				$response->ok->add('config' => $defaultConfig);
			}
			when('addClass') {
				my $classId = $self->{'classes'}->addClass($data->{'name'});
				if(defined $classId) {
					$response->ok->add('classId' => $classId);
				};
			}
			when('editClass') {
				if($self->{'classes'}->updateClass($data->{'id'}, $data->{'name'})) {
					$response->ok();
				}
				else {
					$response->fail('Unknow error');
				};
			}
			when('addComputer') {
				my $mac = $self->{'classes'}->parseMac($data->{'mac'});
				if(defined $mac) {
					if(!$self->{'classes'}->macExists($mac)) {
						if(!defined $data->{'ip'} || !length($data->{'ip'})
							|| defined $self->{'classes'}->parseIp($data->{'ip'})) {
								
							my $computerId = $self->{'classes'}->addComputer($data->{'classId'},
																			 $data->{'name'},
																			 $data->{'mac'},
																			 $data->{'ip'});
							if(defined $computerId) {
								$response->ok->add('computerId' => $computerId, 'mac' => $mac);
							}
							else {
								$response->fail('Unknow error');
							};
						}
						else {
							$response->fail('Wrong IP address');
						};
					}
					else {
						$response->fail('This MAC address already exists');
					};
				}
				else {
					$response->fail('Wrong MAC address');
				};
			}
			when('deleteComputers') {
				foreach my $id (@{$data->{'ids'}}) {
					scalar @$id == 2
					? $self->{'classes'}->deleteComputer(@$id)
					: $self->{'classes'}->deleteClass($id->[0]);
				};
				$response->ok;
			}
			when('moveComputers') {
				foreach my $id(@{$data->{'ids'}}) {
					$self->{'classes'}->updateComputer($id, 'classId' => $data->{'toClassId'});
				};
				$response->ok;
			}
			when('editComputer') {
				my $mac;
				if(!defined ($mac = $self->{'classes'}->parseMac($data->{'mac'}))) {
					$response->fail('Wrong MAC address');
				}
				else {
					if($self->{'classes'}->getMac($data->{'id'}) ne $mac
						&& $self->{'classes'}->macExists($mac)) {
						$response->fail('This MAC address already exists');
					}
					elsif(defined $data->{'ip'} && length($data->{'ip'}) && !defined $self->{'classes'}->parseIp($data->{'ip'})) {
						$response->fail('Wrong IP address');
					}
					else {
						$self->{'classes'}->updateComputer($data->{'id'}, 'name' => $data->{'name'}, 'mac' => $mac, 'ip' => $data->{'ip'});
						$response->ok->add('mac' => $mac);
					};
				};
			}
			when('addImageManual') {
				my($imageId, $addDate) = $self->{'images'}->addImage($data->{'name'}, $data->{'path'});
				if(defined $imageId) {
					$response->ok->add(
						'imageId' => $imageId,
						'addDate' => $addDate
					);
				};
			}
			when('deleteImage') {
				$self->{'images'}->deleteImage($data->{'imageId'});
				$response->ok;
			}
			when('createImage') {
				if($self->{'cloning'}->{'isCloning'}) {
					$response->fail('Cloning already run');
				}
				else {
					$self->{'cloning'}->addComputer($self->{'classes'}->getComputerStruct($data->{'id'}));
					$self->{'cloning'}->start('imaging', $data->{'name'}, $data->{'path'});
					$response->ok;
				};
			}
			when('startCloning') {
				if($self->{'cloning'}->{'isCloning'}) {
					$response->fail('Cloning already run');
				}
				else {
					foreach my $computerId(@{$data->{'ids'}}) {
						$self->{'cloning'}->addComputer($self->{'classes'}->getComputerStruct($computerId));
					};
					$self->{'cloning'}->start('cloning', $data->{'imageId'});
					$response->ok;
				};
			}
			when('getCloningState') {
				$response->ok->add(
					'isCloning' => $self->{'cloning'}->{'isCloning'},
					'state' => $self->{'cloning'}->{'state'}->get(),
					'mode' => $self->{'cloning'}->{'mode'},
					'stateLog' => $self->getStateLogStruct(),
					'computersState' => $self->{'cloning'}->getComputersState()
				);
			}
			when('getCloningLog') {
				if(ref $self->{'cloning'}->{'cloningLog'} eq 'ARRAY') {
					$response->ok->add('log' => join"<br>", @{$self->{'cloning'}->{'cloningLog'}});
				}
				else {
					$response->ok->add('log' => 'no log');
				};
			}
			when('stopCloning') {
				if($self->{'cloning'}->{'isCloning'}) {
					$self->{'cloning'}->end();
					$response->ok->add('stateLog' => $self->getStateLogStruct(), 'mode' => $self->{'cloning'}->{'mode'});
				}
				else {
					$response->fail('Cloning not runned');
				};
			}
			when('wakeComputers') {
				$self->{'cloning'}->wol(@{$data->{'ids'}});
				$response->ok;
			}
			default {
				$response->fail('Unknow action(do eq "' . $data->{'do'} . '")');
			}
		};
	}
	else {
		if(defined $self->{'ticket'}) {
			$response->fail('Interface opened in another browser');
		}
		else {
			$response->fail('IAD Daemon has been restarted');
		};
	};
	if(!$response->isset) {
		$response->fail('Action "' . $data->{'do'} . '" not return response');
	};
	return $response->json, 'Content-Type' => 'application/json';

};

#Подготовка информации о клонируемых компьютерах
sub getCloningClassesStruct {
	my($self) = @_;
	
	my $map = $self->{'cloning'}->getMap();
	
	foreach my $class (@$map) {
		$class->{'expanded'} = 1;
		foreach my $computer(@{$class->{'children'}}) {
			$computer->{'leaf'} = 1;
		};
	};
	return $map;
};

#Подготовока информации о всех компьютерах
sub getClassesStruct {
	my($self) = @_;
	
	my $map = $self->{'classes'}->getMap();
	
	foreach my $class (@$map) {
		$class->{'checked'} = JSON::XS::false;
		foreach my $computer(@{$class->{'children'}}) {
			$computer->{'checked'} = JSON::XS::false;
			$computer->{'leaf'} = 1;
		};
	};
	return $map;
};

#Подготовка информации о текущем статусе
sub getStateLogStruct {
	my($self) = @_;
	return [ map { {'date' => $_->[0], 'state' => $_->[1], 'params' => [@{$_}[2..$#$_]] } }  @{ $self->{'cloning'}->{'state'}->getLog() } ];
};

#Создание 'тикета' для клиента
#Позволяет отключать предыдущий интерфейс при заходе с другого компьютера
sub genTicket {
	my($self) = @_;
	return $self->{'ticket'} = join '', map { chr(int rand(2) ?  97 + int(rand(6)) : 48 + int(rand(10))) } (1..16);
};

#Получение отложенных уведомлений для интерфейса(изменение IP адресов и т.п.)
sub getNotices {
	my($self) = @_;
	my $notices = delete $self->{'notices'};
	$self->{'notices'} = [];
	return $notices;
};

#Регистрация нового уведомления
sub addNotice {
	my($self, $name, @params) = @_;
	push(@{$self->{'notices'}}, [$name, @params]);
};

package IAD::AdminAPI::Response;
#Класс реализующий ответ клиенту, поддерживает цепочку вызовов
use JSON::XS;

#Создание объекта
sub new {
	my($class) = @_;
	return bless {'success' => undef}, $class;
};

#Ответ успешный
sub ok {
	my($self, $ok) = @_;
	$self->{'success'} = defined $ok ? $ok : 1;
	return $self;
};

#Добавление параметров ответа
sub add {
	my($self, %add) = @_;
	$self->{$_} = $add{$_} foreach keys %add;
	return $self;
};

#Ответ не успешен
sub fail {
	my($self, $fail) = @_;
	$self->add('fail' => $fail);
	$self->ok(0);
	return $self;
};

#Ответ задан?
sub isset {
	my($self) = @_;
	return defined $_[0]->{'success'};
};

#Сериализация ответа в JSON
sub json {
	my($self) = @_;
	return encode_json({%{$self}});
};

1;