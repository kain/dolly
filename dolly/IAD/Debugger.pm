package IAD::Debugger;
#Класс вывода дебажных сообщений
use common::sense;

sub new {
	my($class, $mode) = @_;
	my $self = {
		'mode'  => $mode,
		'rules' => [],
	};
	return bless $self, $class;
};

sub set_rules {
	my ($self, @rules) = @_;
	return push @{$self->{'rules'}}, @rules;
}

sub exist_rules {
	my ($self, @rules) = @_;
	foreach my $rule (@{$self->{'rules'}}){
		foreach my $m_rule (@rules){
			return 1 if $rule eq $m_rule;
		}
	}
}

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

sub current_date(){
	my ($self) = @_;
	#Time in format 2012-04-06 03:40:44
	my ($year, $month, $day, $hour, $min, $sec) = (localtime)[5,4,3,2,1,0];
	return sprintf "%4d-%02d-%02d %02d:%02d:%02d ", $year+1900, $month+1, $day, $hour, $min, $sec;
}

sub make_error{
	my ($self, $error_type, @params) = @_;
	return $self->current_date."<$error_type> ".$self->make_message(@params);
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
	return "[$class] ".(join "", @message);
}

sub print_message{
	my ($self, $rules, @params) = @_;
	return unless $self->is_ON() and !$self->exist_rules(@{$rules});
	#Перед выводом добавлена проверка на то что нет соответствующего правила
	#Допустим если при запуске демона было введено правило --debug --rules "notices"
	#То все вызовы этого метода в параметрах которого указано такое правило, будут без вывода закрываться
	print $self->current_date.$self->make_message(@params),"\n";
}

sub print_var{
	my ($self, $rules, @params) = @_;
	return unless $self->is_ON() and !$self->exist_rules(@{$rules});;
	#Если первый аргумент ссылка, то считаем её ссылкой на класс
	my $class = shift @params if ref($params[0]);
	my ($var, $ref) = @params;
	if (defined $class){
		$ref = \$class->{$var};
		return $self->print_message($rules, $class, "VAR:$var VAL:${$ref}");
	}
	$self->print_message($rules, "VAR:$var VAL:${$ref}");
}

1;
