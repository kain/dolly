#!/usr/bin/perl
#$0 = 'Image Auto Deploy Daemon';
$0 = 'IAD Daemon';
use AnyEvent::FCGI;
use common::sense;

use IAD::Debugger;
use IAD::Config;
use IAD::Images;
use IAD::Service;
use IAD::Classes;
use IAD::Cloning;
use IAD::DataBase;
use IAD::AdminAPI;
use IAD::FCGIHandler;

IAD::Service::register('DEBUGGER',    IAD::Debugger->new('no_debug'));

if (@ARGV){
	if ($ARGV[0] eq '--debug'){
		$DI::DEBUGGER->set_ON();
		$DI::DEBUGGER->print_message('Debug mode ON');
	}
	else {
		print "$0: Wrong option '@ARGV'.\nOnly '--debug' key currently allowed.\n";
		exit(0);
	}
}

IAD::Service::register('db',          IAD::DataBase->new('iad.s3db'));
IAD::Config::load();
IAD::Service::register('classes',     IAD::Classes->new());
IAD::Service::register('images',      IAD::Images->new());
IAD::Service::register('cloning',     IAD::Cloning->new());
IAD::Service::register('adminAPI',    IAD::AdminAPI->new());
IAD::Service::register('FCGIHandler', IAD::FCGIHandler->new());

if(AnyEvent::WIN32) {
	#test env
	IAD::Config::set({
		'ipxe_normal_boot' => './ipxe/normalboot',
		'ipxe_network_boot' => './ipxe/networkboot',
		'clone_make_image_cmd' => 'perl t/test-cloning.pl t/imaging.log "%ip%" "%image%"',
		'clone_upload_image_cmd' => 'perl t/test-cloning.pl t/dolly_restore.txt "%ips%" "%image%"'
	});
};

my $fcgi = AnyEvent::FCGI->new(port => 9000, on_request => sub { $DI::FCGIHandler->handleRequest(@_) });

AnyEvent->condvar->recv;