#!/usr/bin/perl
#$0 = 'Image Auto Deploy Daemon';
$0 = 'IAD Daemon';
use AnyEvent::FCGI;
use common::sense;
use Getopt::Long;

BEGIN {
	use IAD::Debugger;
	use IAD::Service;
		IAD::Service::register('DEBUGGER', IAD::Debugger->new('no_debug'));
}

use IAD::Config;
use IAD::Images;
use IAD::Classes;
use IAD::Cloning;
use IAD::DataBase;
use IAD::AdminAPI;
use IAD::FCGIHandler;

my ($rules, $debug, $help, $list, $dev);

my $result = GetOptions(	"r|rules=s"	=> \$rules,
							"d|debug"	=> \$debug,
							"h|help"	=> \$help,
							"l|list"	=> \$list,
							"dev|developer"	=> \$dev,); #для тестов

usage() and exit(0) if !$result or $help or @ARGV;
usage() and exit(0) if $rules and !$debug;
rules() and exit(0) if $list;

$DI::DEBUGGER->set_debug_ON if $debug;
$DI::DEBUGGER->DEBUG([],'Debug mode ON');
$DI::DEBUGGER->DEBUG([],'Developer mode ON') if $dev;
$DI::DEBUGGER->set_rules(split ' ', $rules) and $DI::DEBUGGER->DEBUG([],"Rules: $rules") if $rules;

IAD::Service::register('db',          IAD::DataBase->new('iad.s3db'));
IAD::Config::load();
IAD::Service::register('classes',     IAD::Classes->new());
IAD::Service::register('images',      IAD::Images->new());
IAD::Service::register('cloning',     IAD::Cloning->new());
IAD::Service::register('adminAPI',    IAD::AdminAPI->new());
IAD::Service::register('FCGIHandler', IAD::FCGIHandler->new());

if($dev) {
	#Скрипты эмуляторы
	IAD::Config::set({
		'ipxe_normal_boot' => './ipxe/normalboot',
		'ipxe_network_boot' => './ipxe/networkboot',
		'clone_make_image_cmd' => 'perl t/test-cloning.pl t/imaging.log "%ip%" "%image%"',
		'clone_upload_image_cmd' => 'perl t/test-cloning.pl t/dolly_restore.txt "%ips%" "%image%"'
	});
};

my $fcgi = AnyEvent::FCGI->new(port => 9000, on_request => sub { $DI::FCGIHandler->handleRequest(@_) });

AnyEvent->condvar->recv;



sub usage {
	print <<__USAGE__;
Usage
	iad_daemon [-d|--debug] [-r|--rules "rules separeted by space"]
Options
	-d|--debug
	    shows debug information
	-r|--rules
	    add rules to filter debug messages (uses only with --debug)
	    use -l|--list to see list of rules
__USAGE__
}

sub rules {
	print <<__RULES__;
currently available rules:
    admin, cloning, classes 
       	- blocks all messages from relevant class
    admin_spam 				
       	- blocks getNotice and getCloningState messages from web interface
    cloning_logs 			
      	- blocks messages that goes to logs
    cloning_http			
       	- blocks messages about http-requests to clonings class
    cloning_wol				
       	- blocks messages about wakeOnLan
    cloning_udp | cloning_ntfs
    	- blocks info from cloning or imaging process
__RULES__
}