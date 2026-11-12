const assert = require('assert')
const kb = require('../Keybindings.js')

const K = { Escape: 0x01000000, Tab: 0x01000001, Backtab: 0x01000002, Return: 0x01000004, Delete: 0x01000007, Left: 0x01000012, Up: 0x01000013, Down: 0x01000015, F1: 0x01000030, Shift: 0x01000020 }
const ev = (key, text, mods) => Object.assign({ key, text: text === undefined ? '' : text, ctrl: false, alt: false, meta: false, shift: false }, mods || {})
const ch = (c, mods) => ev(c.toUpperCase().charCodeAt(0), c, mods)

// Event -> canonical shortcut
assert.equal(kb.eventShortcut(ch('j')), 'j')
assert.equal(kb.eventShortcut(ev(0x47, 'G', { shift: true })), 'G')
assert.equal(kb.eventShortcut(ev(0x3f, '?', { shift: true })), '?')
assert.equal(kb.eventShortcut(ev(0x2f, '/')), '/')
assert.equal(kb.eventShortcut(ev(K.Down, '')), 'Down')
assert.equal(kb.eventShortcut(ev(K.Return, '\r')), 'Enter')
assert.equal(kb.eventShortcut(ev(K.Return, '\r', { ctrl: true })), 'Ctrl+Enter')
assert.equal(kb.eventShortcut(ev(0x44, '\x04', { ctrl: true })), 'Ctrl+d')
assert.equal(kb.eventShortcut(ev(0x44, '\x04', { ctrl: true, shift: true })), 'Ctrl+Shift+d')
assert.equal(kb.eventShortcut(ev(0x2c, ',', { ctrl: true })), 'Ctrl+,')
assert.equal(kb.eventShortcut(ev(0x20, ' ')), 'Space')
assert.equal(kb.eventShortcut(ev(K.Backtab, '')), 'Shift+Tab')
assert.equal(kb.eventShortcut(ev(K.F1, '')), 'F1')
assert.equal(kb.eventShortcut(ev(K.Shift, '', { shift: true })), '')
assert.equal(kb.eventShortcut(ev(0x31, '1')), '1')
assert.equal(kb.eventShortcut(ev(0x31, '!', { shift: true })), '!')
assert.equal(kb.eventShortcut(null), '')

// Normalizing typed/stored shortcuts
assert.equal(kb.normalizeShortcut('ctrl+K'), 'Ctrl+Shift+k')
assert.equal(kb.normalizeShortcut('Shift+g'), 'G')
assert.equal(kb.normalizeShortcut('Shift+/'), '/')
assert.equal(kb.normalizeShortcut('return'), 'Enter')
assert.equal(kb.normalizeShortcut('Ctrl++'), 'Ctrl++')
assert.equal(kb.normalizeShortcut('+'), '+')
assert.equal(kb.normalizeShortcut('Ctrl+Alt+x'), 'Ctrl+Alt+x')
assert.equal(kb.normalizeShortcut('Hyper+x'), '')
assert.equal(kb.normalizeShortcut('Ctrl+Ctrl+x'), '')
assert.equal(kb.normalizeShortcut('nonsense'), '')
assert.equal(kb.normalizeShortcut(''), '')
assert.equal(kb.normalizeShortcut('Shift+Down'), 'Shift+Down')

// Defaults are conflict free and every default round-trips through normalize
const defaults = kb.validateOverrides({})
assert.ok(defaults.ok, defaults.error)
kb.actions().forEach(a => {
  assert.ok(a.defaults.length > 0, a.id)
  a.defaults.forEach(s => assert.equal(kb.normalizeShortcut(s), s, a.id + ' ' + s))
  a.defaults.forEach(s => assert.ok(!kb.isFixed(s), a.id + ' uses a fixed key'))
})

// Resolution per context: vim keys and arrows both move the cursor
const r = (e, ctx, o) => kb.resolve(e, ctx, o).id
assert.equal(r(ch('j'), 'list'), 'cursorDown')
assert.equal(r(ev(K.Down, ''), 'list'), 'cursorDown')
assert.equal(r(ev(K.Up, ''), 'config'), 'cursorUp')
assert.equal(r(ev(K.Left, ''), 'list'), 'pagePrev')
assert.equal(r(ev(K.Left, ''), 'picker'), 'pickerLeft')
assert.equal(r(ev(K.Left, ''), 'config'), '')
assert.equal(r(ev(0x47, 'G', { shift: true }), 'list'), 'cursorBottom')
assert.equal(r(ev(0x3f, '?', { shift: true }), 'form'), 'help')
assert.equal(r(ch('x'), 'list'), 'toggleComplete')
assert.equal(r(ch('e'), 'list'), 'editTask')
assert.equal(r(ch('e'), 'config'), '')
assert.equal(r(ev(K.Return, '\r'), 'list'), 'toggleExpand')
assert.equal(r(ev(K.Return, '\r'), 'config'), 'configActivate')
assert.equal(r(ev(K.Return, '\r', { ctrl: true }), 'form'), 'formSubmit')
assert.equal(r(ev(K.Escape, ''), 'list'), '')
assert.equal(r(ev(K.Tab, ''), 'list'), '')
assert.equal(r(ch('x'), 'palette'), '')

// Editing text: plain keys never resolve, chords and F-keys still do
assert.equal(r(ch('j'), 'form', { editing: true }), '')
assert.equal(r(ev(0x3f, '?', { shift: true }), 'form', { editing: true }), '')
assert.equal(r(ev(K.F1, ''), 'form', { editing: true }), 'help')
assert.equal(r(ev(0x44, '\x04', { ctrl: true }), 'form', { editing: true }), 'formPickDue')
assert.equal(r(ev(K.Return, '\r'), 'form', { editing: true }), '')

// Rebinding
let result = kb.rebind({}, 'sync', 'Ctrl+s')
assert.ok(result.ok)
assert.deepEqual(result.overrides, { sync: ['Ctrl+s'] })
assert.equal(r(ev(0x53, '\x13', { ctrl: true }), 'list', { overrides: result.overrides }), 'sync')
assert.equal(r(ch('r'), 'list', { overrides: result.overrides }), '')

// Rebinding onto a key another action in the same context uses steals it
result = kb.rebind({}, 'deleteTask', 'x')
assert.ok(result.ok)
assert.deepEqual(result.stolenFrom, ['Complete or reopen task'])
assert.equal(r(ch('x'), 'list', { overrides: result.overrides }), 'deleteTask')
assert.deepEqual(kb.effectiveShortcuts(kb.actionById('toggleComplete'), result.overrides), ['Space'])

// ...but a key shared across non-overlapping contexts is no conflict
result = kb.rebind({}, 'configColor', 'x')
assert.ok(result.ok)
assert.deepEqual(result.stolenFrom, [])
assert.equal(r(ch('x'), 'list', { overrides: result.overrides }), 'toggleComplete')

// Fixed and unsupported keys are refused
assert.ok(!kb.rebind({}, 'sync', 'Escape').ok)
assert.ok(!kb.rebind({}, 'sync', 'Shift+Tab').ok)
assert.ok(!kb.rebind({}, 'sync', 'banana').ok)
assert.ok(!kb.rebind({}, 'nope', 'q').ok)

// Hand-edited config is validated; bad config falls back to defaults at resolve time
assert.ok(!kb.validateOverrides({ nope: ['q'] }).ok)
assert.ok(!kb.validateOverrides({ sync: ['j'] }).ok)
assert.ok(!kb.validateOverrides({ sync: ['Escape'] }).ok)
assert.deepEqual(kb.validateOverrides({ sync: [] }).overrides, { sync: [] })
assert.equal(r(ch('r'), 'list', { overrides: { sync: ['j'] } }), 'sync')

// Unbinding and resetting
assert.deepEqual(kb.unbind({}, 'sync').overrides, { sync: [] })
assert.ok(!kb.unbind({}, 'nope').ok)
assert.equal(r(ch('r'), 'list', { overrides: { sync: [] } }), '')
assert.deepEqual(kb.resetShortcut({ sync: ['Ctrl+s'], tabDone: ['9'] }, 'sync').overrides, { tabDone: ['9'] })

// Help list: search words, availability ordering, custom keys shown
let rows = kb.actionsForQuery('', {}, 'list')
assert.equal(rows.length, kb.actions().length)
assert.ok(rows[0].available)
assert.equal(rows[0].group, 'Available here')
assert.equal(rows[rows.length - 1].group, 'On other screens')
assert.ok(rows.findIndex(x => !x.available) > rows.findIndex(x => x.available))
assert.ok(rows.filter(x => x.available).every(x => x.contexts.includes('list')))
rows = kb.actionsForQuery('delete', {}, 'list')
assert.equal(rows[0].id, 'deleteTask')
assert.equal(rows[0].shortcut, 'd / Delete')
rows = kb.actionsForQuery('complete done', {}, 'list')
assert.ok(rows.some(x => x.id === 'toggleComplete'))
assert.ok(!rows.some(x => x.id === 'deleteTask'))
rows = kb.actionsForQuery('ctrl', {}, 'form')
assert.ok(rows.some(x => x.id === 'formSubmit'))
rows = kb.actionsForQuery('zzzz', {}, 'list')
assert.equal(rows.length, 0)
rows = kb.actionsForQuery('sync', { sync: ['Meta+s'] }, 'list')
assert.equal(rows[0].shortcut, 'Super+s')
assert.ok(rows[0].customized)
assert.equal(kb.primaryShortcut('help', {}), '?')
assert.equal(kb.primaryShortcut('help', { help: [] }), '')

console.log('ok - keybindings')
