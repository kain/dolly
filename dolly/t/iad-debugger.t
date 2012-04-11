#!/usr/bin/perl
#Тестовый скрипт для класса Debugger
use common::sense;
use Test::More tests => 13;
use Test::Output;
require "../IAD/Debugger.pm";

my $t_class  = TestClass->new('must_be_on_stdout');
my $debugger = IAD::Debugger->new('debug');

isa_ok( $debugger, 'IAD::Debugger');
is( $debugger->{'mode'}, 'debug', 
	"Mode is 'debug'");
ok( $debugger->is_ON(),
	"Debugger is ON, because 'mode' == 'debug'" );

$debugger->set_OFF();

isnt( $debugger->is_ON(), 1, 
	"Debugger is OFF because 'mode' != 'debug'");

stdout_like { $debugger->print_message('Simple message that will not be on STDOUT')}
			qr/^$/,
	"print(message) while debug is OFF";

$debugger->set_ON();

stdout_is { $debugger->print_message('Simple message') } 
			"Simple message\n", 
	"print_message(message)";

stdout_is { $debugger->print_message('Simple message', "\nSecond message") } 
			"Simple message \nSecond message\n", 
	"print_message(message, message)";

stdout_is { $debugger->print_message($t_class) } 
			"<TestClass> REPORTING\n", 
	"print_message(class)";

stdout_is { $debugger->print_message($t_class, "Simple message from TestClass") } 
			"<TestClass> Simple message from TestClass\n", 
	"print_message(class, message)";

my $t_var_s   = 'some_var';
my $t_var_num = 77;
my $t_var_ref = \$t_var_s;


stdout_is { $debugger->print_var('t_var_s', \$t_var_s) }
			"VAR:t_var_s VAL:some_var\n", 
	"print_var(name, var)";

stdout_is { $debugger->print_var('t_var_num', \$t_var_num) }
			"VAR:t_var_num VAL:77\n", 
	"print_var(name, var)";

stdout_like { $debugger->print_var('t_var_ref', \$t_var_ref) }
			qr/VAR:t_var_ref VAL:SCALAR.+/, 
	"print_var(name, ref)";	

stdout_is { $debugger->print_var($t_class, 'data') }
			"<TestClass> VAR:data VAL:must_be_on_stdout\n", 
	"print_var(class, var)";

package TestClass;
{
	sub new {
		my ($class, $some_data) = @_;
		my $self = { 'data' => $some_data, };
		return bless $self, $class; 
	};

	1;
}