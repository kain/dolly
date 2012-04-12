package IAD::Debugger;
#Класс вывода дебажных сообщений
use common::sense;

sub new {
	my($class, $mode) = @_;
	my $self = {
		'mode'  => $mode,
	};
	return bless $self, $class;
};

sub set_ON {
	my ($self) = @_;
	return $self->{'mode'} = 'debug';
}

sub set_OFF {
	my ($self) = @_;
	return $self->{'mode'} = 'no_debug';
}

sub is_ON {
	my ($self) = @_;
	return $self->{'mode'} eq 'debug';
}

sub make_message{
	my ($self, @params) = @_;
	#Если первый аргумент не ссылка то все аргументы воспринимаются 
	#как список сообщений
	return join "", @params unless ref($params[0]);
	#Если первый аргумент - ссылка, то считается что это сообщение от класса
	my ($class, @message) = @params;
	$class = ref($class);
	@message = ("REPORTING") unless @message;
	return "<$class> ".(join "", @message);
}

sub print_message{
	my ($self, @params) = @_;
	return unless $self->is_ON();
	print $self->make_message(@params),"\n";
}

sub print_var{
	my ($self, @params) = @_;
	return unless $self->is_ON();
	#Если первый аргумент ссылка, то считаем её ссылкой на класс
	my $class = shift @params if ref($params[0]);
	my ($var, $ref) = @params;
	if (defined $class){
		$ref = \$class->{$var};
		return $self->print_message($class, "VAR:$var VAL:${$ref}");
	}
	$self->print_message("VAR:$var VAL:${$ref}");
}

1;
