package IAD::Cloning;
#Класс реализующий логику клонирования(и снятия) образа на целевые компьютеры
use common::sense;
use File::Slurp qw/slurp/;
use AnyEvent::Run;

our ($DEBUGGER, @RULES) = ($DI::DEBUGGER, qw/cloning all/);

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
		'maxBackLog' => 10*1024,
		'cloningScriptState' => {},
		'wolRun' => undef,
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
	push my @R, @RULES;

	if($self->{'isCloning'}) {
		$DEBUGGER->ERROR($self,
			"Logical error, unable to start cloning, it seems already started.");
		return undef;
	}
	else {
		$self->{'isCloning'} = 1;
		$self->{'mode'} = $mode; # cloning || imaging
		$self->{'state'}->clear();
		$self->{'ipToMac'} = {};
		$self->{'cloningScriptState'}->{'finished'} = 0;
		
		my (@comp_name, @comp_id, $mode_str, $action_str);

		foreach my $mac (keys %{$self->{'macs'}}){
			push @comp_name, $self->{'macs'}->{$mac}->{name};
			push @comp_id,	 $self->{'macs'}->{$mac}->{computerId};
		}	

		if($mode ne 'maintenance'){
			my $image_path;

			if($mode eq 'cloning') {
				$self->{'imageId'} = $params[0];
				$image_path	= $self->{'imagePath'} = $self->{'images'}->getImagePath($self->{'imageId'});
			}
			elsif($mode eq 'imaging') {
				$self->{'cloningScriptState'}->{'partition'} = 0;
				$self->{'imagingMac'} = (keys %{ $self->{'macs'} })[0];
				(undef, $image_path) = ($self->{'imageName'}, $self->{'imagePath'}) = @params;
			};
			$mode_str 	= "cloning process, mode:[$mode] image path:[$image_path]";
			$action_str = "clone";
		}
		else{
			$mode_str	= "maintenance";
			$action_str = "maintain";

			$self->startWolScript(@comp_id);
		}

		$DEBUGGER->LOG( '#'x15, " Starting $mode_str");
		$DEBUGGER->LOG( "Computers to $action_str:\n",' 'x20,
							 join ', ', sort @comp_name);

		$self->{'cloningScriptLog'} = [];

		$self->{'state'}->set('waitAllReady') and return unless $mode eq 'maintenance';
		$self->{'state'}->set('waitAllReadyMaint');
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

	if ($self->{'mode'} ne 'maintenance'){
		$DEBUGGER->LOG( "Cloning process stopped. State:[", $state // 'canceled', '].' );
		if ($state eq 'error'){
			my @state_log;
			foreach my $log (@{$self->{'state'}->{'log'}}){
				push @state_log, @{$log};
			}
			$DEBUGGER->LOG( "State log:\n\t", join "\n\t", @state_log );
		}
	}
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
	my($self, $out) = @_;
	push my @R, @RULES;

	#Старые логи, просто вывод от скриптов
	# my $LOGFH;
	# my $logfile = $self->{'logfile'} if exists ($self->{'logfile'});
	# if(!exists $self->{'logfile'}) {
	# 	$self->{'logfile'} = $logfile = 'logs/'.time().'.log';
	# 	$DEBUGGER->DEBUG([@R], $self, "Logfile created:[$logfile]");
	# };
	# open $LOGFH, '>>', $logfile
	# 		or $DEBUGGER->FATAL_ERROR($self, "Could not open log file:[$logfile]. $!");

	# print { $LOGFH } ($DEBUGGER->current_date.$log, "\n");
	# close $LOGFH;
	$DEBUGGER->DEBUG([@R, qw/cloning_script/], $self, '[SCRIPT] ', $out);

	shift @{$self->{'cloningLog'}}
		if scalar @{$self->{'cloningLog'}} == $self->{'maxBackLog'};
		
	push(@{$self->{'cloningLog'}}, $out);
	if($self->{'mode'} eq 'cloning') {
		push @R, qw/cloning_udp/;
		given($out) {
			when(/^New connection from ((?:\d{1,3}\.){3}\d{1,3})\s+\(#\d+\) \d+/) {
				my $ip = $1;
				if(exists $self->{'ipToMac'}->{$ip}) {
					$self->{'macs'}->{$self->{'ipToMac'}->{$ip}}->{'status'} = 'connected';
					$self->{'state'}->updateLast(scalar (grep {  $_->{'status'} eq 'connected' } values %{$self->{'macs'}}),
												 scalar (grep {  $_->{'status'} ne 'disconnected' } values %{ $self->{'macs'} }));

					$DEBUGGER->DEBUG([@R],$self,"[UDP] Computer:[$ip] Status:[connected].");
				}
				else {
					$DEBUGGER->ERROR($self,
						"[UDP] Recieved connection from unregistred computer:[$ip] something went wrong.");
				};
			}
			when(/^Disconnecting #\d+ \(((?:\d{1,3}\.){3}\d{1,3})\)/) {
				my $ip = $1;
				if($self->{'cloningScriptState'}->{'transfering'}) {
					$self->{'macs'}->{$self->{'ipToMac'}->{$ip}}->{'status'} = 'disconnected';

					#TODO Сообщение которого никогда не будет с текущей логикой, и порядком инфы от udp-sender'a
					$DEBUGGER->DEBUG([@R],$self,"[UDP] Computer:[$1] Status:[disconected].");
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

				$DEBUGGER->LOG("[UDP] Image transfering started:",
											"[$self->{'cloningScriptState'}->{'image'}]",
											" size:[$self->{'cloningScriptState'}->{'imageSize'}].");
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

				$DEBUGGER->DEBUG([@R],$self,"[UDP] Transfered bytes:[$bytes].");
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
		pop @R and push @R, qw/cloning_ntfs/;
		given($out) {
			when(/^ntfsclone v\d/) {
				$self->{'macs'}->{$self->{'imagingMac'}}->{'status'} = 'imaging';
				$self->{'cloningScriptState'}->{'partition'}++;
			}
			when(/^Scanning volume \.{3}/) {
				$self->{'state'}->set('scanning', $self->{'cloningScriptState'}->{'partition'}, '0.00');

				$DEBUGGER->LOG( "Partition: $self->{'cloningScriptState'}->{'partition'}");
			}
			when(/^\s*?([0-9.]+) percent completed/) {
				my $percent = $1;
				given($self->{'state'}->get()) {
					when(['scanning', 'saving']) {
						$self->{'state'}->updateLast($self->{'cloningScriptState'}->{'partition'}, $percent);

						$DEBUGGER->DEBUG([@R],$self,"[NTFS] [", ucfirst ($self->{'state'}->get()),
															"] Percent completed:[$percent%].");
					}
				};
			}
			when(/^Space in use\s+: (\d+ MB) \(([0-9.]+)%\)/) {
				$self->{'state'}->set('scanned', $1, $2);

				$DEBUGGER->LOG("[NTFS] Space in use:[$1] $2%.");
			}
			when(/^Saving NTFS to image \.{3}/) {
				$self->{'state'}->set('saving', $self->{'cloningScriptState'}->{'partition'}, '0.00');

				$DEBUGGER->LOG("[NTFS] Saving to partition #$self->{'cloningScriptState'}->{'partition'}.");
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
	push my @R, @RULES;

	if(defined $self->{'cloningRun'}) {
		$DEBUGGER->FATAL_ERROR($self, 
			"Attempted to run script when it was already runned.");
	}
	else {
		my $cloningCmd = $self->{'mode'} eq 'cloning'
			? $IAD::Config::clone_upload_image_cmd
			: $IAD::Config::clone_make_image_cmd;	
		my $ipList = join ' ' , map { $_->{'ip'} } values %{$self->{'macs'}};
		$cloningCmd =~ s/%ips?%/$ipList/g;
		$cloningCmd =~ s/%image%/$self->{'imagePath'}/g;
		$self->parseLog('run cmd ' . $cloningCmd . ' ' . time());
		
		$DEBUGGER->LOG( "Launching command:[$cloningCmd]");
		$self->{'cloningRun'} = AnyEvent::Run->new(
	        cmd      => $cloningCmd,
	        on_read  => sub {
	            my $handle = shift;
	            my $data = delete $handle->{'rbuf'};
				$self->parseLog($_) foreach split(/\r|\n/, $data);
	        },
	        on_eof	 => sub {
				if($self->{'cloningScriptState'}->{'finished'}) {
					
					$DEBUGGER->LOG( "Cloning script finished normally.");
	        		$self->end('complete');
	        	}
	        	else {
	        		
	        		$DEBUGGER->ERROR($self, 
	        			"Cloning script finished with errors.");
	        		$self->end('error', 'EOF from script');
	        	};
	        },
	        on_error => sub {
	            my ($handle, $fatal, $msg) = @_;
				$self->parseLog('cloning script error ' . $msg . ' ' . time());

	            $DEBUGGER->ERROR($self,
	            	"Script run error. AnyEvent::Run::on_error FATAL: $fatal, msg: $msg.");
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
	push my @R, @RULES;

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

	$DEBUGGER->DEBUG([@R, qw/cloning_http/], $self, "HTTP request: Action:<$action> mac:<$mac> ip:<$ip>.");
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
						if ($self->{'mode'} ne 'maintenance'){
							$DEBUGGER->DEBUG([@R], $self, "All computers ready, starting cloning script.");
							$self->startCloningScript();
						}
						else {
							$DEBUGGER->DEBUG([@R], $self, "All computers ready.");
							$self->{'state'}->set('allready');
						}
					}
					else {
						$DEBUGGER->ERROR($self,
							"Logical error: computer reported 'ready' after script was launched.");
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

sub startWolScript {
	my ($self, @computers) = @_;
	push my @R, @RULES, qw/cloning_wol/;

	my $wol_cmd = '/usr/bin/wakeonlan'; #TODO Move to Config
	#Check availability for script
	$DEBUGGER->ERROR($self,
		"Unable to locate WakeOnLan script in: $wol_cmd") 
		and return 
	unless -e (split " ", $wol_cmd)[0]; 
	
	$self->{'wolRun'} = AnyEvent::Run->new(
	cmd  => sub {
		foreach my $id (@computers){
			my $cmd = $wol_cmd;
			my ($ip, $mac) = @{$self->{'classes'}->getComputerStruct($id)}{'ip','mac'};
			$ip =~ s/\.\d+$/\.255/;
			print `$wol_cmd -i $ip $mac`;
			select undef, undef, undef, 0.25; #Sleep 0.25 for broadcast storm def
		}
	},
	on_read  => sub {
		my $handle = shift;
	    my $data = delete $handle->{'rbuf'};
	    chomp($data);
		$DEBUGGER->DEBUG([@R], "[WoL] ", $data);
	},
	on_eof	 => sub {
		$DEBUGGER->DEBUG([@R], "Wake-on-lan finished.");
	},
	on_error => sub {
		my ($handle, $fatal, $msg) = @_;
			$DEBUGGER->ERROR("[WoL] Script error. AnyEvent::Run::on_error FATAL: $fatal, msg: $msg.");
		},
	);
}


package IAD::Cloning::State;
#Класс реализует состояние процесса клонирования
use common::sense;
use Storable qw/dclone/;

our ($DEBUGGER, @RULES) = ($DI::DEBUGGER, qw/cloning all/);

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

	$DEBUGGER->DEBUG([@RULES], $self, "Cloning state changed to:[$state].");

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
