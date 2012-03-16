package IAD::Config;
#Класс реализует управление настройками
use common::sense;

#Стандартные настройки
sub getDefault {
	return {
		'ipxe_normal_boot' => './ipxe/normalboot',
		'ipxe_network_boot' => './ipxe/networkboot',
		'clone_make_image_cmd' => '/usr/local/bin/dolly -m save -t "%ip%" "%image%"',
		'clone_upload_image_cmd' => '/usr/local/bin/dolly -m restore -t "%ips%" "%image%"',
		'auto_update_ip' => 1,
		'add_new_to_group' => undef,
	};
};

#Список всех ключей
our @NAMES = sort keys %{getDefault()};

#Применение настроек
sub set {
	my($config) = @_;
	foreach(keys%$config) {
		${$_} = $config->{$_};
	};
};

#Получение текущих настроек
sub get {
	my $config = {};
	foreach(@NAMES) {
		$config->{$_} = ${$_};
	};
	return $config;
};

#Инициализация базы данных
sub create {
	my $db = $DI::db;
	foreach(@NAMES) {
		$db->addConfig($_, ${$_});
	};
};

#Сохранение\обновление настроек
sub save {
	my $db = $DI::db;
	foreach(@NAMES) {
		$db->updateConfig($_, ${$_});
	};
};

#Загрузка настроек из базы
sub load {
	my $db = $DI::db;
	my $config = { map { @$_ } @{$db->getConfig} };
	if(scalar keys %$config) {
		set($config);
	}
	else {
		create();
	};

};

#Загрузка стандартных настроек
set(getDefault());

1;