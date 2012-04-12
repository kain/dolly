#!/usr/bin/perl
#Тестовый скрипт для класса Debugger
use common::sense;
use Test::More tests => 16;
use Test::Output;
use Test::Warn;

require "../IAD/Debugger.pm";

my $t_class  = TestClass->new('must_be_on_stdout');
my $debugger = IAD::Debugger->new('debug');
my $date_regex = '20\d{2}-[0-1]\d-[0-3]\d [0-2]\d:[0-5]\d:[0-5]\d';


isa_ok( $debugger, 'IAD::Debugger');
is( $debugger->{'mode'}, 
	'debug', 
	"Mode is 'debug'");
ok( $debugger->is_ON(),
	"Debugger is ON, because 'mode' == 'debug'" );

like( $debugger->current_date,
	qr/$date_regex/,
	"curren_date is in ok format");

$debugger->set_OFF();

isnt( $debugger->is_ON(), 1, 
	"Debugger is OFF because 'mode' != 'debug'");

stdout_like { $debugger->print_message('Simple message that will not be on STDOUT')}
			qr/^$/,
	"print(message) while debug is OFF";

$debugger->set_ON();

stdout_like { $debugger->print_message('Simple message') } 
			qr/$date_regex Simple message\n/, 
	"print_message(message)";

stdout_like { $debugger->print_message('Simple message', "\nSecond message") } 
			qr/$date_regex Simple message\nSecond message\n/, 
	"print_message(message, message)";

stdout_like { $debugger->print_message($t_class) } 
			qr/$date_regex \[TestClass\] REPORTING/, 
	"print_message(class)";

stdout_like { $debugger->print_message($t_class, "Simple message from TestClass") } 
			qr/$date_regex \[TestClass\] Simple message from TestClass\n/, 
	"print_message(class, message)";

my $t_var_s   = 'some_var';
my $t_var_num = 77;
my $t_var_ref = \$t_var_s;


stdout_like { $debugger->print_var('t_var_s', \$t_var_s) }
			qr/$date_regex VAR:t_var_s VAL:some_var\n/, 
	"print_var(name, var)";

stdout_like { $debugger->print_var('t_var_num', \$t_var_num) }
			qr/$date_regex VAR:t_var_num VAL:77\n/, 
	"print_var(name, var)";

stdout_like { $debugger->print_var('t_var_ref', \$t_var_ref) }
			qr/$date_regex VAR:t_var_ref VAL:SCALAR.+/, 
	"print_var(name, ref)";	

stdout_like { $debugger->print_var($t_class, 'data') }
			qr/$date_regex \[TestClass\] VAR:data VAL:must_be_on_stdout\n\s*/, 
	"print_var(class, var)";

warning_like { warn $debugger->make_error('ERROR', $t_class, "Error from test class.") } 
			[qr/$date_regex <ERROR> \[TestClass\] Error from test class\..+$/],
	"warning test while debug is ON";

$debugger->set_OFF();

warning_like {  warn $debugger->make_error('ERROR', $t_class, "Error from test class.") }
			[qr/$date_regex <ERROR> \[TestClass\] Error from test class\..+$/],
	"warning test while debug is OFF";

package TestClass;
{
	sub new {
		my ($class, $some_data) = @_;
		my $self = { 'data' => $some_data, };
		return bless $self, $class; 
	};

	1;
}