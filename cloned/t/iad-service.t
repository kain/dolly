use Test::Simple 'no_plan';
use IAD::Service;
use Data::Dumper;

IAD::Service::register('test', {test => 42});
ok($IAD::Service::test->{'test'} == 42, 'register');