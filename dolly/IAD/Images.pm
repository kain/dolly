package IAD::Images;
#Класс реализует логику образов
use common::sense;

our ($DEBUGGER, @RULES) = ($DI::DEBUGGER, qw/all/);

#создание объекта
sub new {
	my($class) = @_;
	
	my $self = {
		'db' => $DI::db,
		'images' => {},
	};
	$self = bless $self, $class;
	$self->init();
	return $self;
};

#Инициализация, получение всех образов из базы данных
sub init {
	my($self) = @_;
	my $data = $self->{'db'}->getAllImages();
	$self->{'images'} = { map { $_->[0] => {
		'name' => $_->[1],
		'path' => $_->[2],
		'addDate' => $_->[3] } } @$data 
	};
};

#Возвращает список всех образов
sub getMap {
	my($self) = @_;
	return [map { {'imageId' => $_, %{ $self->{'images'}->{$_} } } } sort { $a <=> $b } keys %{ $self->{'images'} } ];
};

#Добавление нового образа
sub addImage {
	my($self, $name, $path, $addDate) = @_;
	$addDate //= time();
	my $imageId = $self->{'db'}->addImage($name, $path, $addDate);
	if(defined $imageId) {
		$self->{'images'}->{$imageId} = {'name' => $name, 'path' => $path, 'addDate' => $addDate};
	};
	return ($imageId, $addDate);
};

#Получение путя к образу
sub getImagePath {
	my($self, $imageId) = @_;
	if(exists $self->{'images'}->{$imageId}) {
		return $self->{'images'}->{$imageId}->{'path'};
	}
	else {
		die $DEBUGGER->make_error('FATAL_ERROR', $self, "Tried to get image path with wrong ID:<$imageId>.");
	};
};

#Удаление образа
sub deleteImage {
	my($self, $imageId) = @_;
	if(exists $self->{'images'}->{$imageId}) {
		$self->{'db'}->deleteImage($imageId);
		delete $self->{'images'}->{$imageId};
	}
	else {
		die $DEBUGGER->make_error('FATAL_ERROR', $self, "Tried to delete image with wrong ID:<$imageId>.");
	};
};

1;