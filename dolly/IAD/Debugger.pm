package IAD::Debugger;
#Класс вывода дебажных сообщений и записи логов
#По сути это все обертка вокруг Log::Dispatch, с некоторыми изменениями и парой новых функций
use common::sense;
use Carp qw(croak carp confess cluck);

#Логика логирования, вывода ошибок, и дебаг сообщений

sub new {
	my($class, $mode) = @_;
	my $self = {
		'mode'  => $mode,
		'rules' => [],
		 LOGGER	=> IAD::Debugger::Logger->new(),
	};
	return bless $self, $class;
};

#Выброс ошибки с записью в логи и закрытием программы
#В дебаге backtrace выводится
sub FATAL_ERROR {
	my ($self) = shift;
	my $message = $self->make_error('FATAL_ERROR', shift, @_);
	$self->{LOGGER}->logger->log( level => 'emergency', message => $self->current_date.$message);
	confess() if $self->is_ON; #Более полный вывод информации в режиме дебага
	croak();
}

#Выброс ошибки с записью в логи
#В дебаге backtrace выводится
sub ERROR {
	my ($self) = shift;
	my $message = $self->make_error('ERROR', shift, @_);
	$self->{LOGGER}->logger->log( level => 'error', message => $message);
	cluck() if $self->is_ON; #Более полный вывод информации в режиме дебага	
}

#Запись в лог
sub LOG {
	my ($self, @params) = @_;
	my $message = $self->make_message(@params);
	my $level = 'notice';
	#Запись в логи и вывод на экран
	$level = 'debug' if $self->is_ON;
	$self->{LOGGER}->logger->log( level => $level, message => $self->make_message(@params));
}

#Вывод debug сообщения с фильтром по правилам
sub DEBUG {
	my ($self, $rules, @params) = @_;
	return unless $self->is_ON() and !$self->exist_rules(@{$rules});
	#Перед выводом добавлена проверка на то что нет соответствующего правила
	#Допустим если при запуске демона было введено правило --debug --rules "notices"
	#То все вызовы этого метода в параметрах которого указано такое правило, будут без вывода закрываться
	$self->{LOGGER}->logger->log( level => 'debug', message => $self->current_date.'[DEBUG] '.$self->make_message(@params));
}

sub is_ON {
	my ($self) = @_;
	return $self->{'mode'} eq 'debug';
}

sub set_debug_ON {
	my ($self) = @_;
	$self->{LOGGER}->set_debug_ON();
	return $self->{'mode'} = 'debug';
}

sub set_debug_OFF {
	my ($self) = @_;
	$self->{LOGGER}->set_debug_ON();
	return $self->{'mode'} = 'no_debug';
}

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

sub current_date(){
	my ($self) = @_;
	#Time in format 2012-04-06 03:40:44
	my ($year, $month, $day, $hour, $min, $sec) = (localtime)[5,4,3,2,1,0];
	return sprintf "%4d/%02d/%02d %02d:%02d:%02d ", $year+1900, $month+1, $day, $hour, $min, $sec;
}

sub make_error{
	my ($self, $error_type, @params) = @_;
	my $message = "<$error_type> ".$self->make_message(@params);
	return $self->current_date.$message;
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

package IAD::Debugger::Logger;

#Класс обертка над Log::Dispatch
#Используется Log::Dispatch::File::Rolling для ротации логов
#
#TODO Сделать удаление старых лог файлов
#
use Log::Dispatch::File::Rolling;
use Log::Dispatch::Screen;

sub new {
	my ($class) = shift;
	my $logger 	= Log::Dispatch->new();
	my $file 	= $class->get_file();
	my $screen 	= $class->get_screen('screen', 'warning', 'alert');
	$logger->add($file);
	$logger->add($screen);
	return bless { logger => $logger, }, $class;
}

#просто проброс в Debugger
sub log{	
	my $self = shift;
	return $_[0]->logger->log(@_);
}

sub logger {
	#Чтобы фигурные скобки не писать
	return $_[0]->{logger};
}

sub set_debug_ON{
	my ($self) = @_;
	return $self->logger->add($self->get_screen('debug','debug','notice'));
}

sub set_debug_OFF{
	my ($self) = @_;
	return $self->logger->remove('debug');
}

sub get_screen {
	my ($self, $name, $min_level, $max_level) = @_;
	return Log::Dispatch::Screen->new(
											name      => $name,
											min_level => $min_level // 'warning',
											max_level => $max_level // 'alert',
											stderr	  => 1,
											newline   => 1,
											);
}

sub get_file {
	my ($self) = @_;
	return Log::Dispatch::File::Rolling->new(
											name      => 'main_log',
											min_level => 'notice',
											filename  => 'logs/dolly-%d{yyyy-MM-dd}.log',
											#Ротация по суткам
											mode      => 'append',
											newline   => 1,
											);
}

# Inner logic on log_level (use only: 0,2,3 in code please)
#		debug -> 	   stderr if debug
#		 info -> 	   stderr if debug
#	   notice -> logs, stderr if debug
#	  warning -> logs, stderr always
#	    error -> logs, stderr always
#	 critical -> logs, stderr always
#	    alert -> logs, stderr always
#	emergency -> logs, # For 'die'

1;
