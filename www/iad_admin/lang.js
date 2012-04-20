var lang = {
	langs: {
		'en': 'English',
		'ru': 'Русский',
	},
	default: {
		'dateFormat': 'm/d/Y H:i',
		//cloning states
		'cloningState.notRunned': 'Cloning not run',
		'cloningState.waitAllReady': 'Cloning process started, waiting all computers ready state',
		'cloningState.runned': 'Cloning script started',
		'cloningState.waitConnections': 'Wait connection of all computers [%s/%s]',
		'cloningState.transfering': 'Transfering image %s: %s%',
		'cloningState.complete': 'Cloning successfully finished',
		'cloningState.canceled': 'Cloning aborted',
		'cloningState.error': 'An error occurred: %s',
		'cloningState.allready': 'All computers successfully booted',
		
		//additional imaging states
		'cloningState.imaging.waitAllReady': 'Creating image process started, wait computer ready state',
		'cloningState.imaging.runned': 'Creating image script started',
		'cloningState.imaging.complete': 'Creating image successfully finished',
		'cloningState.imaging.canceled': 'Creating image aborted',
		'cloningState.imaging.scanning': 'Scanning partition #%s: %s%',
		'cloningState.imaging.scanned': 'Scanning completed, space used: %s (%s%)',
		'cloningState.imaging.saving': 'Saving partition #%s to image: %s%',

		//computer status
		'computerStatus.none': 'Need to reboot computer with PXE boot',
		'computerStatus.booting': 'Booting over PXE',
		'computerStatus.ready': 'Ready for cloning',
		'computerStatus.connecting': 'Wait for connection to udp-sender',
		'computerStatus.connected': 'Connected to udp-sender',
		'computerStatus.cloning': 'Cloning',
		'computerStatus.complete': 'Cloning complete',
		'computerStatus.disconnected': 'Computer disconnected',

		//addtional computer imaging status
		'computerStatus.imaging.ready': 'Booted',
		'computerStatus.imaging.connecting': 'Wait for connection to ?',
		'computerStatus.imaging.connected': 'Connected to ?',
		'computerStatus.imaging.imaging': 'Creating image',
		'computerStatus.imaging.complete': 'Image created',
	},
	current: 'en'
};




function setLang(langName) {
	document.write('<script type="text/javascript" src="lang/' + langName + '.js"></scr' + 'ipt>');
	lang.current = langName;
};

function _() { //gettext analog
	var str, result; 
	for(idx in arguments) {
		str = arguments[idx];
		
		if(lang.current != 'en') {
			if(lang[lang.current][str]) {
				result = lang[lang.current][str]; //lang str or lang states
			}
			else if(lang.default[str]) {
				console.log('not translated state', "'" + str + "'");
				result = lang.default[str] //en states ?
			};
		}
		else {
			if(lang.default[str]) {
				result = lang.default[str]; //en states
			};
		};
		if(result) {
			return result;
		}
		else if(idx == arguments.length - 1) {
			if(lang.current == 'en') {
				return str; //plain en
			}
			else {
				console.log('not translated', "'" + str + "'");
				return str; //not translated
			};
		};
	};
};


Ext.state.Manager.setProvider(new Ext.state.CookieProvider());
var langId;
if(langId = Ext.state.Manager.get('lang')) {
	if(langId != 'en') {
		setLang(langId);
	};
}
else {
	Ext.state.Manager.set('lang', 'en');
};