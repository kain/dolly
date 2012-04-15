#!/usr/bin/perl
#Тестовый скрипт для класса Debugger
use common::sense;
use Test::More tests => 19;
use Test::Output;
use Test::Warn;

require "../IAD/Debugger.pm";

my $debugger;
my $tc  = TestClass->new('must_be_on_stdout');
my $d = IAD::Debugger->new('no_debug');
my $rgx = qr/20\d\d\/[0-1]\d\/[0-3]\d [0-2]\d:[0-5]\d:[0-5]\d/;
my $msg = "I've fallen, and I can't get up...";

isa_ok($d, 'IAD::Debugger', 'This is Debugger class');
like($d->current_date, $rgx, 'Current date is in ok format');
ok(!$d->is_ON, 'Debug mode is turned off now');

stdout_like {$d->DEBUG([],$msg)}
			qr/^$/,
			'Debug mode is off, so no message';
stderr_like {$d->ERROR($tc, $msg)}
			qr/^$rgx <ERROR> \[TestClass\] $msg\n$/,
			'But even when debug mode is off, errors will go';

$d->set_debug_ON;

ok ($d->is_ON, 'Debug mode now on');

stderr_like {$d->DEBUG([],$tc, $msg)}
			qr/^$rgx \[TestClass\] $msg\n$/,
			'So, now we can see debug message';

$d->set_debug_OFF;

ok (!$d->is_ON, 'Debug mode off again, switch is working');

stderr_like {$d->DEBUG($tc, $msg)}
			qr/^$/,
			'And we can\'t see message again...';

stderr_like {$d->set_debug_ON; $d->DEBUG([],$tc, $msg)}
			qr/^$rgx \[TestClass\] $msg\n$/,
			'And and now we can...';

stderr_like {$d->ERROR($msg)}
			qr/^$rgx <ERROR> $msg\n[.\s]*/,
			'Of course we can see errors in debug mode, with a lot more information in it';

my @rules = qw/logs/;

ok (!$d->exist_rules(@rules), 'No rules yet in class...');

$d->set_rules(@rules);

ok ($d->exist_rules(@rules), 'But now, there are some rules');

stderr_like {$d->DEBUG([],$msg)}
			qr/^$rgx $msg\n$/,
			'This message will go, because no it has no restricting rules...';
stderr_like {$d->DEBUG([@rules],$msg)}
			qr/^$/,
			'But this won\'t, it has some rules that set as forbidden in debugger';
stderr_like {$d->DEBUG([],$tc, $msg)}
			qr/^$rgx \[TestClass\] $msg\n$/,
			'Some format checks... (class, params)';
stderr_like {$d->DEBUG([],$tc, $msg, $msg)}
			qr/^$rgx \[TestClass\] $msg$msg\n$/,
			'Some format checks... (class, params, params)';
stderr_like {$d->DEBUG([],$msg, $msg)}
			qr/^$rgx $msg$msg\n$/,
			'Some format checks... (params, params)';
stderr_like {$d->DEBUG([], $tc)}
			qr/^$rgx \[TestClass\] REPORTING\n$/,
			'Some format checks... (class)';

package TestClass;
{
	sub new {
		my ($class, $some_data) = @_;
		my $self = { 'data' => $some_data, };
		return bless $self, $class; 
	};

	1;
}