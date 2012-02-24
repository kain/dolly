package IAD::Cloning;
use common::sense;
use File::Slurp qw/slurp/;
use AnyEvent::Run;

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
	}, $class;
	return $self;
};

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
			#use Data::Dumper;
			#print Dumper($computer);
		};
	};
};

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

sub getComputersState {
	my($self) = @_;
	my $state = {};
	foreach my $computer(values %{$self->{'macs'}}) {
		$state->{$computer->{'computerId'}} = { map { $_ => $computer->{$_} } ('status','ip') };
	};
	return $state;
};

sub start {
	my($self, $mode, @params) = @_;
	if($self->{'isCloning'}) {
		warn 'logic error, start when isCloning';
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

my @clientStatus = (
	'none',
	'booting',
	'ready',
	'connecting',
	'connected',
	'cloning',
	'complete'
);

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
#			when(/^ntfsclone v\d/) {
#				$self->{'macs'}->{$self->{'imagingMac'}}->{'status'} = 'imaging';
#				$self->{'cloningScriptState'}->{'partition'}++;
#			}
#			when(/^Scanning volume \.{3}/) {
#				$self->{'state'}->set('scanning', $self->{'cloningScriptState'}->{'partition'}, '0.00');
#			}
#			when(/^\s*?([0-9.]+) percent completed/) {
#				my $percent = $1;
#				given($self->{'state'}->get()) {
#					when(['scanning', 'saving']) {
#						$self->{'state'}->updateLast($self->{'cloningScriptState'}->{'partition'}, $percent);
#					}
#				};
#			}
#			when(/^Space in use\s+: (\d+ MB) \(([0-9.]+)%\)/) {
#				$self->{'state'}->set('scanned', $1, $2);
#			}
#			when(/^Saving NTFS to image \.{3}/) {
#				$self->{'state'}->set('saving', $self->{'cloningScriptState'}->{'partition'}, '0.00');
#			}
			when(/^Saving partition /){
				$self->{'macs'}->{$self->{'imagingMac'}}->{'status'} = 'imaging';
				$self->{'cloningScriptState'}->{'partition'}++;
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

sub mathPercent {
	my($self, $complete, $all) = @_;
	return undef if !defined $all || $all == 0;
	return sprintf("%.1f", $complete / $all * 100);
};

sub startCloningScript {
	my($self) = @_;
	if(defined $self->{'cloningRun'}) {
		die 'cloning script already runned';
	}
	else {
		my $cloningCmd = $self->{'mode'} eq 'cloning'
			? $IAD::Config::clone_upload_image_cmd
			: $IAD::Config::clone_make_image_cmd;
			
		my $ipList = join ' ' , map { $_->{'ip'} } values %{$self->{'macs'}};
		
		$cloningCmd =~ s/%ips?%/$ipList/g;
		$cloningCmd =~ s/%image%/$self->{'imagePath'}/g;
		
		$self->parseLog('run cmd ' . $cloningCmd . ' ' . time());
		warn "cloning script: ", $cloningCmd;
		
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
	            warn "AE::Run::on_error fatal: $fatal, msg: $msg";
	            $self->end('error', "Error fatal: $fatal, msg: $msg");
	        },
		);
		$self->{'state'}->set('runned');
		$_->{'status'} = 'connecting' foreach values %{$self->{'macs'}};
	};
};	

#sub endCloningScript {
#	my ($self) = @_;
#	$self->{'state'}->set(defined $error ? 'error' : 'complete');
#	
#	#$_->{'status'} = 'complete' foreach values %{ $self->{'macs'} };
#	$self->{'macs'} = {};
#	$self->{'isCloning'} = 0;
#	$self->{'cloningRun'} = undef;
#};

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

	
	warn "http: action $action, mac $mac, ip $ip";
	
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
						warn "all ready, start cloning script";
						$self->startCloningScript();
					}
					else {
						warn "logic error: all computers ready, but cloning script already run";
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

package IAD::Cloning::State;
use common::sense;
use Storable qw/dclone/;

sub new {
	my($class, %conf) = @_;
	my $self = bless {}, $class;
	return $self->clear()->set('notRunned');
};

sub clear {
	my($self) = @_;
	$self->{'log'} = [];
	return $self
};

sub set {
	my($self, $state, @params) = @_;
	$self->{'state'} = $state;
	push @{ $self->{'log'} }, [time(), $state, @params];
	return $self
};

sub updateLast {
	my($self, @params) = @_;
	$self->{'log'}->[-1] = [(@{$self->{'log'}->[-1]})[0..1], @params];
	return $self;
};

sub get {
	return $_[0]->{'state'};
};

sub getLog {
	return dclone $_[0]->{'log'};
};

#package IAD::Cloning::Computer;

1;
