use common::sense;

use AE;
#use AnyEvent::Impl::Perl;
use AnyEvent::Run;
use Data::Dumper;
use Test::Simple 'no_plan';


my $handle;
my $timerAfter = AE::timer 1, 0, sub {
	$handle = AnyEvent::Run->new(
        cmd      => 'perl t/test-cmd.pl',
        on_read  => sub {
            my $handle = shift;
            my $data = delete $handle->{'rbuf'};
            given($data) {
            	when(/STDOUT/) {
            		ok(1, 'stdout');
            		$handle->push_write("1111\n");
            	}
            	when(/first/) {
            		ok($data =~ /1111/, 'got first');
            	}
            };
        },
        on_eof => sub {
        	warn "cmd exit"
        },
        on_error  => sub {
            my ($handle, $fatal, $msg) = @_;
            print "ERROR $fatal $msg\n";
            #...
            #$cv->send;
        },
    );
    
    # Send data to the process's STDIN
    #$handle->push_write($data);
};

AE->cv->recv;