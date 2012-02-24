package IAD::Service;
use common::sense;
#Depency injection simple realisation
sub register {
	my($name, $service) = @_;
	${$name} = $service;
	${'DI::'.$name} = $service; #shortcat
};

1;