


var isImageSelecting = false;
var isCloning = false;
var toCloning = [];
var idsToCloning = [];
var ticket = '';


var taskCheckNotices = {
    run: function() {
    	var task = this;
    	if(!task.runned) {
    		task.runned = true;
	        adminAPI({
	        	data: { 'do': 'getNotices' },
	        	ok: function(reqdata, data) {
					data.notices.forEach(function(notice) {
						if(notice[0] == 'computerAdded') {
							var computer = notice[1];
							var classNode;
							editClassesGrid.getStore().getRootNode().cascadeBy(function(el) {
			        			if(!el.isLeaf() && el.get('classId') == computer.classId) {
									classNode = el;
									return false;
			        			};
			        			return true;
			        		});
			        		if(classNode) {
								if(!classNode.isExpanded()) 
									classNode.expand();
								computer.leaf = true;
								computer.checked = false;
								classNode.appendChild(computer);
			        		};
						}
						else if(notice[0] == 'computerEdited') {
							var computerId = notice[1].id;
							delete notice[1].id;
							var node = editClassesGrid.getStore().getRootNode().findChild('computerId', computerId, true);
							if(node) {
								for(key in notice[1]) {
									node.set(key, notice[1][key]);
								};
								node.commit();
							};
						}
						else if(notice[0] == 'imageAdded') {
							imagesGrid.getStore().add(notice[1]);
						};
					});
					
	        		task.runned = false;
	        	},
		        fail: function(reqdata, fail) {
					Ext.Msg.alert(_('Error'),
						_('An error occurred, recommend reload interface') + '<br/><br/>' + _('Reason: ') + fail,
						function() { task.runned = false }
					);
		        }
	        });
		};
    },
    interval: 5000
};

var taskCheckCloningState = {
    run: function() {
    	var task = this;
    	if(!task.runned) {
    		task.runned = true;
	        adminAPI({
	        	data: { 'do': 'getCloningState' },
	        	ok: function(reqdata, data) {
					updateCloningStateGrid(data.stateLog, data.mode);
					
					if(!data.isCloning) {
	        			stopCloning();
	        			task.runned = false;
	        			return;
	        		};
	        		cloningGrid.getStore().getRootNode().cascadeBy(function(el) {
	        			if(el.isLeaf()) {
	        				el.set('ip', data.computersState[el.get('computerId')].ip);
	        				var status = data.computersState[el.get('computerId')].status;
	        				el.set('status', status);
	        				el.set('statusDesc', data.mode == 'cloning'
	        					? _('computerStatus.' + status)
	        					: _('computerStatus.imaging.' + status, 'computerStatus.' + status)
	        					);
	        				el.commit();
	        			};
	        			return true;
	        		});
	        		task.runned = false;
	        	},
		        fail: function(reqdata, fail) {
					Ext.Msg.alert(_('Error'),
						_('An error occurred, recommend reload interface') + '<br/><br/>' + _('Reason: ') + fail,
						function() { task.runned = false }
					);
		        }
	        });
		};
    },
    interval: 2000
};

//if(true) {
//    Ext.override(Ext.grid.column.Date, {
//        constructor: function() {
//            this.format = Ext.Date.defaultFormat;
//            this.callOverridden(arguments);
//        }
//    });
//}; //fix http://www.sencha.com/forum/showthread.php?144089-4.0.2a-Ext.Date.defaultFormat-is-used-at-define-time-in-Ext.grid.column.Date
Ext.Date.defaultFormat = _('dateFormat');

Ext.onReady(function() {
	
	IADWindow = Ext.getCmp('IADWindow');
	AddComputerWindow = Ext.getCmp('AddComputerWindow');
	AddImageWindow = Ext.getCmp('AddImageWindow');
	
	navTabs = IADWindow.getComponent('navTabs');
	classesTab = navTabs.getComponent('classesTab');
	editClassesGrid = classesTab.getComponent('editClassesGrid');
	
	imagesTab = navTabs.getComponent('imagesTab');
	imagesGrid = imagesTab.getComponent('imagesGrid');
		
	cloningTab = navTabs.getComponent('cloningTab');
	cloningGrid = cloningTab.getComponent('cloningGrid');
	cloningStateGrid = cloningTab.getComponent('cloningStateGrid');
	
	settingsTab = navTabs.getComponent('settingsTab');
	
	AddComputerWindow.hide();
	AddImageWindow.hide();
	
	classesTabHandler();
	imagesTabHandler();
	cloningTabHandler();
	settingsTabHandler();

	Ext.Ajax.url = 'adminAPI/';
	
	init();
});


function classesTabHandler() {
	
	var toolbar = editClassesGrid.getDockedComponent('toolbar');
	
	editClassesGrid.getSelectionModel().setSelectionMode('MULTI');
	
	editClassesGrid.getView().on('beforeitemdblclick', function(node, e) {
		return false;
	}); //disable expand/collapse on dblclick
	

	editClassesGrid.getView().on('beforedrop', function(node, data, over, position) {
		var cancel = false;
		if(position != 'append') {
			data.records.forEach(function(el) {
				if(el.isLeaf()) {
					cancel = true;
					return false;
				};
			});
		}
		else {
			data.records.forEach(function(el) {
				if(!el.isLeaf()) {
					cancel = true;
					return false;
				};
			});
		};
		if(cancel) {
			return false;
		};
	});
	
	editClassesGrid.getView().on('drop', function(node, data, over) {
		var computerIds = [];
		data.records.forEach(function(el) {
			computerIds.push(el.get('computerId'));
		});
		adminAPI({
			data: {
				'do': 'moveComputers',
				toClassId: over.get('classId'),
				ids: computerIds
			},
			ok: function () {
			},
			loadMsg: _('Moving computers')
		});
	});
	
	

	editClassesGrid.on('beforeedit', function(e) {
		if(e.field != 'name' && !e.record.isLeaf())
			return false;
	});

	editClassesGrid.on('edit', function(editor, e) {
		if(e.value != e.originalValue) {
			adminAPI({
				data: {
					'do': e.record.isLeaf() ? 'editComputer' : 'editClass',
					id: e.record.isLeaf() ? e.record.get('computerId') : e.record.get('classId'),
					name: e.record.get('name'),
					mac: e.record.isLeaf() ? e.record.get('mac') : null,
					ip:  e.record.isLeaf() ? e.record.get('ip') : null
				},
				ok: function(reqdata, data) {
					if(e.record.isLeaf())
						e.record.set('mac', data.mac);
					e.record.commit();
				},
				fail: function(reqdata, reason) {
					e.record.reject();
					Ext.Msg.alert(_('Error'), _('Editing canceled, reason:') + '<br/>' + reason);
				},
				loadMsg: _('Saving')
			});
		};
	});
	
	editClassesGrid.on('checkchange', function(node, checked) {
		if(!node.isLeaf()) {
			node.eachChild(function(childnode) {
				childnode.set('checked', checked);
			});
		}
		else {
			if(!checked)
				node.parentNode.set('checked', 0);
		};
	});
	
	toolbar.down('#addClass').on('click', function() {
		Ext.Msg.prompt(_('Add group'), _('Enter group name:'), function(answer, name) {
			if(answer == 'ok') {
				adminAPI({
					data: {
						'do': 'addClass',
						name: name,
					},
					ok: function(reqdata, data) {
						editClassesGrid.getStore().getRootNode().appendChild({name: name,
																			  classId: data.classId,
																			  checked: false,
																			  children: []});
						updateClassesNamesComboBox();
					},
					loadMsg: _('Adding group')
				});
			};
		});
	});
	
	toolbar.down('#addComputer').on('click', function() {
		var selected = editClassesGrid.getSelectionModel().getLastSelected();
		if(selected != null)
		{
			AddComputerWindow.classNode = selected.isLeaf() ? selected.parentNode : selected;
			AddComputerWindow.down('#className').setValue(AddComputerWindow.classNode.get('name'));
			AddComputerWindow.show();
		}
		else
		{
			Ext.Msg.alert(_('Error'), _('You must select class'));
		};
	});
	
	AddComputerWindow.down('#addComputer').on('click', function() {

		adminAPI({
			data: {
				'do': 'addComputer',
				classId: AddComputerWindow.classNode.get('classId'),
				name: AddComputerWindow.down('#name').getValue(),
				mac: AddComputerWindow.down('#mac').getValue(),
				ip: AddComputerWindow.down('#ip').getValue()
			},
			ok: function(reqdata, data) {
				if(!AddComputerWindow.classNode.isExpanded()) 
					AddComputerWindow.classNode.expand();
				
				AddComputerWindow.classNode.appendChild({
					name: reqdata.name,
					mac: data.mac,
					ip: reqdata.ip,
					classId: reqdata.classId,
					computerId: data.computerId,
					leaf: true,
					checked: false
				});
			},
			loadMsg: _('Adding computer')
		});
	});
	
	AddComputerWindow.down('#cancel').on('click', function() {
		AddComputerWindow.hide();
	});
	
	toolbar.down('#deleteChecked').on('click', function() {
		var idsToDelete = [];
		var nodesToDelete = [];
		var add_new_to_group = settingsTab.down('#add_new_to_group').getValue();
		editClassesGrid.getChecked().forEach(function(el) {

			if(!el.isLeaf()) {
				var classId = el.get('classId');
				idsToDelete.push([classId]);
				nodesToDelete.push(el);
				if(add_new_to_group == classId)
					add_new_to_group = 'notadd';
			}
			else {
				if(!el.parentNode.get('checked')) {
					idsToDelete.push([el.get('classId'), el.get('computerId')]);
					nodesToDelete.push(el);
				};
			};
		});
		if(idsToDelete.length) {
			adminAPI({
				data: {
					'do': 'deleteComputers',
					ids: idsToDelete
				},
				ok: function(reqdata, data) {
					nodesToDelete.forEach(function(el) {
						el.remove();
					});
					updateClassesNamesComboBox();
					settingsTab.down('#add_new_to_group').select(add_new_to_group);
				},
				loadMsg: _('Deleting groups and/or computers')
			});
		};
	});
	
	toolbar.down('#createImage').on('click', function() {
		if(isCloning) {
			Ext.Msg.alert(_('Error'), _('Cloning already run'));
		}
		else {
			var checked = editClassesGrid.getChecked();
			var leafCount = 0;
			checked.forEach(function (el) {
				if(el.isLeaf()) leafCount++;
			});

			if(checked.length != 1 || leafCount != 1) {
				Ext.Msg.alert(_('Error'), _('You must select only one computer'));
			}
			else {
				toCloning = [{
					name: checked[0].parentNode.get('name'),
					mac: '',
					expanded: true,
					children: [Ext.clone(checked[0].data)],
				}];
				delete toCloning[0].children[0].checked;
				toCloning[0].children[0].status = 'none';
				
				AddImageWindow.setTitle(_('Create image'));
				AddImageWindow.addImageMode = 'create';
				AddImageWindow.computerId = checked[0].get('computerId');
				AddImageWindow.show();
			};
		};

	});
	
	toolbar.down('#startCloning').on('click', function() {
		if(isCloning) {
			Ext.Msg.alert(_('Error'), _('Cloning already run'));
		}
		else {
			toCloning = [];
			idsToCloning = [];
			var classIdToIdx = {};
			editClassesGrid.getChecked().forEach(function(el) {
				if(el.isLeaf()) {
					idsToCloning.push(el.get('computerId'));
					var classId = el.get('classId');
					if(classIdToIdx[classId] === undefined) {
						toCloning.push({
							name: el.parentNode.get('name'),
							mac: '',
							expanded: true,
							children: [],
						});
						classIdToIdx[classId] = toCloning.length - 1;
					};
					var dataCopy = Ext.clone(el.data);
					delete dataCopy['checked'];
					dataCopy['status'] = 'none';
					toCloning[classIdToIdx[classId]].children.push(dataCopy);
				};
			});
			if(idsToCloning.length) {
				isImageSelecting = true;
				navTabs.setActiveTab(imagesTab);
				imagesTab.down('#askbar').show();
				imagesTab.down('#toolbar').hide();
				imagesGrid.doComponentLayout(); //ext js bug
				IADWindow.doLayout();
				
				navTabs.items.each(function(tab) {
					if(tab != imagesTab) {
						tab.setDisabled(true);
					};
				});
			}
			else {
				Ext.Msg.alert(_('Error'), _('You must select at least one computer'));
			};
		};
	});
	
	toolbar.down('#wolButton').on('click', function() {
		toWake = [];
		idsToWake = [];
		var classIdToIdx = {};
		editClassesGrid.getChecked().forEach(function(el) {
			if(el.isLeaf()) {
				idsToWake.push(el.get('computerId'));
				var classId = el.get('classId');
				if(classIdToIdx[classId] === undefined) {
					toWake.push({
						name: el.parentNode.get('name'),
						expanded: true,
						children: [],
					});
					classIdToIdx[classId] = toWake.length - 1;
				};
				var dataCopy = Ext.clone(el.data);
				delete dataCopy['checked'];
				dataCopy['status'] = 'none';
				toWake[classIdToIdx[classId]].children.push(dataCopy);
			};
		});
		if(!(idsToWake.length))
			Ext.Msg.alert(_('Error'), _('You must select at least one computer'));
		else
		{
			adminAPI({
				data: {
					'do': 'wakeComputers',
					ids: idsToWake,
				},
				ok: function(reqdata, data) {
					},
				fail: function(reqdata, reason) {
					Ext.Msg.alert(_('Error'), _('WOL canceled, reason:') + '<br/>' + reason);
				}
			});
		}
	});

	toolbar.down('#startMaintenance').on('click', function() {
		if(isCloning) {
			Ext.Msg.alert(_('Error'), _('Cloning already run'));
		}
		else {
			toCloning = [];
			idsToCloning = [];
			var classIdToIdx = {};
			editClassesGrid.getChecked().forEach(function(el) {
				if(el.isLeaf()) {
					idsToCloning.push(el.get('computerId'));
					var classId = el.get('classId');
					if(classIdToIdx[classId] === undefined) {
						toCloning.push({
							name: el.parentNode.get('name'),
							mac: '',
							expanded: true,
							children: [],
						});
						classIdToIdx[classId] = toCloning.length - 1;
					};
					var dataCopy = Ext.clone(el.data);
					delete dataCopy['checked'];
					dataCopy['status'] = 'none';
					toCloning[classIdToIdx[classId]].children.push(dataCopy);
				};
			});
			if(idsToCloning.length) {
				adminAPI({
					data: {'do': 'startMaintenance', ids: idsToCloning},
					ok: function(reqdata, data) {
						startCloning(toCloning);
					},
					loadMsg: _('Starting maintenance')
				});
			}
			else {
				Ext.Msg.alert(_('Error'), _('You must select at least one computer'));
			};
		};
	});
};

function imagesTabHandler() {
	var toolbar = imagesTab.down('#toolbar');
	var askbar = imagesTab.down('#askbar');
	

	imagesTab.down('#addImageManual').on('click', function() {
		AddImageWindow.setTitle(_('Add image manual'));
		AddImageWindow.addImageMode = 'manual';
		AddImageWindow.show();
	});
	
	AddImageWindow.down('#cancel').on('click', function() {
		AddImageWindow.hide();
	});
	
	AddImageWindow.down('#add').on('click', function() {
		var name = AddImageWindow.down('#name').getValue();
		var path = AddImageWindow.down('#path').getValue();
		if(!name.length) {
			Ext.Msg.alert(_('Error'), _('You must enter image name'));
		}
		else if(!path.length) {
			Ext.Msg.alert(_('Error'), _('You must enter image path'));
		}
		else if(AddImageWindow.addImageMode == 'manual') {
			adminAPI({
				data: {'do': 'addImageManual', name: name, path: path},
				ok: function(reqdata, data) {
					imagesGrid.getStore().add({imageId: data.imageId,
											   name: name,
											   path: path,
											   addDate: data.addDate});
					AddImageWindow.hide();
				},
				loadMsg: _('Adding image manual')
			});
		}
		else if(AddImageWindow.addImageMode == 'create') {
			adminAPI({
				data: {'do': 'createImage', name: name, path: path, id: AddImageWindow.computerId},
				ok: function(reqdata, data) {
					AddImageWindow.hide();
					startCloning(toCloning);
				},
				loadMsg: _('Starting creating image')
			});
		};
	});
	
	
	imagesGrid.down('#deleteRow').items[0].handler = function(grid, rowIndex, colIndex) {
        var record = grid.getStore().getAt(rowIndex);
		adminAPI({
			data: {'do': 'deleteImage', imageId: record.get('imageId')},
			ok: function(reqdata, data) {
				grid.getStore().remove(record);
			},
			loadMsg: _('Deleting image')
		});
	};
	
	askbar.down('#cancelCloning').on('click', function() {
		isImageSelecting = false;
		askbar.hide();
		toolbar.show();
		imagesGrid.doComponentLayout(); // ext js bug
		IADWindow.doLayout();


		navTabs.items.each(function(tab) {
			if(tab != imagesTab) {
				tab.setDisabled(false);
			};
		});
	});
	
	askbar.down('#startCloning').on('click', function() {
		if(isCloning) {
			Ext.Msg.alert(_('Error'), _('Cloning already run'));
		}
		else {

			var images = imagesGrid.getSelectionModel().getSelection();
			if(images.length == 1) {
				
				askbar.down('#cancelCloning').fireEvent('click');
				
				adminAPI({
					data: {'do': 'startCloning', ids: idsToCloning, imageId: images[0].get('imageId')},
					ok: function(reqdata, data) {
						startCloning(toCloning);
					},
					loadMsg: _('Starting cloning')
				});
			}
			else {
				Ext.Msg.alert(_('Error'), _('You must select image'));
			};
		};
	});
};

function cloningTabHandler() {
	var toolbar = cloningGrid.getDockedComponent('toolbar');
	
	toolbar.down('#stopCloning').on('click', function() {
		if(isCloning) {
			stopCloning();
			adminAPI({
				data: {
					'do': 'stopCloning',
				},
				ok: function(reqdata, data) {
					updateCloningStateGrid(data.stateLog, data.mode);
				},
				loadMsg: _('Aborting cloning')
			});
		}
		else {
			Ext.Msg.alert(_('Error'), _('Cloning not runned'));
		};
	});
	
	toolbar.down('#getCloningLog').on('click', function() {
		adminAPI({
			data: { 'do': 'getCloningLog' },
			ok: function(reqdata, data) {
				Ext.Msg.show({title: 'cloningLog', msg: data.log, autoScroll: true});
			}
		});
	});
	
};

function settingsTabHandler() {
	
	var langs = [];
	for(var key in lang.langs) {
		langs.push({lang: key, name: lang.langs[key]});
	};

	updateGrid(settingsTab.down('#language'), langs);
	settingsTab.down('#language').select(lang.current);
	
	settingsTab.down('#save').on('click', function() {
		var config = {};
		settingsTab.down('#daemon').items.each(function(el) {
			if(el.$className.indexOf('Ext.form.field.') != -1) {
				if(el.itemId == 'add_new_to_group') {
					var val = el.getValue();
					config[el.itemId] = val == 'notadd' ? null : val;
				}
				else {
					config[el.itemId] = el.getValue();
				};
			};
		});
		adminAPI({
			data: {'do': 'updateConfig', config: config},
			loadMsg: _('Saving settings')
		});
	});
	settingsTab.down('#reset').on('click', function() {
		adminAPI({
			data: {'do': 'resetConfig'},
			ok: function(reqdata, data) {
				updateConfig(data.config);
				console.log(data.config);
			},
			loadMsg: _('Restoring default settings')
		});
	});

	settingsTab.down('#saveInterface').on('click', function() {
		Ext.state.Manager.set('lang', settingsTab.down('#language').getValue());
		Ext.Msg.show({
			title: _('Reload interface'),
			msg: _('You must reload interface to take changes'),
			closable: false
		});
	});
	
	settingsTab.down('#resetInterface').on('click', function() {
		for(var key in Ext.state.Manager.provider.state) {
			Ext.state.Manager.clear(key);
		};
		
		Ext.Msg.show({
			title: _('Reload interface'),
			msg: _('You must reload interface to take changes'),
			closable: false
		});
	});
};

function updateClassesNamesComboBox(select) {
	var cb = settingsTab.down('#add_new_to_group');
	var oldValue = cb.getValue();
	var data = [{classId: 'notadd', name: _('Not add')}];
	editClassesGrid.getStore().getRootNode().cascadeBy(function(el) {
		if(!el.isLeaf() && !el.isRoot()) {
			data.push({classId: el.get('classId'),
					   name: el.get('name')});
		};
	});
	updateGrid(cb, data);
	if(select) {
		cb.select(select);
	}
	else if(oldValue) {
		cb.select(oldValue);
	};
	if(cb.picker)
		cb.picker.setLoading(false); //bug
};


function init() {
	adminAPI({
		data: {'do': 'init'},
		ok: function(reqdata, data) {
			console.log(data);
			
			ticket = data.ticket;
			
			
			updateGrid(editClassesGrid, data.classes);
			updateClassesNamesComboBox();

			updateConfig(data.config);
			
			updateGrid(imagesGrid, data.images);
			
			updateCloningStateGrid(data.cloningStateLog, data.cloningMode);
			
			Ext.TaskManager.start(taskCheckNotices);

			if(data.isCloning) {
				startCloning(data.cloningClasses);
			};
		},
		loadMsg: _('Loading data')
	});
};

function startCloning(toCloning) {
	isCloning = true;
	updateGrid(cloningGrid, toCloning);
	navTabs.setActiveTab(cloningTab);
	Ext.TaskManager.start(taskCheckCloningState);
};

function stopCloning() {
	updateGrid(cloningGrid, []);
	isCloning = false;
	Ext.TaskManager.stop(taskCheckCloningState);
};

function updateCloningStateGrid(stateLog, mode) {
	var last, icon, state;
	for(var id = 0; id < stateLog.length; id++) {
		last = id == stateLog.length - 1;
		icon = 'badge-circle-check-16-ns.png';
		switch(stateLog[id].state) {
			case 'notRunned':
				icon = 'circle-grey-16-ns.png';
				break;
			case 'waitAllReady':
			case 'allready':
				if(last) icon = 'badge-circle-check-16-ns.png';
				break;
			case 'runned':
			case 'waitConnections':
			case 'scanning':
			case 'saving':
			case 'transfering':
				if(last) icon = 'loading.gif';
				break;
			case 'complete':
			case 'scanned':
				break;
			case 'canceled':
				icon = 'badge-circle-minus-16-ns.png';
				break;
			case 'error':
				icon = 'warning-16-ns.png';
				break;
		}
		stateLog[id].icon = '<img src="icons/' + icon + '"/>';
		state = mode == 'cloning' || 'maintenance'
			? _('cloningState.' + stateLog[id].state)
			: _('cloningState.imaging.' + stateLog[id].state, 'cloningState.' + stateLog[id].state);
		if(stateLog[id].params.length) {
			//JS not have sprintf?
			var chunks = state.split('%s');
			state = '';
			for(var i = 0; i < stateLog[id].params.length; i++) {
				if(chunks.length) {
					state += chunks.shift() + stateLog[id].params[i];
				};
			};
			state += chunks.join('%s');
		};
		stateLog[id].state = state;
		if(id == stateLog.length - 1) {
			IADWindow.getDockedComponent('statusbar').down('#state').setText(state);
		};
	};
	updateGrid(cloningStateGrid, stateLog);
	//try to work around with grid scroller bug
	var cloningStateGridScroller = cloningStateGrid.getVerticalScroller();
	if(cloningStateGridScroller) {

 		var el = cloningStateGridScroller.scrollEl,
            elDom = el && el.dom;
        if(elDom) {
            cloningStateGridScroller.setScrollTop(elDom.scrollHeight - elDom.clientHeight);
    	};
	};
	cloningStateGrid.invalidateScroller();
};


function updateGrid(grid, data) {
	grid.getStore().setProxy({
        type: 'memory',
        data: data,
        reader: {type: 'json'}
	});
	grid.getStore().load();
};

function updateConfig(config) {
	for(name in config) {
		switch(name) {
			case 'add_new_to_group':
				if(config[name] == null) {
					settingsTab.down('#' + name).select('notadd');
				}
				else {
					settingsTab.down('#' + name).select(config[name]);
				};
				break;
			default:
				settingsTab.down('#' + name).setValue(config[name]);
		};
	};
};

//request.data
//request.ok
//request.fail
//request.loadMsg
function adminAPI(request) {
	if(request.loadMsg)
		IADWindow.setLoading(request.loadMsg);
	
	request.data.ticket = ticket;
	Ext.Ajax.request({
		jsonData: request.data,
		success: function(response) {
			var data = Ext.decode(response.responseText);
			
			if(request.loadMsg)
				IADWindow.setLoading(false);
			
			if(data.success) {
				if(request.ok) 
					request.ok(request.data, data);
			} else {
				if(request.fail) {
					request.fail(request.data, _(data.fail));
				}
				else {
					Ext.Msg.alert(_('Error'),
						_('An error occurred, recommend reload interface') + '<br/><br/>' + _('Reason: ') + _(data.fail));
				};
			};
		},
		failure: function() {
			if(request.loadMsg)
				IADWindow.setLoading(false);

			if(request.fail) {
				request.fail(request.data, _('Network error'));
			}
			else {
				Ext.Msg.alert(_('Error'),
					_('An error occurred, recommend reload interface') + '<br/><br/>' + _('Reason: ') + _('Network error'));
			};
		}
	});
};
