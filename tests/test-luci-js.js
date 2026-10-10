/*
 * Tests for the pure helpers in the LuCI view (files/www/.../view/aether.js).
 *
 * The view is a LuCI module: it opens with 'require x' directives and ends
 * with `return view.extend({...})`, so it cannot simply be require()d. Instead
 * each helper is EXTRACTED from the real source by brace matching (skipping
 * comments, strings and regex literals) and evaluated here — the tests run
 * against shipped code, not a copy.
 *
 * The headline check is cross-language: the aetherCoreSupportsVNN gates that
 * decide what the web UI shows must agree with the core_supports_vNN gates
 * aether-ctl enforces. A disagreement means the UI offers a setting the CLI
 * will reject, or hides one it would accept.
 *
 * Run with: node tests/test-luci-js.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const VIEW = path.join(ROOT, 'files/www/luci-static/resources/view/aether.js');
const MATRIX = path.join(ROOT, 'tests/fixtures/version-matrix.sh');

const src = fs.readFileSync(VIEW, 'utf8');

let failures = 0;
let passed = 0;

function pass() { passed++; }
function fail(msg) { failures++; console.log('FAIL: ' + msg); }
function eq(label, want, got) {
	if (want === got) pass();
	else fail(`${label} (want ${JSON.stringify(want)}, got ${JSON.stringify(got)})`);
}
function isTrue(label, v) { eq(label, true, v); }
function isFalse(label, v) { eq(label, false, v); }

/* ------------------------------------------------------------------------
 * Source extraction
 * ---------------------------------------------------------------------- */

// True when a '/' at index i begins a regex literal rather than a division.
function regexStartsAt(s, i) {
	let j = i - 1;
	while (j >= 0 && /\s/.test(s[j])) j--;
	if (j < 0) return true;
	const c = s[j];
	if ('(,=:[!&|?{};+-*%~^<>'.includes(c)) return true;
	// "return /re/" — keyword operand.
	const kw = ['return', 'typeof', 'case', 'in', 'of', 'new', 'delete', 'void'];
	for (const k of kw) {
		if (s.slice(j - k.length + 1, j + 1) === k) {
			const before = j - k.length;
			if (before < 0 || !/[A-Za-z0-9_$]/.test(s[before])) return true;
		}
	}
	return false;
}

// Index of the '}' that closes the '{' at openIdx.
function matchBrace(s, openIdx) {
	let depth = 0;
	let i = openIdx;
	while (i < s.length) {
		const c = s[i];
		if (c === '/' && s[i + 1] === '/') {
			const nl = s.indexOf('\n', i);
			if (nl < 0) break;
			i = nl + 1;
			continue;
		}
		if (c === '/' && s[i + 1] === '*') {
			const end = s.indexOf('*/', i + 2);
			if (end < 0) break;
			i = end + 2;
			continue;
		}
		if (c === '"' || c === "'" || c === '`') {
			i++;
			while (i < s.length && s[i] !== c) {
				if (s[i] === '\\') i++;
				i++;
			}
			i++;
			continue;
		}
		if (c === '/' && regexStartsAt(s, i)) {
			i++;
			while (i < s.length && s[i] !== '/') {
				if (s[i] === '\\') i++;
				else if (s[i] === '[') {
					i++;
					while (i < s.length && s[i] !== ']') {
						if (s[i] === '\\') i++;
						i++;
					}
				}
				i++;
			}
			i++;
			while (i < s.length && /[a-z]/.test(s[i])) i++;
			continue;
		}
		if (c === '{') depth++;
		else if (c === '}') {
			depth--;
			if (depth === 0) return i;
		}
		i++;
	}
	throw new Error('unbalanced braces after index ' + openIdx);
}

function extract(header) {
	const at = src.indexOf(header);
	if (at < 0) throw new Error('cannot locate "' + header + '" in aether.js');
	const open = src.indexOf('{', at);
	if (open < 0) throw new Error('no body for "' + header + '"');
	return src.slice(at, matchBrace(src, open) + 1);
}

const FN_NAMES = [
	'aetherProfileLabels',
	'aetherProfileDefault',
	'aetherCoreSupportsV16',
	'aetherCoreSupportsV17',
	'aetherCoreSupportsV18',
	'aetherCoreSupportsV19',
	'aetherCoreSupportsV20',
	'aetherCoreSupportsV21',
	'aetherCoreSupportsV23',
	'aetherPsiphonState',
	'extractFromLogs',
	'parseKeyValues'
];

const code = [extract('var AETHER_PROFILES =')]
	.concat(FN_NAMES.map((n) => extract('function ' + n + '(')))
	.join('\n\n');

const view = new Function(code + '\nreturn {' + FN_NAMES.join(',') + '};')();

/* ------------------------------------------------------------------------
 * Obfuscation profile tables
 * ---------------------------------------------------------------------- */

const wgKeys = Object.keys(view.aetherProfileLabels('wg')).sort().join(',');
eq('wg profile keys', 'aggressive,balanced,light,off', wgKeys);

const masqueKeys = Object.keys(view.aetherProfileLabels('masque')).sort().join(',');
eq('masque profile keys', 'firewall,gfw,off', masqueKeys);

eq('mim shares the masque profile table', masqueKeys,
	Object.keys(view.aetherProfileLabels('mim')).sort().join(','));
eq('gool shares the wg profile table', wgKeys,
	Object.keys(view.aetherProfileLabels('gool')).sort().join(','));
eq('unknown protocol falls back to masque', masqueKeys,
	Object.keys(view.aetherProfileLabels('nonsense')).sort().join(','));
eq('missing protocol falls back to masque', masqueKeys,
	Object.keys(view.aetherProfileLabels(undefined)).sort().join(','));

eq('wg defaults to balanced', 'balanced', view.aetherProfileDefault('wg'));
eq('gool defaults to balanced', 'balanced', view.aetherProfileDefault('gool'));
eq('masque defaults to firewall', 'firewall', view.aetherProfileDefault('masque'));
eq('mim defaults to firewall', 'firewall', view.aetherProfileDefault('mim'));
eq('unknown protocol defaults to firewall', 'firewall', view.aetherProfileDefault('zzz'));

// Every default must exist in its own label table, or the select renders blank.
for (const p of ['wg', 'gool', 'masque', 'mim']) {
	const def = view.aetherProfileDefault(p);
	isTrue(`default '${def}' is a listed ${p} profile`,
		Object.prototype.hasOwnProperty.call(view.aetherProfileLabels(p), def));
}

/* ------------------------------------------------------------------------
 * Log parsing
 * ---------------------------------------------------------------------- */

eq('extractFromLogs pulls the first capture group', '1.2.3.4',
	view.extractFromLogs('connecting to 1.2.3.4 now', /to (\S+) now/));
eq('extractFromLogs returns empty when the pattern is absent', '',
	view.extractFromLogs('nothing here', /to (\S+) now/));
eq('extractFromLogs tolerates null logs', '', view.extractFromLogs(null, /(\d+)/));
eq('extractFromLogs tolerates empty logs', '', view.extractFromLogs('', /(\d+)/));

// parseKeyValues consumes the exact output of `aether-ctl passwall status`,
// which emits strict "key=value" lines with no padding around '='. Values may
// carry a leading space (matched_nodes is built by appending " sec(remark)"),
// which is what the .trim() is for.
const PW_STATUS = [
	'passwall2_present=1',
	'passwall2_enabled=1',
	'localhost_proxy=1',
	'client_proxy=0',
	'aether_socks_addr=127.0.0.1:1819',
	'node_found=1',
	'matched_nodes= cfg02f9a1(Aether SOCKS5)',
	'conflict_count=0',
	'conflict_nodes=',
	'conflict_names='
].join('\n');

const kv = view.parseKeyValues(PW_STATUS);
eq('parseKeyValues reads passwall2_present', '1', kv.passwall2_present);
eq('parseKeyValues reads localhost_proxy', '1', kv.localhost_proxy);
eq('parseKeyValues reads a value containing : and .', '127.0.0.1:1819', kv.aether_socks_addr);
eq('parseKeyValues reads node_found', '1', kv.node_found);
eq('parseKeyValues trims the leading space off matched_nodes',
	'cfg02f9a1(Aether SOCKS5)', kv.matched_nodes);
eq('parseKeyValues keeps an empty value as an empty string', '', kv.conflict_nodes);
eq('parseKeyValues parses every line', 10, Object.keys(kv).length);

// Prose and indented noise must not become keys.
const noisy = view.parseKeyValues(
	PW_STATUS + '\nPasswall2 config not found\n   \nnot a pair\n=orphan\n');
eq('parseKeyValues ignores prose and malformed lines', 10, Object.keys(noisy).length);
eq('parseKeyValues tolerates null', 0, Object.keys(view.parseKeyValues(null)).length);
eq('parseKeyValues tolerates undefined', 0, Object.keys(view.parseKeyValues(undefined)).length);
// The /i flag means an upper-case key is still captured.
eq('parseKeyValues accepts an upper-case key', 'x', view.parseKeyValues('Key=x').Key);

/* ------------------------------------------------------------------------
 * Psiphon status classification
 * ---------------------------------------------------------------------- */

const missingPsiphonHelperLog =
	'Error: Other("psiphon needs the psiphon-tunnel-core console client, and it was not in /usr/bin/pt")';
eq('Psiphon off is disabled', 'off', view.aetherPsiphonState('off', '2.3.0', '', false));
eq('Psiphon config on old core is unsupported', 'unsupported',
	view.aetherPsiphonState('only', '2.0.0', '', false));
eq('Psiphon only reports its own state', 'only',
	view.aetherPsiphonState('only', '2.3.0', '', true));
eq('Psiphon helper failure is surfaced while stopped', 'helper-missing',
	view.aetherPsiphonState('only', 'v2.3.0', missingPsiphonHelperLog, false));
eq('stale helper failure is ignored while running', 'only',
	view.aetherPsiphonState('only', '2.3.0', missingPsiphonHelperLog, true));
eq('Psiphon tunnel reports enabled', 'enabled',
	view.aetherPsiphonState('tunnel', '2.3.0', '', true));
eq('Psiphon reverse reports enabled', 'enabled',
	view.aetherPsiphonState('reverse', '2.3.0', '', false));
eq('invalid Psiphon mode is recognized', 'invalid',
	view.aetherPsiphonState('bad-mode', '2.3.0', '', false));

/* ------------------------------------------------------------------------
 * Capability gates: JS behaviour
 * ---------------------------------------------------------------------- */

const gates = [
	['V16', view.aetherCoreSupportsV16, '1.5.9', '1.6.0'],
	['V17', view.aetherCoreSupportsV17, '1.6.9', '1.7.0'],
	['V18', view.aetherCoreSupportsV18, '1.7.9', '1.8.0'],
	['V19', view.aetherCoreSupportsV19, '1.8.9', '1.9.0'],
	['V20', view.aetherCoreSupportsV20, '1.9.9', '2.0.0'],
	['V21', view.aetherCoreSupportsV21, '2.0.9', '2.1.0'],
	['V23', view.aetherCoreSupportsV23, '2.2.9', '2.3.0']
];

for (const [name, fn, below, at] of gates) {
	isFalse(`${name} rejects ${below}`, fn(below));
	isTrue(`${name} accepts ${at}`, fn(at));
	isTrue(`${name} accepts 3.0.0`, fn('3.0.0'));
	isFalse(`${name} rejects an empty version`, fn(''));
	isFalse(`${name} rejects null`, fn(null));
	isFalse(`${name} rejects undefined`, fn(undefined));
	isFalse(`${name} rejects garbage`, fn('garbage'));
	// The view is handed raw `aether --version` output, so it must parse a
	// decorated string and an explicit "v" prefix.
	isTrue(`${name} accepts 'v${at}'`, fn('v' + at));
	isTrue(`${name} accepts a raw banner`, fn(`aether version v${at} (linux musl)`));
}

// Monotonicity: a core new enough for the newest gate satisfies every older one.
for (const v of ['2.3.0', '2.4.1', '3.0.0', '10.2.0']) {
	for (const [name, fn] of gates) isTrue(`${name} accepts ${v}`, fn(v));
}
// A v1.5 core must satisfy no v2 gate.
const V2_GATES = gates.filter(([name]) => ['V20', 'V21', 'V23'].includes(name));
for (const [name, fn] of V2_GATES) isFalse(`${name} rejects 1.5.0`, fn('1.5.0'));

/* ------------------------------------------------------------------------
 * Cross-language consistency with aether-ctl
 * ---------------------------------------------------------------------- */

let matrixOut;
try {
	matrixOut = execFileSync('sh', [MATRIX], { encoding: 'utf8' });
} catch (e) {
	console.log('FAIL: could not run tests/fixtures/version-matrix.sh: ' + e.message);
	process.exit(1);
}

const jsForGate = {
	v16: view.aetherCoreSupportsV16,
	v17: view.aetherCoreSupportsV17,
	v18: view.aetherCoreSupportsV18,
	v19: view.aetherCoreSupportsV19,
	v20: view.aetherCoreSupportsV20,
	v21: view.aetherCoreSupportsV21,
	v23: view.aetherCoreSupportsV23
};

let compared = 0;
const divergences = [];
for (const line of matrixOut.split('\n')) {
	if (!line.trim()) continue;
	const [gate, version, shellResult] = line.split(' ');
	const fn = jsForGate[gate];
	if (!fn) { divergences.push(`unknown gate ${gate}`); continue; }
	const jsResult = fn(version) ? '1' : '0';
	compared++;
	if (jsResult !== shellResult) {
		divergences.push(`${gate} @ ${version}: LuCI=${jsResult} aether-ctl=${shellResult}`);
	}
}

if (compared === 0) {
	fail('version matrix produced no rows');
} else if (divergences.length) {
	fail(`${divergences.length} LuCI/CLI capability divergence(s):\n        ` +
		divergences.join('\n        '));
} else {
	passed++;
	console.log(`PASS: LuCI gates agree with aether-ctl across ${compared} version/gate pairs`);
}

console.log('----');
console.log(`assertions passed: ${passed}   failures: ${failures}`);
if (failures === 0) console.log('all luci-js checks passed');
else {
	console.log(`${failures} luci-js assertion(s) FAILED`);
	process.exit(1);
}
