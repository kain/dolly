package IAD::FCGIHandler;
#Класс реализует базовый обработчик подключений через FastCGI
use common::sense;
use URI;
use Time::HiRes;

our ($DEBUGGER, @RULES) = ($DI::DEBUGGER, qw/fcgi all/);

#Создание объекта
sub new {
	my($class) = @_;
	my $self = {'adminAPI' => $DI::adminAPI, 'cloning' => $DI::cloning,};
	return bless $self, $class;
};

#Обработка запросов, в зависимости от типа запросов перенаправляет обработку IAD::adminAPI или IAD::Cloning
sub handleRequest {
	
    my($self, $request) = @_;
    
	my $uri = URI->new($request->param('DOCUMENT_URI'));
	$uri->query($request->param('QUERY_STRING'));
	my $method = $request->param('REQUEST_METHOD');
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
		$request->respond( @response );
	}
	else {
    	$request->respond('', 'Status' => 404);
    };
};

1;