package IAD::FCGIHandler;
use common::sense;
use URI;
use Time::HiRes;

sub new {
	my($class) = @_;
	my $self = {'adminAPI' => $DI::adminAPI, 'cloning' => $DI::cloning};
	return bless $self, $class;
};
sub handleRequest {
	
    my($self, $request) = @_;
    
	my $uri = URI->new($request->param('DOCUMENT_URI'));
	$uri->query($request->param('QUERY_STRING'));
	my $method = $request->param('REQUEST_METHOD');
	if(AnyEvent::WIN32) {
		warn 'FCGI::', $method, ' ', $uri->as_string(), ' at ', Time::HiRes::time();
	};
	my $content = '';
	
	while(my $buf = $request->read_stdin(8192)) {
		$content .= $buf;
	};
	
	my $uriPath = $uri->path();
	if($method eq 'POST' && $uriPath =~ /^\/iad_admin\/adminAPI(\/.*)$/) {
		$request->respond( $self->{'adminAPI'}->handleRequest($content) );
	}
	elsif($method eq 'GET' && $uriPath =~ /^\/iad_api\/([a-z]+)$/) {
		my @response = $self->{'cloning'}->handleRequest($1, {$uri->query_form()});
		if(AnyEvent::WIN32) {
			use Data::Dumper;
			warn Dumper(\@response);
		};
		$request->respond( @response );
	}
	else {
    	$request->respond('', 'Status' => 404);
    };
};

1;