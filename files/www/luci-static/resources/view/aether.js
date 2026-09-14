/*
 * luci-app-aether — LuCI Web Interface for Aether VPN
 *
 * Uses built-in ubus objects (service / rc / uci / file) instead of a
 * custom shell rpcd handler. On OpenWrt 25.12.5 shell handlers under
 * /usr/libexec/rpcd may register as ubus objects with zero methods.
 */
'use strict';
'require form';
'require rpc';
'require uci';
'require ui';
'require view';

var AETHER_CLIENT_VERSION = 'v0.8.0';

/* Obfuscation profiles from Aether core guide — depend on protocol. */
var AETHER_PROFILES = {
	masque: {
		firewall: 'Firewall (recommended)',
		gfw: 'GFW',
		off: 'Off'
	},
	wg: {
		balanced: 'Balanced (recommended)',
		aggressive: 'Aggressive',
		light: 'Light',
		off: 'Off'
	},
	gool: {
		balanced: 'Balanced (recommended)',
		aggressive: 'Aggressive',
		light: 'Light',
		off: 'Off'
	},
	mim: {
		firewall: 'Firewall (recommended)',
		gfw: 'GFW',
		off: 'Off'
	}
};

function aetherProfileLabels(protocol) {
	return AETHER_PROFILES[protocol] || AETHER_PROFILES.masque;
}

function aetherProfileDefault(protocol) {
	return (protocol === 'wg' || protocol === 'gool') ? 'balanced' : 'firewall';
}

/* v1.6 introduced HTTP CONNECT, MASQUE startup deadlines, and log controls.
 * Later releases inherit this capability profile until one needs its own. */
function aetherCoreSupportsV16(version) {
	var m = String(version || '').match(/(?:^|\s)v?(\d+)\.(\d+)\.(\d+)/);
	if (!m)
		return false;
	return Number(m[1]) > 1 || (Number(m[1]) === 1 && Number(m[2]) >= 6);
}

/* v1.7 added upstream proxy chaining (--upstream). */
function aetherCoreSupportsV17(version) {
	var m = String(version || '').match(/(?:^|\s)v?(\d+)\.(\d+)\.(\d+)/);
	if (!m)
		return false;
	return Number(m[1]) > 1 || (Number(m[1]) === 1 && Number(m[2]) >= 7);
}

/* v1.8 added the resource performance profile. Routing rules, in-tunnel
 * DNS and TLS groups are core-side defaults and deliberately not exposed. */
function aetherCoreSupportsV18(version) {
	var m = String(version || '').match(/(?:^|\s)v?(\d+)\.(\d+)\.(\d+)/);
	if (!m)
		return false;
	return Number(m[1]) > 1 || (Number(m[1]) === 1 && Number(m[2]) >= 8);
}

/* v1.9 added independent dual-hop gool endpoint control. */
function aetherCoreSupportsV19(version) {
	var m = String(version || '').match(/(?:^|\s)v?(\d+)\.(\d+)\.(\d+)/);
	if (!m)
		return false;
	return Number(m[1]) > 1 || (Number(m[1]) === 1 && Number(m[2]) >= 9);
}

function aetherCoreSupportsV20(version) {
	var m = String(version || '').match(/(?:^|\s)v?(\d+)\.(\d+)\.(\d+)/);
	return !!m && Number(m[1]) >= 2;
}

function aetherSyncProfileChoices(profileOpt, section_id, protocol) {
	var labels = aetherProfileLabels(protocol);
	var keys = Object.keys(labels);
	var def = aetherProfileDefault(protocol);
	var uiEl, cur;

	profileOpt.keylist = keys.slice();
	profileOpt.vallist = keys.map(function(k) { return labels[k]; });

	try {
		uiEl = profileOpt.getUIElement(section_id);
	}
	catch (e) {
		uiEl = null;
	}

	if (!uiEl)
		return;

	cur = uiEl.getValue();
	if (cur == null || cur === '' || !labels.hasOwnProperty(cur))
		cur = def;

	if (typeof uiEl.clearChoices === 'function' && typeof uiEl.addChoices === 'function') {
		uiEl.clearChoices(true);
		uiEl.addChoices(keys, labels);
		uiEl.setValue(cur);
		return;
	}

	/* Native <select> fallback */
	var node = uiEl.node || uiEl;
	var select = (node && node.tagName === 'SELECT') ? node
		: (node && node.querySelector ? node.querySelector('select') : null);
	if (select) {
		while (select.firstChild)
			select.removeChild(select.firstChild);
		keys.forEach(function(k) {
			select.appendChild(E('option', { value: k }, labels[k]));
		});
		select.value = cur;
	}
}

function aetherSetOptionDisabled(opt, section_id, disabled) {
	var uiEl = null, node = null, controls = [];

	try {
		uiEl = opt.getUIElement(section_id);
	}
	catch (e) {
		uiEl = null;
	}

	node = uiEl ? (uiEl.node || uiEl) : document.getElementById(opt.cbid(section_id));
	if (!node)
		return;

	if (node.matches && node.matches('input, select, textarea, button, .cbi-dropdown'))
		controls.push(node);

	if (node.querySelectorAll) {
		node.querySelectorAll('input, select, textarea, button, .cbi-dropdown').forEach(function(ctrl) {
			controls.push(ctrl);
		});
	}

	controls.forEach(function(ctrl) {
		if (disabled)
			ctrl.setAttribute('disabled', 'disabled');
		else
			ctrl.removeAttribute('disabled');

		if ('disabled' in ctrl)
			ctrl.disabled = disabled;
	});
}

function aetherSyncMasqueOptions(options, section_id, protocol) {
	var disabled = (protocol !== 'masque' && protocol !== 'mim');
	options.forEach(function(opt) {
		aetherSetOptionDisabled(opt, section_id, disabled);
	});
}

var callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: [ 'name' ],
	expect: {}
});

var callRCInit = rpc.declare({
	object: 'rc',
	method: 'init',
	params: [ 'name', 'action' ],
	expect: {}
});

var callUCIGet = rpc.declare({
	object: 'uci',
	method: 'get',
	params: [ 'config', 'section', 'option' ],
	expect: {}
});

var callFileExec = rpc.declare({
	object: 'file',
	method: 'exec',
	params: [ 'command', 'params' ],
	expect: {}
});

function extractFromLogs(logs, pattern) {
	if (!logs) return '';
	var m = logs.match(pattern);
	return m ? m[1] : '';
}

function getServiceStatus() {
	return Promise.all([
		callServiceList('aether').then(function(res) {
			try {
				var instances = res.aether.instances || {};
				var inst = instances.core || instances.instance1;
				if (!inst) {
					var names = Object.keys(instances);
					inst = names.length ? instances[names[0]] : null;
				}
				if (!inst)
					return { running: false };
				return { running: !!inst.running, pid: inst.pid, command: inst.command };
			} catch (e) {
				return { running: false };
			}
		}).catch(function() {
			return { running: false };
		}),
		callUCIGet('aether', 'main', 'enabled').then(function(r) {
			return (r && r.value != null) ? String(r.value).replace(/'/g, '') : '0';
		}).catch(function() { return '0'; }),
		callUCIGet('aether', 'main', 'protocol').then(function(r) {
			return (r && r.value) ? String(r.value).replace(/'/g, '') : 'masque';
		}).catch(function() { return 'masque'; }),
		callUCIGet('aether', 'main', 'tor_mode').then(function(r) {
			return (r && r.value) ? String(r.value).replace(/'/g, '') : 'off';
		}).catch(function() { return 'off'; }),
		callFileExec('logread', [ '-e', 'aether', '-l', '30' ]).then(function(r) {
			return (r && r.stdout) ? r.stdout : '';
		}).catch(function() { return ''; }),
		callFileExec('/usr/bin/aether', [ '--version' ]).then(function(r) {
			return (r && r.stdout) ? String(r.stdout).trim() : '';
		}).catch(function() { return ''; }),
		callUCIGet('aether', 'main', 'tor_bind').then(function(r) {
			return (r && r.value) ? String(r.value).replace(/'/g, '') : '127.0.0.1:1820';
		}).catch(function() { return '127.0.0.1:1820'; })
	]).then(function(r) {
		var svc = r[0], logs = r[4], version = r[5];
		return {
			running: svc.running,
			pid: svc.pid,
			command: svc.command,
			enabled: r[1],
			protocol: r[2],
			version: version.replace(/^aether\s+/i, ''),
			torMode: r[3],
			torBind: r[6],
			endpoint: extractFromLogs(logs, /using cloudflare edge ([0-9.:]+)/),
			transport: extractFromLogs(logs, /MASQUE transport: ([^\s]+)/),
			socks_addr: extractFromLogs(logs, /socks5 (?:server )?listening on ([^\s]+)/),
			obfuscation: extractFromLogs(logs, /obfuscation profile: (\w+)/),
			scan_mode: extractFromLogs(logs, /scan mode: (\w+)/),
			identity: extractFromLogs(logs, /device=([^\s]+)/),
			logs: logs
		};
	});
}

function doServiceAction(action) {
	return function() {
		var btn = this;
		btn.disabled = true;
		btn.value = '...';
		callFileExec('/usr/bin/aether-ctl', [ action ])
		.then(function(result) {
			if (!result || result.code !== 0)
				throw new Error((result && result.stderr) || 'Service action failed');
			setTimeout(function() { location.reload(); }, 3000);
		}).catch(function() {
			btn.disabled = false;
			btn.value = action.charAt(0).toUpperCase() + action.slice(1);
		});
	};
}

function doTestConnection(host) {
	return function() {
		var btn = this;
		var resultEl = document.getElementById('test-result-' + host);
		btn.disabled = true;
		btn.value = 'Testing...';
		if (resultEl) {
			resultEl.textContent = 'Connecting...';
			resultEl.style.color = '#888';
		}

		callFileExec('/usr/bin/aether-ctl', [ 'test', host ]
		).then(function(r) {
			var output = (r && r.stdout) ? r.stdout : '';
			var errput = (r && r.stderr) ? r.stderr : '';
			var combined = output + ' ' + errput;
			// New format: "OK <http_code> <ms>ms" or "FAILED <ms>ms"
			var okMatch = combined.match(/OK\s+(\d+)\s+(\d+)ms/i);
			var failMatch = combined.match(/FAILED\s+(\d+)ms/i);
			if (okMatch) {
				var info = 'HTTP ' + okMatch[1] + ' \u2014 ' + okMatch[2] + 'ms';
				if (resultEl) {
					resultEl.textContent = info;
					resultEl.style.color = '#2ecc71';
				}
			} else if (failMatch) {
				if (resultEl) {
					resultEl.textContent = 'Failed \u2014 ' + failMatch[1] + 'ms';
					resultEl.style.color = '#e74c3c';
				}
			} else {
				if (resultEl) {
					resultEl.textContent = 'Failed';
					resultEl.style.color = '#e74c3c';
				}
			}
		}).catch(function() {
			if (resultEl) {
				resultEl.textContent = 'Error';
				resultEl.style.color = '#e74c3c';
			}
		}).finally(function() {
			btn.disabled = false;
			btn.value = host;
		});
	};
}
function doCheckIp() {
	return function() {
		var btn = this;
		var resultEl = document.getElementById('test-result-ip');
		btn.disabled = true;
		btn.value = 'Checking...';
		if (resultEl) {
			resultEl.textContent = 'Connecting...';
			resultEl.style.color = '#888';
		}

		callFileExec('/usr/bin/aether-ctl', [ 'check-ip' ]
		).then(function(r) {
			var output = (r && r.stdout) ? r.stdout : '';
			var errput = (r && r.stderr) ? r.stderr : '';
			var combined = output + ' ' + errput;
			// Matches "IP: <ip> (<country>) <ms>ms" or "IP: <ip> <ms>ms"
			var ipCountryMatch = combined.match(/IP:\s*([^\s(]+)\s*\(([^)]+)\)\s+(\d+)ms/i);
			var ipMatch = combined.match(/IP:\s*([^\s(]+)\s+(\d+)ms/i);
			var failMatch = combined.match(/FAILED\s+(\d+)ms/i);

			if (ipCountryMatch) {
				if (resultEl) {
					resultEl.textContent = ipCountryMatch[1] + ' (' + ipCountryMatch[2] + ') \u2014 ' + ipCountryMatch[3] + 'ms';
					resultEl.style.color = '#2ecc71';
				}
			} else if (ipMatch) {
				if (resultEl) {
					resultEl.textContent = ipMatch[1] + ' \u2014 ' + ipMatch[2] + 'ms';
					resultEl.style.color = '#2ecc71';
				}
			} else if (failMatch) {
				if (resultEl) {
					resultEl.textContent = 'Failed \u2014 ' + failMatch[1] + 'ms';
					resultEl.style.color = '#e74c3c';
				}
			} else {
				if (resultEl) {
					resultEl.textContent = 'Failed';
					resultEl.style.color = '#e74c3c';
				}
			}
		}).catch(function() {
			if (resultEl) {
				resultEl.textContent = 'Error';
				resultEl.style.color = '#e74c3c';
			}
		}).finally(function() {
			btn.disabled = false;
			btn.value = 'Check Public IP';
		});
	};
}

function doCheckTor() {
	return function() {
		var btn = this;
		var resultEl = document.getElementById('test-result-tor');
		btn.disabled = true;
		btn.value = 'Checking...';
		if (resultEl) {
			resultEl.textContent = 'Connecting...';
			resultEl.style.color = '#888';
		}

		callFileExec('/usr/bin/aether-ctl', [ 'check-tor' ]
		).then(function(r) {
			var output = (r && r.stdout) ? r.stdout : '';
			var errput = (r && r.stderr) ? r.stderr : '';
			var combined = output + ' ' + errput;
			var torMatch = combined.match(/Tor:\s*(true|false)\s+IP:\s*(\S+)\s+(\d+)ms/i);
			var failMatch = combined.match(/FAILED\s+(\d+)ms/i);

			if (torMatch) {
				if (resultEl) {
					var isTor = /^true$/i.test(torMatch[1]);
					resultEl.textContent = (isTor ? 'Tor \u2713 ' : 'NOT Tor \u2717 ') + torMatch[2] + ' \u2014 ' + torMatch[3] + 'ms';
					resultEl.style.color = isTor ? '#2ecc71' : '#e74c3c';
				}
			} else if (failMatch) {
				if (resultEl) {
					resultEl.textContent = 'Failed \u2014 ' + failMatch[1] + 'ms';
					resultEl.style.color = '#e74c3c';
				}
			} else {
				if (resultEl) {
					resultEl.textContent = 'Failed';
					resultEl.style.color = '#e74c3c';
				}
			}
		}).catch(function() {
			if (resultEl) {
				resultEl.textContent = 'Error';
				resultEl.style.color = '#e74c3c';
			}
		}).finally(function() {
			btn.disabled = false;
			btn.value = 'Check Tor IP';
		});
	};
}

/* Parse "key=value" lines emitted by `aether-ctl passwall status`. */
function parseKeyValues(text) {
	var out = {};
	String(text || '').split('\n').forEach(function(line) {
		var m = line.match(/^\s*([a-z0-9_]+)=(.*)$/i);
		if (m)
			out[m[1]] = m[2].trim();
	});
	return out;
}

function pwRunCtl(args, btn, busyLabel) {
	var original = btn.value;
	btn.disabled = true;
	btn.value = busyLabel || 'Working...';
	return callFileExec('/usr/bin/aether-ctl', args).then(function(r) {
		if (!r || r.code !== 0) {
			var err = (r && r.stderr) ? String(r.stderr).trim().split('\n')[0] : 'Failed';
			btn.value = err;
			return false;
		}
		btn.value = 'Done';
		return true;
	}).catch(function() {
		btn.value = 'Error';
		return false;
	}).finally(function() {
		setTimeout(function() {
			btn.disabled = false;
			btn.value = original;
		}, 2000);
	});
}


return view.extend({
	load: function() {
		return {};
	},

	render: function() {
		var el = E('div', {});

		return getServiceStatus().then(function(st) {
			var supportsV16 = aetherCoreSupportsV16(st.version);
			var supportsV17 = aetherCoreSupportsV17(st.version);
			var supportsV18 = aetherCoreSupportsV18(st.version);
			var supportsV19 = aetherCoreSupportsV19(st.version);
			var supportsV20 = aetherCoreSupportsV20(st.version);
			var tbl = E('table', { 'class': 'table' });

			function row(label, val) {
				if (val == null || val === '') return;
				tbl.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td', 'style': 'width:160px;font-weight:600' }, label),
					E('td', { 'class': 'td' }, val)
				]));
			}

			var color = st.running ? '#2ecc71' : '#e74c3c';
			row('State', E('span', {
				'style': 'font-weight:bold;color:' + color
			}, st.running ? 'Running' : 'Stopped'));
			row('Client Version', AETHER_CLIENT_VERSION);
			if (st.version) row('Core Version', st.version);
			row('Enable on Boot', st.enabled === '1' ? 'Yes' : 'No');

			if (st.running) {
				if (st.pid) row('PID', String(st.pid));
				if (st.endpoint) row('Endpoint', E('code', {}, st.endpoint));
				if (st.transport) row('Transport', 'MASQUE / ' + st.transport);
				if (st.obfuscation) row('Obfuscation', st.obfuscation);
				if (st.scan_mode) row('Scan Mode', st.scan_mode);
				if (st.socks_addr) row('SOCKS5 Proxy', E('code', {}, st.socks_addr));
				if (st.identity) {
					row('Device ID', E('code', {
						'style': 'font-size:11px;word-break:break-all'
					}, st.identity));
				}
			} else {
				row('Info', 'Service is not running. Click Start to begin.');
			}

			if (supportsV20) {
				if (!st.torMode || st.torMode === 'off') {
					row('Tor', 'Disabled');
				} else if (st.torMode === 'only') {
					row('Tor', 'Enabled (Tor only, no WARP tunnel)');
				} else {
					var torAddr = String(st.torBind || '127.0.0.1:1820').replace(/0\.0\.0\.0/, '127.0.0.1');
					row('Tor', E('span', {}, ['Enabled at ', E('code', {}, torAddr)]));
				}
			} else {
				row('Tor', 'Needs core v2.0+');
			}

			var btns = E('div', {
				'style': 'margin-top:10px;display:flex;gap:8px;align-items:center;flex-wrap:wrap'
			});

			if (st.running) {
				btns.appendChild(E('input', {
					'type': 'button',
					'class': 'cbi-button cbi-button-remove',
					'value': 'Stop',
					'click': doServiceAction('stop')
				}));
				btns.appendChild(E('input', {
					'type': 'button',
					'class': 'cbi-button cbi-button-reset',
					'value': 'Restart',
					'click': doServiceAction('restart')
				}));
			} else {
				btns.appendChild(E('input', {
					'type': 'button',
					'class': 'cbi-button cbi-button-apply',
					'value': 'Start',
					'click': doServiceAction('start')
				}));
			}

			btns.appendChild(E('span', {
				'style': 'font-size:12px;color:#888;margin-left:8px'
			}, 'Start/Stop controls the running tunnel. "Enable on Boot" below controls auto-start on reboot.'));

			el.appendChild(E('div', { 'class': 'cbi-section' }, [
				E('h3', { 'style': 'margin-top:0' }, 'Status'),
				tbl,
				btns
			]));

			// --- Connection Test Section ---
			var testSection = E('div', { 'class': 'cbi-section' }, [
				E('h3', { 'style': 'margin-top:0' }, 'Connection Test'),
				E('p', { 'style': 'margin:4px 0 10px 0;color:#666;font-size:13px' },
					'Test if the tunnel can reach external services through the SOCKS5 proxy.')
			]);

			var testHosts = ['google.com', 'youtube.com', 'github.com', 'telegram.org'];
			var testRow = E('div', {
				'style': 'display:flex;gap:10px;align-items:center;flex-wrap:wrap'
			});

			testHosts.forEach(function(host) {
				var wrapper = E('div', {
					'style': 'display:flex;align-items:center;gap:6px'
				});

				var btn = E('input', {
					'type': 'button',
					'class': 'cbi-button cbi-button-apply',
					'value': host,
					'click': doTestConnection(host)
				});

				var result = E('span', {
					'id': 'test-result-' + host,
					'style': 'font-size:13px;color:#888;min-width:100px'
				}, '');

				wrapper.appendChild(btn);
				wrapper.appendChild(result);
				testRow.appendChild(wrapper);
			});
			var ipWrapper = E('div', {
				'style': 'display:flex;align-items:center;gap:6px'
			});

			var ipBtn = E('input', {
				'type': 'button',
				'class': 'cbi-button cbi-button-apply',
				'value': 'Check Public IP',
				'click': doCheckIp()
			});

			var ipResult = E('span', {
				'id': 'test-result-ip',
				'style': 'font-size:13px;color:#888;min-width:140px'
			}, '');

			ipWrapper.appendChild(ipBtn);
			ipWrapper.appendChild(ipResult);
			testRow.appendChild(ipWrapper);

			if (supportsV20 && (st.torMode === 'tunnel' || st.torMode === 'reverse' || st.torMode === 'only')) {
				var torWrapper = E('div', {
					'style': 'display:flex;align-items:center;gap:6px'
				});

				var torBtn = E('input', {
					'type': 'button',
					'class': 'cbi-button cbi-button-apply',
					'value': 'Check Tor IP',
					'click': doCheckTor()
				});

				var torResult = E('span', {
					'id': 'test-result-tor',
					'style': 'font-size:13px;color:#888;min-width:140px'
				}, '');

				torWrapper.appendChild(torBtn);
				torWrapper.appendChild(torResult);
				testRow.appendChild(torWrapper);
			}

			testSection.appendChild(testRow);
			el.appendChild(testSection);
			// --- Live Logs Section ---
			var logSection = E('div', { 'class': 'cbi-section' }, [
				E('h3', { 'style': 'margin-top:0' }, 'Live Logs'),
				E('p', { 'style': 'margin:4px 0 10px 0;color:#666;font-size:13px' },
					'Auto-updating Aether log output. Streaming in real-time.')
			]);

			var logContent = E('pre', {
				'id': 'aether-log-content',
				'style': 'background:#1a1a2e;color:#e0e0e0;padding:12px;border-radius:6px;max-height:400px;overflow-y:auto;font-size:12px;line-height:1.5;white-space:pre-wrap;word-break:break-all;margin:0'
			}, st.logs || '(no logs)');

			// Auto-scroll toggle
			var autoScroll = true;
			var autoScrollLabel = E('label', {
				'style': 'font-size:13px;color:#666;display:flex;align-items:center;gap:6px;cursor:pointer'
			});
			var autoScrollCheckbox = E('input', {
				'type': 'checkbox',
				'checked': true,
				'style': 'margin:0',
				'click': function() { autoScroll = autoScrollCheckbox.checked; }
			});
			autoScrollLabel.appendChild(autoScrollCheckbox);
			autoScrollLabel.appendChild(document.createTextNode('Auto-scroll'));

			// Pause/resume button
			var isPaused = false;
			var pauseBtn = E('input', {
				'type': 'button',
				'class': 'cbi-button cbi-button-reset',
				'value': 'Pause',
				'click': function() {
					isPaused = !isPaused;
					pauseBtn.value = isPaused ? 'Resume' : 'Pause';
					pauseBtn.className = isPaused ? 'cbi-button cbi-button-apply' : 'cbi-button cbi-button-reset';
					if (!isPaused) {
						fetchLatestLogs();
					}
				}
			});

			// Clear button
			var clearBtn = E('input', {
				'type': 'button',
				'class': 'cbi-button',
				'value': 'Clear',
				'click': function() {
					logContent.textContent = '';
				}
			});

			var logControls = E('div', {
				'style': 'display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;gap:8px'
			}, [ autoScrollLabel, E('div', { 'style': 'display:flex;gap:6px' }, [ pauseBtn, clearBtn ]) ]);

			logSection.appendChild(logControls);
			logSection.appendChild(logContent);
			el.appendChild(logSection);

			// --- Real live log streaming ---
			var logPollTimer = null;

			function fetchLatestLogs() {
				if (isPaused) return;
				callFileExec('logread', [ '-e', 'aether', '-l', '50' ]).then(function(r) {
					var logs = (r && r.stdout) ? r.stdout : '';
					if (!logs) return;

					var currentText = logContent.textContent || '';
					if (currentText === '(no logs)' || currentText === '') {
						logContent.textContent = logs;
						return;
					}

					/* Find lines that appeared AFTER the last line we already have.
					   Take the last non-empty line of the current buffer and
					   look for it in the new logread output.  Everything after
					   that position is new.  If the last line is NOT found (log
					   rotated or buffer exceeded), replace the entire buffer. */
					var currentLines = currentText.split('\n');
					var lastLine = '';
					for (var i = currentLines.length - 1; i >= 0; i--) {
						if (currentLines[i].trim() !== '') {
							lastLine = currentLines[i];
							break;
						}
					}

					if (!lastLine) {
						logContent.textContent = logs;
						return;
					}

					var newLines = logs.split('\n');
					var matchPos = -1;
					for (var j = 0; j < newLines.length; j++) {
						if (newLines[j] === lastLine) {
							matchPos = j;
						}
					}

					if (matchPos >= 0 && matchPos < newLines.length - 1) {
						/* append everything after the matched line */
						var tail = newLines.slice(matchPos + 1).join('\n');
						if (tail.trim() !== '') {
							if (logContent.textContent.slice(-1) !== '\n') {
								logContent.textContent += '\n';
							}
							logContent.textContent += tail;
							if (tail.slice(-1) !== '\n') {
								logContent.textContent += '\n';
							}
						}
					} else if (matchPos >= 0) {
						/* last line matches and nothing after it — no new logs */
						return;
					} else {
						/* last line not found — log rotated or buffer exceeded,
						   replace entire content with fresh window */
						logContent.textContent = logs;
					}

					/* Trim to last 500 lines */
					var allLines = logContent.textContent.split('\n');
					if (allLines.length > 500) {
						logContent.textContent = allLines.slice(-500).join('\n');
					}

					if (autoScroll) {
						logContent.scrollTop = logContent.scrollHeight;
					}
				}).catch(function() {});
			}

			// Poll every 2 seconds for new logs
			logPollTimer = setInterval(fetchLatestLogs, 2000);

			// Clean up timer when leaving the page
			window.addEventListener('beforeunload', function() {
				if (logPollTimer) clearInterval(logPollTimer);
			});

			el.appendChild(E('hr', {
				'style': 'margin:12px 0;border:none;border-top:1px solid #ddd'
			}));

			var m = new form.Map('aether', '',
				'Configure Aether tunnel settings below. Click "Save & Apply" to persist changes.');
			var s, o;

			s = m.section(form.NamedSection, 'main', 'aether', 'Basic Settings');
			s.anonymous = true;

			o = s.option(form.Flag, 'enabled', 'Enable on Boot',
				'Auto-start Aether when the router boots');
			o.default = '0';
			o.rmempty = false;
			o.write = function(section_id, value) {
				uci.set('aether', section_id, 'enabled', value);
				return callRCInit('aether', value === '1' ? 'enable' : 'disable');
			};

			o = s.option(form.ListValue, 'protocol', 'Protocol');
			o.value('masque', 'MASQUE (recommended)');
			o.value('wg', 'WireGuard');
			o.value('gool', 'WARP-in-WARP');
			if (supportsV20)
				o.value('mim', 'MASQUE-in-MASQUE');
			o.default = 'masque';
			var protocolOpt = o;
			var masqueOptionOpts = [];

			o = s.option(form.Value, 'socks_listen', 'SOCKS5 Listen Address');
			o.default = '0.0.0.0:1819';
			o.datatype = 'ipaddrport';
			o.rmempty = false;

			if (supportsV16) {
				o = s.option(form.Value, 'http_proxy', 'HTTP CONNECT Proxy',
					'Optional HTTP CONNECT listener. Leave empty to disable it.');
				o.datatype = 'or(ipaddrport,string)';
				o.rmempty = true;
			}

			if (supportsV17) {
				o = s.option(form.Value, 'upstream_proxy', 'Upstream Proxy',
					'Dial out through another proxy before reaching Cloudflare ' +
					'(requires core v1.7+). Accepts socks5://[user:pass@]host:port, ' +
					'http://host:port or bare host:port. A SOCKS5 upstream carries all ' +
					'transports; an HTTP CONNECT upstream requires HTTP/2 mode.');
				o.rmempty = true;
				o.password = true;
			}

			if (!supportsV16) {
				el.appendChild(E('div', { 'class': 'alert-message warning' },
					'Aether v1.5 compatibility mode: HTTP CONNECT proxy, MASQUE startup deadline, and core log-level controls require core v1.6.0 or newer.'));
			} else if (!supportsV17) {
				el.appendChild(E('div', { 'class': 'alert-message warning' },
					'Aether v1.6 compatibility mode: upstream proxy chaining requires core v1.7.0 or newer.'));
			}
			if (supportsV20) {
				el.appendChild(E('div', { 'class': 'alert-message notice' },
					'Aether Core v2.0.0 compatibility mode: MASQUE-in-MASQUE, QUIC v2 controls, and Tor are available.'));
			}
			if (!supportsV18) {
				el.appendChild(E('div', { 'class': 'alert-message warning' },
					'Aether v1.7 compatibility mode: the performance profile requires core v1.8.0 or newer.'));
			} else if (!supportsV19) {
				el.appendChild(E('div', { 'class': 'alert-message warning' },
					'Aether v1.8 compatibility mode: dual-hop gool endpoints require core v1.9.0 or newer.'));
			}

			s = m.section(form.NamedSection, 'main', 'aether', 'Network');

			o = s.option(form.ListValue, 'scan_mode', 'Scan Mode',
				'turbo=fastest, balanced=default, thorough=best quality, stealth=quietest, ironclad=real tunnel test');
			o.value('turbo', 'Turbo');
			o.value('balanced', 'Balanced (default)');
			o.value('thorough', 'Thorough');
			o.value('stealth', 'Stealth');
			o.value('ironclad', 'Ironclad (real tunnel test)');
			o.default = 'balanced';

			o = s.option(form.ListValue, 'ip_version', 'IP Version');
			o.value('ipv4', 'IPv4 only');
			o.value('ipv6', 'IPv6 only');
			o.value('both', 'Both');
			o.default = 'ipv4';

			o = s.option(form.Value, 'peer', 'Force Peer',
				'ip:port, or leave empty for auto-scan');
			o.rmempty = true;

			s = m.section(form.NamedSection, 'main', 'aether', 'Obfuscation');

			o = s.option(form.ListValue, 'obfuscation_profile', 'Profile',
				'Choices change with Protocol (MASQUE vs WireGuard/gool)');
			o.rmempty = false;
			o.value('firewall', 'Firewall (recommended)');
			o.value('gfw', 'GFW');
			o.value('off', 'Off');
			o.value('balanced', 'Balanced (recommended)');
			o.value('aggressive', 'Aggressive');
			o.value('light', 'Light');
			o.default = 'firewall';
			var profileOpt = o;
			o.cfgvalue = function(section_id) {
				var proto = uci.get('aether', section_id, 'protocol') || 'masque';
				var v = uci.get('aether', section_id, 'obfuscation_profile');
				var labels = aetherProfileLabels(proto);
				if (!v || !labels.hasOwnProperty(v))
					return aetherProfileDefault(proto);
				return v;
			};
			o.renderWidget = function(section_id, option_index, cfgvalue) {
				var proto = 'masque';
				try {
					proto = protocolOpt.formvalue(section_id) || protocolOpt.cfgvalue(section_id) || 'masque';
				}
				catch (e) {
					proto = uci.get('aether', section_id, 'protocol') || 'masque';
				}
				var labels = aetherProfileLabels(proto);
				var keys = Object.keys(labels);
				this.keylist = keys.slice();
				this.vallist = keys.map(function(k) { return labels[k]; });
				if (cfgvalue == null || !labels.hasOwnProperty(cfgvalue))
					cfgvalue = aetherProfileDefault(proto);
				return new ui.Select(cfgvalue, labels, {
					id: this.cbid(section_id),
					sort: keys,
					widget: this.widget,
					optional: this.optional,
					validate: (typeof this.getValidator === 'function') ? this.getValidator(section_id) : null,
					disabled: (this.readonly != null) ? this.readonly : this.map.readonly
				}).render();
			};

			protocolOpt.onchange = function(ev, section_id, value) {
				var proto = value || 'masque';
				aetherSyncProfileChoices(profileOpt, section_id, proto);
				aetherSyncMasqueOptions(masqueOptionOpts, section_id, proto);
			};

			s = m.section(form.NamedSection, 'main', 'aether', 'Zero Trust',
				'Optional Cloudflare Zero Trust enrollment using a headless service token.');

			o = s.option(form.Value, 'team', 'Team Name',
				'The organization subdomain from <team>.cloudflareaccess.com');
			o.rmempty = true;

			o = s.option(form.Value, 'access_id', 'Access Client ID',
				'Service-token client ID created in the Zero Trust dashboard');
			o.rmempty = true;
			o.depends('team', /.+/);

			o = s.option(form.Value, 'access_secret', 'Access Client Secret',
				'Stored in the root-only UCI configuration and never written to service logs');
			o.password = true;
			o.rmempty = true;
			o.depends('team', /.+/);

			o = s.option(form.Value, 'access_token', 'Existing Access Token',
				'Optional existing Zero Trust token. It replaces service-token credentials when set.');
			o.password = true;
			o.rmempty = true;
			o.depends('team', /.+/);

			o = s.option(form.Flag, 'gateway', 'Use Organization Gateway',
				'Opt in to organization filtering and logging for HTTP/HTTPS traffic');
			o.default = '0';
			o.depends('team', /.+/);

			s = m.section(form.NamedSection, 'main', 'aether', 'MASQUE Options');

			if (supportsV20) {
				o = s.option(form.Flag, 'quic_v2', 'Use QUIC v2 Opener',
					'Enabled by default for HTTP/3. Disable only when the v2 opener is incompatible with your network.');
				o.default = '1';
				masqueOptionOpts.push(o);
			}

			if (supportsV19) {
				o = s.option(form.Value, 'ech', 'Encrypted Client Hello (ECH)',
					'Leave empty for the core default. Use auto or paste a base64 ECH configuration.');
				o.rmempty = true;
				masqueOptionOpts.push(o);
			}

			o = s.option(form.Flag, 'http2_mode', 'HTTP/2 Mode',
				'Enable if UDP/QUIC is blocked');
			o.default = '0';
			masqueOptionOpts.push(o);

			o = s.option(form.Value, 'h2_peer', 'H2 Peer',
				'Manual destination for h2 mode (ip:port), leave empty for auto');
			o.rmempty = true;
			masqueOptionOpts.push(o);

			o = s.option(form.Flag, 'fragment_tls', 'TLS Fragmentation',
				'Fragment ClientHello (HTTP/2 only)');
			o.default = '0';
			masqueOptionOpts.push(o);

			o = s.option(form.Value, 'fragment_size', 'Fragment Size');
			o.default = '16-32';
			masqueOptionOpts.push(o);

			o = s.option(form.Value, 'fragment_delay', 'Fragment Delay (ms)');
			o.default = '2-10';
			masqueOptionOpts.push(o);

			s = m.section(form.NamedSection, 'main', 'aether', 'Advanced');

			if (supportsV16) {
				o = s.option(form.ListValue, 'log_level', 'Log Level');
				o.value('error', 'Error');
				o.value('warn', 'Warning');
				o.value('info', 'Info');
				o.value('debug', 'Debug');
				o.value('trace', 'Trace');
				o.default = 'info';
			}

			o = s.option(form.Value, 'keepalive', 'Keepalive (s)');
			o.default = '5';
			o.datatype = 'min(1)';
			o.depends('protocol', 'wg');
			o.depends('protocol', 'gool');

			o = s.option(form.Value, 'reconnect_secs', 'Reconnect Delay (s)',
				'Delay before auto-reconnect after tunnel drops');
			o.default = '2';
			o.datatype = 'min(1)';
			if (!supportsV16)
				o.depends('protocol', 'masque');

			o = s.option(form.Value, 'validate_secs', 'Validation Timeout (s)',
				'Seconds to wait for data-plane probe before giving up on a gateway');
			o.default = '10';
			o.datatype = 'min(1)';
			if (!supportsV16)
				o.depends('protocol', 'masque');

			if (supportsV16) {
				o = s.option(form.Value, 'startup_secs', 'MASQUE Startup Deadline (s)',
					'Maximum total time for MASQUE connection and first data validation.');
				o.default = '30';
				o.datatype = 'min(1)';
				o.depends('protocol', 'masque');
				o.depends('protocol', 'mim');
			}

			o = s.option(form.Flag, 'quick_reconnect', 'Quick Reconnect',
				'Re-verify the last known-good gateway first, then scan if it is unavailable');
			o.default = '1';

			o = s.option(form.Flag, 'no_data_check', 'Skip Data Validation',
				'Trust gateway after handshake only (faster but less reliable)');
			o.default = '0';

			o = s.option(form.Flag, 'no_profile_retry', 'Disable Profile Retry',
				'Do not retry alternate noise profiles after a WireGuard or gool scan failure.');
			o.default = '0';
			o.depends('protocol', 'wg');
			o.depends('protocol', 'gool');

			o = s.option(form.Value, 'config_path', 'Config Path');
			o.default = '/etc/aether/aether.toml';
			o.readonly = true;

			o = s.option(form.Flag, 'watchdog_enabled', 'Data-plane Watchdog',
				'Recover a stuck tunnel after repeated end-to-end SOCKS5 probe failures (requires curl)');
			o.default = '1';

			o = s.option(form.Value, 'watchdog_interval', 'Watchdog Interval (s)');
			o.default = '60';
			o.datatype = 'min(30)';
			o.depends('watchdog_enabled', '1');

			o = s.option(form.Value, 'watchdog_failures', 'Failures Before Recovery');
			o.default = '3';
			o.datatype = 'range(2,10)';
			o.depends('watchdog_enabled', '1');

			if (supportsV18) {
				o = s.option(form.ListValue, 'perf_profile', 'Performance Profile',
					'Core resource profile.');
				o.value('low', 'Low');
				o.value('medium', 'Medium');
				o.value('high', 'High');
				o.default = 'low';
				o.rmempty = false;
			}

			if (supportsV19) {
				o = s.option(form.Value, 'wiw_outer', 'gool Outer Hop',
					'Outer WARP-in-WARP endpoint (ip:port), the one your network sees. Leave empty to auto-scan.');
				o.datatype = 'ipaddrport(1)';
				o.rmempty = true;
				o.depends('protocol', 'gool');

				o = s.option(form.Value, 'wiw_inner', 'gool Inner Hop',
					'Inner WARP-in-WARP endpoint (ip:port). Leave empty to auto-scan.');
				o.datatype = 'ipaddrport(1)';
				o.rmempty = true;
				o.depends('protocol', 'gool');
			}

			if (supportsV20) {
				o = s.option(form.Value, 'mim_outer', 'MIM Outer Hop',
					'Outer MASQUE-in-MASQUE endpoint (ip:port). Leave empty to auto-scan.');
				o.datatype = 'ipaddrport(1)';
				o.rmempty = true;
				o.depends('protocol', 'mim');

				o = s.option(form.Value, 'mim_inner', 'MIM Inner Hop',
					'Inner MASQUE-in-MASQUE endpoint (ip:port). Leave empty to auto-select.');
				o.datatype = 'ipaddrport(1)';
				o.rmempty = true;
				o.depends('protocol', 'mim');

				o = s.option(form.Value, 'mim_peers', 'MIM Peers',
					'Optional outer[,inner] ip:port endpoint pair. Leave empty to auto-scan.');
				o.rmempty = true;
				o.depends('protocol', 'mim');

				s = m.section(form.NamedSection, 'main', 'aether', 'Tor (Core v2)');
				o = s.option(form.ListValue, 'tor_mode', 'Tor Mode');
				o.value('off', 'Off');
				o.value('tunnel', 'Tor through WARP');
				o.value('reverse', 'WARP through Tor (MASQUE only)');
				o.value('only', 'Tor only (no WARP tunnel)');
				o.default = 'off';

				o = s.option(form.Value, 'tor_bind', 'Tor SOCKS5 Listen Address');
				o.default = '127.0.0.1:1820';
				o.datatype = 'ipaddrport';
				o.depends('tor_mode', 'tunnel');
				o.depends('tor_mode', 'reverse');

				o = s.option(form.Value, 'tor_dir', 'Tor State Directory');
				o.rmempty = true;
				o.depends('tor_mode', /^(tunnel|reverse|only)$/);

				o = s.option(form.ListValue, 'tor_bridges', 'Tor Bridge Policy');
				o.value('auto', 'Automatic fallback');
				o.value('on', 'Use bridges immediately');
				o.value('off', 'Never use bridges');
				o.default = 'auto';
				o.depends('tor_mode', /^(tunnel|reverse|only)$/);
			}
			s = m.section(form.NamedSection, 'main', 'aether', 'Custom Command',
				'Take full control of the core command line. Generated mode shows the running command read-only; switch to Manual to type your own arguments (space-separated, no quotes). Manual commands still launch through aether-run, so Zero Trust secrets stay out of process listings. Applies on restart.');

			o = s.option(form.ListValue, 'command_mode', 'Command Mode');
			o.value('generated', 'Generated (recommended)');
			o.value('manual', 'Manual');
			o.default = 'generated';

			o = s.option(form.DummyValue, '_generated_cmd', 'Generated Command');
			o.cfgvalue = function(section_id) { return (st.command || []).join(' '); };
			o.depends('command_mode', 'generated');

			o = s.option(form.TextValue, 'custom_command', 'Manual Arguments');
			o.rows = 5;
			o.rmempty = true;
			o.depends('command_mode', 'manual');

			return m.render().then(function(formNode) {
				el.appendChild(formNode);
				var proto = 'masque';
				try {
					proto = protocolOpt.formvalue('main') || protocolOpt.cfgvalue('main') || 'masque';
				}
				catch (e) {
					proto = uci.get('aether', 'main', 'protocol') || 'masque';
				}
				aetherSyncProfileChoices(profileOpt, 'main', proto);
				aetherSyncMasqueOptions(masqueOptionOpts, 'main', proto);
				// --- Passwall2 Integration (rendered under Advanced settings) ---
				var pwSection = E('div', { 'class': 'cbi-section' });

				function pwRow(tbl, label, val) {
					tbl.appendChild(E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td', 'style': 'width:160px;font-weight:600' }, label),
						E('td', { 'class': 'td' }, val)
					]));
				}

				function refreshPasswall() {
					while (pwSection.firstChild)
						pwSection.removeChild(pwSection.firstChild);

					pwSection.appendChild(E('h3', { 'style': 'margin-top:0' }, 'Passwall2 Integration'));

					callFileExec('/usr/bin/aether-ctl', [ 'passwall', 'status' ]).then(function(r) {
						var st = parseKeyValues(r && r.stdout);

						if (String(st.passwall2_present) !== '1') {
							pwSection.appendChild(E('p', {
								'style': 'margin:4px 0 10px 0;color:#666;font-size:13px'
							}, 'Passwall2 was not detected on this router. Install luci-app-passwall2 to use this integration.'));
							return;
						}

						if (st.localhost_proxy === '1') {
							pwSection.appendChild(E('div', { 'class': 'alert-message warning' },
								'Passwall2 is proxying router-local traffic (localhost_proxy=1). This competes with Aether for local connections and can route Aether\'s own probes through Passwall2. Disable it unless you deliberately chain the two proxies.'));
						}

						var tbl = E('table', { 'class': 'table' });
						pwRow(tbl, 'Global Enabled', st.passwall2_enabled === '1' ? 'Yes' : 'No');
						pwRow(tbl, 'Localhost Proxy', st.localhost_proxy === '1' ? 'Enabled' : 'Disabled');
						pwRow(tbl, 'Client Proxy', st.client_proxy === '1' ? 'Enabled' : 'Disabled');
						pwRow(tbl, 'Aether SOCKS5', E('code', {}, st.aether_socks_addr || '?'));

						var found = parseInt(st.node_found, 10) || 0;
						var conflicts = parseInt(st.conflict_count, 10) || 0;
						if (found > 0) {
							pwRow(tbl, 'Aether Node', E('code', {}, String(st.matched_nodes || '').trim()));
						} else if (conflicts > 0) {
							pwRow(tbl, 'Aether Node', E('span', {
								'style': 'color:#e67e22'
							}, 'Points elsewhere:' + (st.conflict_nodes || '')));
						} else {
							pwRow(tbl, 'Aether Node', E('span', { 'style': 'color:#888' }, 'Not configured'));
						}
						pwSection.appendChild(tbl);

						if (found === 0 && conflicts > 0) {
							/* Never offer to create a second node — instruct instead. */
							var firstName = String(st.conflict_names || '').trim().split(/\s+/)[0] || '';
							pwSection.appendChild(E('div', { 'class': 'alert-message warning' }, [
								'A Passwall2 node for Aether already exists but points at a different address/port.',
								E('br'),
								'Fix it manually (pick one):',
								E('br'),
								'1. Services \u2192 Passwall2 \u2192 Nodes \u2192 edit "' + firstName + '": set Address/Port to ',
								E('strong', {}, st.aether_socks_addr || '?'),
								', then Save & Apply.',
								E('br'),
								'2. Delete that node, apply, and reload this page \u2014 the Create button will appear.'
							]));
							return;
						}

						var btnRow = E('div', {
							'style': 'margin-top:8px;display:flex;gap:8px;align-items:center;flex-wrap:wrap'
						});

						if (st.localhost_proxy === '1') {
							var offBtn = E('input', {
								'type': 'button',
								'class': 'cbi-button cbi-button-remove',
								'value': 'Disable Localhost Proxy',
								'click': function() {
									var btn = this;
									pwRunCtl([ 'passwall', 'localhost', 'off' ], btn, 'Disabling...').then(function(ok) {
										if (ok) setTimeout(refreshPasswall, 1200);
									});
								}
							});
							btnRow.appendChild(offBtn);
							btnRow.appendChild(E('span', {
								'style': 'font-size:12px;color:#888'
							}, 'Sets localhost_proxy=0 in /etc/config/passwall2 and restarts Passwall2 if it is enabled.'));
						}

						if (found === 0 && conflicts === 0) {
							var addBtn = E('input', {
								'type': 'button',
								'class': 'cbi-button cbi-button-apply',
								'value': 'Create Aether Node',
								'click': function() {
									var btn = this;
									pwRunCtl([ 'passwall', 'add-node' ], btn, 'Creating...').then(function(ok) {
										if (ok) setTimeout(refreshPasswall, 1200);
									});
								}
							});
							btnRow.appendChild(addBtn);
							btnRow.appendChild(E('span', {
								'style': 'font-size:12px;color:#888'
							}, 'Adds a Passwall2 socks node named "aether_node" pointing at Aether (' + (st.aether_socks_addr || '127.0.0.1:1819') + ').'));
						}

						if (btnRow.firstChild)
							pwSection.appendChild(btnRow);
					}).catch(function() {
						pwSection.appendChild(E('p', {
							'style': 'margin:4px 0;color:#666;font-size:13px'
						}, 'Could not query Passwall2 status (aether-ctl passwall status failed).'));
					});
				}

				el.appendChild(pwSection);
				refreshPasswall();
				return el;
			});
		});
	}
});
