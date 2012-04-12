package IAD::Cloning;
#Класс реализующий логику клонирования(и снятия) образа на целевые компьютеры
use common::sense;
use File::Slurp qw/slurp/;
use AnyEvent::Run;

#Инициализация
sub new {
	my($class) = @_;
	my $self = bless {
		'isCloning' => 0,
		'mode' => 'cloning',
		'cloningRun' => undef,
		'state' => IAD::Cloning::State->new(),
		'macs' => {},
		'ipToMac' => {},
		'classes' => $DI::classes,
		'images' => $DI::images,
		'DEBUGGER' => $DI::DEBUGGER,
		'maxBackLog' => 10*1024,
		'cloningScriptState' => {},
	}, $class;
	return $self;
};

#Добавление компьютера для клонирования
sub addComputer {
	my($self, $computer) = @_;
	if($self->{'isCloning'}) {
		return undef;
	}
	else {
		if(exists $self->{'macs'}->{$computer->{'mac'}}) {
			return undef;
		}
		else {
			$computer->{'status'} = 'none';
			$computer->{'ip'} = 'unknow';
			$self->{'macs'}->{$computer->{'mac'}} = $computer;
		};
	};
};

#Получение информации о всех зарегистированных компьютеров для клонирования
sub getMap {
	my($self) = @_;

	my $map = {};
	foreach my $computer (values %{$self->{'macs'}}) {
		if(!exists $map->{$computer->{'classId'}}) {
			$map->{$computer->{'classId'}} = $self->{'classes'}->getClassStruct($computer->{'classId'});
		};
		push(@{$map->{$computer->{'classId'}}->{'children'}},
			$self->{'classes'}->getComputerStruct($computer->{'computerId'}));
	};
	return [sort { $b->{'classId'} <=> $a->{'classId'} } values %$map];
};

#Получение статуса всех клонируемых компьютеров
sub getComputersState {
	my($self) = @_;
	my $state = {};
	foreach my $computer(values %{$self->{'macs'}}) {
		$state->{$computer->{'computerId'}} = { map { $_ => $computer->{$_} } ('status','ip') };
	};
	return $state;
};

#Запуск процесса клонирования\снятия образа
sub start {
	my($self, $mode, @params) = @_;
	if($self->{'isCloning'}) {
		warn "<ERROR> ".$self->{'DEBUGGER'}->make_message($self, "Logical error, unable to start cloning, it seems already started.");
		return undef;
	}
	else {
		$self->{'isCloning'} = 1;
		$self->{'mode'} = $mode; # cloning || imaging
		$self->{'state'}->clear();
		$self->{'state'}->set('waitAllReady');
		$self->{'ipToMac'} = {};
		$self->{'cloningScriptState'}->{'finished'} = 0;
		if($self->{'mode'} eq 'cloning') {
			$self->{'imageId'} = $params[0];
			$self->{'imagePath'} = $self->{'images'}->getImagePath($self->{'imageId'});
		}
		else {
			$self->{'cloningScriptState'}->{'partition'} = 0;
			$self->{'imagingMac'} = (keys %{ $self->{'macs'} })[0];
			($self->{'imageName'}, $self->{'imagePath'}) = @params;
		};
		$self->{'cloningScriptLog'} = [];
	};
};


#Заверешение процесса клонирования(плановое или по инициативе пользователя)
sub end {
	my($self, $state, @params) = @_;
	if(!$self->{'isCloning'}) {
		return undef;
	};
	$self->{'cloningRun'} = undef;
	$self->{'cloningScriptState'} = {};
	
	$self->{'macs'} = {};
	delete $self->{'ipToMac'};
	
	$self->{'state'}->set(defined $state ? $state : 'canceled', @params);
	$self->{'isCloning'} = 0;

};

#Список всех состояний процесса клонирования
my @cloningStatus = (
	'notRunned',
	'waitAllReady',
	'runned',
	'waitConnections',
	'transfering', #image, percent
	'complete',
	'canceled',
	'error'
);

#Список состояний целевых компьютеров
my @clientStatus = (
	'none',
	'booting',
	'ready',
	'connecting',
	'connected',
	'cloning',
	'complete'
);

#Разбор лога от скриптов клонирования\создания образа dolly
sub parseLog {
	my($self, $log) = @_;
	if(!exists $self->{'logFp'}) {
		open $self->{'logFp'}, '>logs/' . time() . '.log';
	};
	print { $self->{'logFp'} } $log, "\n";
	
	shift @{$self->{'cloningLog'}}
		if scalar @{$self->{'cloningLog'}} == $self->{'maxBackLog'};
		
	push(@{$self->{'cloningLog'}}, $log);
	if($self->{'mode'} eq 'cloning') {
		given($log) {
			when(/^New connection from ((?:\d{1,3}\.){3}\d{1,3})\s+\(#\d+\) \d+/) {
				my $ip = $1;
				if(exists $self->{'ipToMac'}->{$ip}) {
					$self->{'macs'}->{$self->{'ipToMac'}->{$ip}}->{'status'} = 'connected';
					$self->{'state'}->updateLast(scalar (grep {  $_->{'status'} eq 'connected' } values %{$self->{'macs'}}),
												 scalar (grep {  $_->{'status'} ne 'disconnected' } values %{ $self->{'macs'} }));
				}
				else {
					warn '!exists ipToMac -> ', $ip;
				};
			}
			when(/^Disconnecting #\d+ \(((?:\d{1,3}\.){3}\d{1,3})\)/) {
				my $ip = $1;
				if($self->{'cloningScriptState'}->{'transfering'}) {
					$self->{'macs'}->{$self->{'ipToMac'}->{$ip}}->{'status'} = 'disconnected';
				};
			}
			when(/^Starting transfer: \d+/) {
				foreach(values %{ $self->{'macs'} }) {
					$_->{'status'} = 'cloning' if $_->{'status'} eq 'connected';
				};
				$self->{'cloningScriptState'}->{'transfering'} = 1;
				$self->{'state'}->set('transfering',
									  $self->{'cloningScriptState'}->{'image'},
									  $self->mathPercent(0, $self->{'cloningScriptState'}->{'imageSize'}));
			}
			when(/^UDP sender for (.*?) at /) {
				$self->{'cloningScriptState'}->{'image'} = $1;
				$self->{'cloningScriptState'}->{'imageSize'} = (stat($1))[7];
			}
			when(/^bytes=([\s0-9KM]*) re-xmits/) {
				my $bytes = $1;
				$bytes =~ s/\s//g;
				if($bytes =~ s/K//) {
					$bytes *= 1024;
				}
				elsif ($bytes =~ s/M//) {
					$bytes *= 1024*1024;
				};
				$self->{'cloningScriptState'}->{'bytes'} = $bytes;
				$self->{'state'}->updateLast($self->{'cloningScriptState'}->{'image'},
						  					 $self->mathPercent($bytes, $self->{'cloningScriptState'}->{'imageSize'}));
			}
			when(/^Transfer complete/) {
				$self->{'cloningScriptState'}->{'transfering'} = 0;
				#$self->{'state'}->updateLast($self->{'cloningScriptState'}->{'image'},
				#		  					 100);
			}
			when(/^Broadcasting control to/) {
				foreach(values %{ $self->{'macs'} }) {
					$_->{'status'} = 'connecting' if $_->{'status'} ne 'disconnected';
				};
				$self->{'state'}->set('waitConnections', 0, scalar (grep {  $_->{'status'} ne 'disconnected' } values %{ $self->{'macs'} }));
			}
			when(/^Cloning finished at:/) {
				$self->{'cloningScriptState'}->{'finished'} = 1;
				my $updateDate = time();
				foreach(values %{ $self->{'macs'} }) {
					if($_->{'status'} ne 'disconnected') {
						$self->{'classes'}->updateComputer($_->{'computerId'},
														   'updateDate' => $updateDate,
														   'imageId' => $self->{'imageId'});
						$DI::adminAPI->addNotice('computerEdited', {
							'id' => $_->{'computerId'},
							'updateDate' => $updateDate,
							'imageName' => $DI::images->{'images'}->{$self->{'imageId'}}->{'name'}
						});
					};
				};
			}
		};
	}
	else {
		given($log) {
			when(/^ntfsclone v\d/) {
				$self->{'macs'}->{$self->{'imagingMac'}}->{'status'} = 'imaging';
				$self->{'cloningScriptState'}->{'partition'}++;
			}
			when(/^Scanning volume \.{3}/) {
				$self->{'state'}->set('scanning', $self->{'cloningScriptState'}->{'partition'}, '0.00');
			}
			when(/^\s*?([0-9.]+) percent completed/) {
				my $percent = $1;
				given($self->{'state'}->get()) {
					when(['scanning', 'saving']) {
						$self->{'state'}->updateLast($self->{'cloningScriptState'}->{'partition'}, $percent);
					}
				};
			}
			when(/^Space in use\s+: (\d+ MB) \(([0-9.]+)%\)/) {
				$self->{'state'}->set('scanned', $1, $2);
			}
			when(/^Saving NTFS to image \.{3}/) {
				$self->{'state'}->set('saving', $self->{'cloningScriptState'}->{'partition'}, '0.00');
			}
			when(/^Imaging finished at:/) {
				$self->{'macs'}->{$self->{'imagingMac'}}->{'status'} = 'complete';
				$self->{'cloningScriptState'}->{'finished'} = 1;
				my($imageId, $addDate) = $self->{'images'}->addImage($self->{'imageName'}, $self->{'imagePath'});
				if(defined $imageId) {
					$DI::adminAPI->addNotice('imageAdded', {
						'imageId' => $imageId,
						'name' => $self->{'imageName'},
						'path' => $self->{'imagePath'},
						'addDate' => $addDate
					});
				};
			}
		};
	};
};

#Подсчет процента выполнения
sub mathPercent {
	my($self, $complete, $all) = @_;
	return undef if !defined $all || $all == 0;
	return sprintf("%.1f", $complete / $all * 100);
};

#Зацуск скрипта клонирования\снятия образа dolly
sub startCloningScript {
	my($self) = @_;
	if(defined $self->{'cloningRun'}) {
		die "<FATAL_ERROR> ".$self->{'DEBUGGER'}->make_message($self, "Was attempt to run script while it was already runned.");
	}
	else {
		my $cloningCmd = $self->{'mode'} eq 'cloning'
			? $IAD::Config::clone_upload_image_cmd
			: $IAD::Config::clone_make_image_cmd;
			
		my $ipList = join ' ' , map { $_->{'ip'} } values %{$self->{'macs'}};
		
		$cloningCmd =~ s/%ips?%/$ipList/g;
		$cloningCmd =~ s/%image%/$self->{'imagePath'}/g;
		
		$self->parseLog('run cmd ' . $cloningCmd . ' ' . time());
		
		$self->{'DEBUGGER'}->print_message($self, "Launching command:<<$cloningCmd>>");
		
		$self->{'cloningRun'} = AnyEvent::Run->new(
	        cmd      => $cloningCmd,
	        on_read  => sub {
	            my $handle = shift;
	            my $data = delete $handle->{'rbuf'};
				$self->parseLog($_) foreach split(/\r|\n/, $data);
	        },
	        on_eof	 => sub {
				if($self->{'cloningScriptState'}->{'finished'}) {
	        		$self->end('complete');
	        	}
	        	else {
	        		$self->end('error', 'EOF from script');
	        	};
	        },
	        on_error => sub {
	            my ($handle, $fatal, $msg) = @_;
				$self->parseLog('cloning script error ' . $msg . ' ' . time());
	            warn "<ERROR> ".$self->{'DEBUGGER'}->make_message($self, "AnyEvent::Run::on_error FATAL: $fatal, msg: $msg.");
	            $self->end('error', "Error fatal: $fatal, msg: $msg");
	        },
		);
		$self->{'state'}->set('runned');
		$_->{'status'} = 'connecting' foreach values %{$self->{'macs'}};
	};
};	

#Обработка запросов от целевых компьютеров для обеспечения обычной загрузки и загрузки в режиме клонирования
sub handleRequest {
	my($self, $action, $params) = @_;

	my($mac, $ip) = ($params->{'mac'},  $params->{'ip'});
	
	if(!defined ($mac = $self->{'classes'}->parseMac($mac))) {
		return 'Bad mac', 'Status' => 404, 'Content-Type' => 'text/plain';
	}
	elsif(!defined $self->{'classes'}->parseIp($ip)) {
		return 'Bad ip', 'Status' => 404, 'Content-Type' => 'text/plain';
	};


	
	if($IAD::Config::auto_update_ip && defined (my $computerId = $self->{'classes'}->macExists($mac))) {
		$self->{'classes'}->updateComputer($computerId, 'ip' => $ip);
		$DI::adminAPI->addNotice('computerEdited', {'id' => $computerId, 'ip' => $ip});
	};
	
	defined $IAD::Config::add_new_to_group
		&& $self->{'classes'}->addIfNotExists($mac, $ip);
	
	my $computer = $self->{'macs'}->{$mac};

	$self->{'DEBUGGER'}->print_message($self, "HTTP: Action:<$action> mac:<$mac> ip:<$ip>.");
	
	if($action eq 'getbootscript') {
		if($self->{'isCloning'} && defined $computer) {
			$computer->{'status'} = 'booting';
			$computer->{'ip'} = $ip;
			$self->{'ipToMac'}->{$ip} = $mac;
			return scalar slurp($IAD::Config::ipxe_network_boot), 'Content-Type' => 'text/plain';
		}
		else {
			return scalar slurp($IAD::Config::ipxe_normal_boot), 'Content-Type' => 'text/plain';
		};
	};
	
	if($self->{'isCloning'}) {
		if(defined $computer) {
			$computer->{'ip'} = $ip;
			$self->{'ipToMac'}->{$ip} = $mac;

			if($action eq 'iready') {
				$computer->{'status'} = 'ready';
				if(scalar (grep {  $_->{'status'} eq 'ready' } values %{$self->{'macs'}})
					== scalar keys %{$self->{'macs'}}) {
					if(!defined $self->{'cloningRun'}) {
						$self->{'DEBUGGER'}->print_message($self, "All computers ready, starting cloning script.");
						$self->startCloningScript();
					}
					else {
						warn "<ERROR> ".$self->{'DEBUGGER'}->make_message($self, "Logical error: computer reported 'ready' after script was launched.");
					};
				}
				return '', 'Status' => 200;
			}
			else {
			 	return 'Unknow action', 'Status' => 404, 'Content-Type' => 'text/plain';
			};
		}
		else {
		 	return 'Unknow computer', 'Status' => 404, 'Content-Type' => 'text/plain';
		};
	}
	else {
		return 'Cloning not run', 'Status' => 404, 'Content-Type' => 'text/plain';
	};
};

sub wol {
	my ($self, @computers) = @_;
	my $wol_cmd = '/usr/bin/wakeonlan -i %ip% %mac%'; #TODO Move to Config
	#Check availability for script
	warn "<ERROR> ".$self->{'DEBUGGER'}->make_message($self, "Unable to locate WakeOnLan script in: $wol_cmd") 
		and return 
	unless -e (split " ", $wol_cmd)[0]; 
	
	foreach my $id (@computers)
	{
		my $cmd = $wol_cmd;
		my ($ip, $mac) = @{$self->{'classes'}->getComputerStruct($id)}{'ip','mac'};
		$ip =~ s/\.\d+$/\.255/;
		$wol_cmd =~ s/%ip%/$ip/;
		$wol_cmd =~ s/%mac%/$mac/;
		`$wol_cmd`;
		$self->{'DEBUGGER'}->print_message($self,"WakeOnLan: $ip $mac");
	}
}


package IAD::Cloning::State;
#Класс реализует состояние процесса клонирования
use common::sense;
use Storable qw/dclone/;

#Инициализация
sub new {
	my($class, %conf) = @_;
	my $self = bless {}, $class;
	return $self->clear()->set('notRunned');
};

#Очистка списка состояний
sub clear {
	my($self) = @_;
	$self->{'log'} = [];
	return $self
};

#Добавление нового состояние
sub set {
	my($self, $state, @params) = @_;
	$self->{'state'} = $state;
	push @{ $self->{'log'} }, [time(), $state, @params];
	return $self
};

#Обновление предыдущего состояния
sub updateLast {
	my($self, @params) = @_;
	$self->{'log'}->[-1] = [(@{$self->{'log'}->[-1]})[0..1], @params];
	return $self;
};

#Получение текущего состояния
sub get {
	return $_[0]->{'state'};
};

#Получение всех зарегистрированных состояний
sub getLog {
	return dclone $_[0]->{'log'};
};

1;
