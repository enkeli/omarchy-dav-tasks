// Keyboard action registry, shortcut parsing/matching and rebinding rules.
//
// Pure functions only (no QML types), so the behavior is unit-tested under
// node (test/keybindings-test.js) and imported into QML as a stateless JS
// library. Shortcut strings are canonical, e.g. "j", "G", "?", "Down",
// "Ctrl+Enter", "Ctrl+Shift+k". Unmodified printable keys keep the case that
// was typed ("g" and "G" are different keys); chords with Ctrl/Alt/Meta use a
// lower-case letter plus an explicit "Shift+" when shift is held.
//
// Contexts say where an action is live:
//   list     Pending / Done task lists
//   config   Config tab (calendars, servers, misc)
//   form     Add-task form
//   picker   Due-date grid inside the form
//   palette  Calendar color palette popup
// While a text field has focus ("editing"), only chords with Ctrl/Alt/Meta and
// function keys resolve, so typing is never swallowed.

var KEY_CODES = {
  0x20: "Space",
  0x01000000: "Escape",
  0x01000001: "Tab",
  0x01000002: "Tab",
  0x01000003: "Backspace",
  0x01000004: "Enter",
  0x01000005: "Enter",
  0x01000007: "Delete",
  0x01000010: "Home",
  0x01000011: "End",
  0x01000012: "Left",
  0x01000013: "Up",
  0x01000014: "Right",
  0x01000015: "Down",
  0x01000016: "PageUp",
  0x01000017: "PageDown"
}
for (var fn = 1; fn <= 12; fn++) KEY_CODES[0x01000030 + fn - 1] = "F" + fn

var MODIFIER_ONLY = { 0x01000020: true, 0x01000021: true, 0x01000022: true, 0x01000023: true, 0x01001103: true }

var NAMED = {}
Object.keys(KEY_CODES).forEach(function(code) { NAMED[KEY_CODES[code].toLowerCase()] = KEY_CODES[code] })
NAMED["return"] = "Enter"
NAMED["esc"] = "Escape"
NAMED["del"] = "Delete"
NAMED["pgup"] = "PageUp"
NAMED["pgdn"] = "PageDown"

// Escape and Tab keep fixed jobs (back/close, and cycling fields or bar
// panels), so they can neither be rebound nor taken by another action.
var FIXED = ["Escape", "Tab", "Shift+Tab"]

var LIST = ["list"]
var LISTS = ["list", "config"]
var EVERYWHERE = ["list", "config", "form"]

// defaults: the first entry is the primary key shown in hints.
var ACTIONS = [
  { id: "help", label: "Show keyboard shortcuts", category: "Application", contexts: EVERYWHERE, defaults: ["?", "F1"], keywords: "help keys cheatsheet overview" },
  { id: "sync", label: "Sync now", category: "Application", contexts: EVERYWHERE, defaults: ["r", "Ctrl+r"], keywords: "refresh reload fetch" },
  { id: "wide", label: "Wide view: more pages as columns", category: "Application", contexts: EVERYWHERE, defaults: ["F11"], keywords: "fullscreen expand columns pages width" },
  { id: "addTask", label: "New task", category: "Application", contexts: LISTS, defaults: ["a", "n"], keywords: "add create todo" },
  { id: "tabPending", label: "Show pending tasks", category: "Application", contexts: LISTS, defaults: ["1"], keywords: "tab upcoming backlog" },
  { id: "tabDone", label: "Show completed tasks", category: "Application", contexts: LISTS, defaults: ["2"], keywords: "tab done finished" },
  { id: "tabConfig", label: "Open config", category: "Application", contexts: LISTS, defaults: ["3", "Ctrl+,"], keywords: "tab settings calendars servers preferences" },
  { id: "tabNext", label: "Next tab", category: "Application", contexts: LISTS, defaults: ["]"], keywords: "switch view" },
  { id: "tabPrev", label: "Previous tab", category: "Application", contexts: LISTS, defaults: ["["], keywords: "switch view" },

  { id: "cursorDown", label: "Move down", category: "Navigation", contexts: LISTS, defaults: ["j", "Down"], keywords: "next row cursor" },
  { id: "cursorUp", label: "Move up", category: "Navigation", contexts: LISTS, defaults: ["k", "Up"], keywords: "previous row cursor" },
  { id: "cursorTop", label: "Jump to first", category: "Navigation", contexts: LISTS, defaults: ["g", "Home"], keywords: "top start" },
  { id: "cursorBottom", label: "Jump to last", category: "Navigation", contexts: LISTS, defaults: ["G", "End"], keywords: "bottom end" },
  { id: "pagePrev", label: "Previous page", category: "Navigation", contexts: LIST, defaults: ["h", "Left", "PageUp"], keywords: "pager back" },
  { id: "pageNext", label: "Next page", category: "Navigation", contexts: LIST, defaults: ["l", "Right", "PageDown"], keywords: "pager forward" },
  { id: "filter", label: "Filter tasks", category: "Navigation", contexts: LIST, defaults: ["/"], keywords: "search find" },

  { id: "toggleExpand", label: "Show or hide task details", category: "Tasks", contexts: LIST, defaults: ["Enter", "o"], keywords: "expand collapse open description" },
  { id: "editTask", label: "Edit task", category: "Tasks", contexts: LIST, defaults: ["e"], keywords: "change rename modify update title description due" },
  { id: "toggleComplete", label: "Complete or reopen task", category: "Tasks", contexts: LIST, defaults: ["x", "Space"], keywords: "done check finish status" },
  { id: "deleteTask", label: "Delete task (press twice)", category: "Tasks", contexts: LIST, defaults: ["d", "Delete"], keywords: "remove trash confirm" },

  { id: "configActivate", label: "Toggle calendar or debug, open form", category: "Config", contexts: ["config"], defaults: ["Enter", "Space"], keywords: "enable disable activate press" },
  { id: "configColor", label: "Pick calendar color", category: "Config", contexts: ["config"], defaults: ["c"], keywords: "colour swatch palette" },
  { id: "connectServer", label: "Connect CalDAV server", category: "Config", contexts: ["config"], defaults: ["s"], keywords: "account login url" },

  { id: "formSubmit", label: "Create or save task", category: "New task form", contexts: ["form"], defaults: ["Ctrl+Enter"], keywords: "save submit add" },
  { id: "formPickDue", label: "Open due date picker", category: "New task form", contexts: ["form"], defaults: ["Ctrl+d"], keywords: "calendar date deadline" },
  { id: "formPickStart", label: "Open starts-by date picker", category: "New task form", contexts: ["form"], defaults: ["Ctrl+t"], keywords: "calendar date begin start" },
  { id: "formCalendarPopup", label: "Choose calendar from list", category: "New task form", contexts: ["form"], defaults: ["Ctrl+l"], keywords: "list target dropdown" },
  { id: "formCalendarNext", label: "Next calendar", category: "New task form", contexts: ["form"], defaults: ["Ctrl+j"], keywords: "list target" },
  { id: "formCalendarPrev", label: "Previous calendar", category: "New task form", contexts: ["form"], defaults: ["Ctrl+k"], keywords: "list target" },

  { id: "pickerLeft", label: "Previous day", category: "Due date picker", contexts: ["picker"], defaults: ["h", "Left"], keywords: "calendar" },
  { id: "pickerRight", label: "Next day", category: "Due date picker", contexts: ["picker"], defaults: ["l", "Right"], keywords: "calendar" },
  { id: "pickerUp", label: "Previous week", category: "Due date picker", contexts: ["picker"], defaults: ["k", "Up"], keywords: "calendar" },
  { id: "pickerDown", label: "Next week", category: "Due date picker", contexts: ["picker"], defaults: ["j", "Down"], keywords: "calendar" },
  { id: "pickerPrevMonth", label: "Previous month", category: "Due date picker", contexts: ["picker"], defaults: ["H", "PageUp", "["], keywords: "calendar" },
  { id: "pickerNextMonth", label: "Next month", category: "Due date picker", contexts: ["picker"], defaults: ["L", "PageDown", "]"], keywords: "calendar" },
  { id: "pickerToday", label: "Jump to today", category: "Due date picker", contexts: ["picker"], defaults: ["t"], keywords: "calendar" },
  { id: "pickerSelect", label: "Choose this day", category: "Due date picker", contexts: ["picker"], defaults: ["Enter", "Space"], keywords: "calendar pick" },
  { id: "pickerClear", label: "Remove due date", category: "Due date picker", contexts: ["picker"], defaults: ["x", "Delete", "Backspace"], keywords: "calendar clear" },

  { id: "palettePrev", label: "Previous color", category: "Color palette", contexts: ["palette"], defaults: ["h", "k", "Left", "Up"], keywords: "swatch" },
  { id: "paletteNext", label: "Next color", category: "Color palette", contexts: ["palette"], defaults: ["l", "j", "Right", "Down"], keywords: "swatch" },
  { id: "paletteSelect", label: "Use this color", category: "Color palette", contexts: ["palette"], defaults: ["Enter", "Space"], keywords: "swatch pick" }
]

function actions() {
  return ACTIONS.map(function(action) { return Object.assign({}, action) })
}

function actionById(id) {
  for (var i = 0; i < ACTIONS.length; i++) if (ACTIONS[i].id === id) return ACTIONS[i]
  return null
}

function isPrintable(ch) {
  return ch.length === 1 && ch.charCodeAt(0) >= 0x21 && ch.charCodeAt(0) <= 0x7e
}

function isLetter(ch) {
  return /^[A-Za-z]$/.test(ch)
}

var MODIFIER_NAMES = { ctrl: "Ctrl", control: "Ctrl", alt: "Alt", option: "Alt", meta: "Meta", super: "Meta", cmd: "Meta", shift: "Shift" }

function build(mods, key) {
  var parts = []
  if (mods.Ctrl) parts.push("Ctrl")
  if (mods.Alt) parts.push("Alt")
  if (mods.Meta) parts.push("Meta")
  if (mods.Shift) parts.push("Shift")
  parts.push(key)
  return parts.join("+")
}

// Canonical form of a user/default shortcut string, or "" when unsupported.
function normalizeShortcut(value) {
  var raw = String(value == null ? "" : value).trim()
  if (!raw || raw.length > 40) return ""
  var key
  var modNames
  if (raw === "+") { key = "+"; modNames = [] }
  else if (raw.slice(-2) === "++") { key = "+"; modNames = raw.slice(0, -2).split("+") }
  else {
    var parts = raw.split("+")
    key = parts.pop()
    modNames = parts
  }
  var mods = {}
  for (var i = 0; i < modNames.length; i++) {
    var name = MODIFIER_NAMES[modNames[i].trim().toLowerCase()]
    if (!name || mods[name]) return ""
    mods[name] = true
  }
  var chorded = !!(mods.Ctrl || mods.Alt || mods.Meta)
  var named = NAMED[key.toLowerCase()]
  if (key.length > 1 && !named) return ""
  if (named) {
    key = named
  } else {
    if (!isPrintable(key)) return ""
    if (isLetter(key)) {
      if (chorded) {
        if (key !== key.toLowerCase()) mods.Shift = true
        key = key.toLowerCase()
      } else if (mods.Shift) {
        key = key.toUpperCase()
        delete mods.Shift
      }
    } else {
      delete mods.Shift
    }
  }
  return build(mods, key)
}

// Canonical shortcut for a key event: { key, text, ctrl, alt, meta, shift }.
// Returns "" for modifier-only presses and unsupported keys.
function eventShortcut(event) {
  if (!event || event.isComposing || event.composing) return ""
  var code = Number(event.key)
  if (MODIFIER_ONLY[code]) return ""
  var mods = { Ctrl: !!event.ctrl, Alt: !!event.alt, Meta: !!event.meta, Shift: !!event.shift }
  var chorded = mods.Ctrl || mods.Alt || mods.Meta
  var named = KEY_CODES[code]
  var key = ""
  if (named) {
    key = named
    if (code === 0x01000002) mods.Shift = true
  } else if (chorded) {
    // Modified keys carry control characters in `text`; derive from the code.
    if (code >= 0x30 && code <= 0x39) key = String.fromCharCode(code)
    else if (code >= 0x41 && code <= 0x5a) key = String.fromCharCode(code).toLowerCase()
    else if (code >= 0x21 && code <= 0x7e) key = String.fromCharCode(code)
  } else {
    var text = String(event.text == null ? "" : event.text)
    if (text.length === 1 && isPrintable(text)) key = text
    else if (code >= 0x21 && code <= 0x7e) key = String.fromCharCode(code)
    if (key && isLetter(key) && !text) key = mods.Shift ? key.toUpperCase() : key.toLowerCase()
  }
  if (!key) return ""
  if (!named && (!isLetter(key) || !chorded)) mods.Shift = false
  return build(mods, key)
}

function isFixed(shortcut) {
  return FIXED.indexOf(shortcut) >= 0
}

function isChord(shortcut) {
  return /^(Ctrl|Alt|Meta)\+/.test(shortcut) || /^(Shift\+)?F\d+$/.test(shortcut)
}

function effectiveShortcuts(action, overrides) {
  var source = overrides && Object.prototype.hasOwnProperty.call(overrides, action.id)
    ? (Array.isArray(overrides[action.id]) ? overrides[action.id] : [overrides[action.id]])
    : action.defaults
  var out = []
  source.forEach(function(value) {
    var shortcut = normalizeShortcut(value)
    if (shortcut && out.indexOf(shortcut) < 0) out.push(shortcut)
  })
  return out
}

function contextsOverlap(a, b) {
  for (var i = 0; i < a.contexts.length; i++) if (b.contexts.indexOf(a.contexts[i]) >= 0) return true
  return false
}

// Returns { ok, overrides, error }. `overrides` maps action id -> array of
// canonical shortcuts ([] means deliberately unbound). Unknown or fixed keys
// and any two actions sharing a key in overlapping contexts are rejected.
function validateOverrides(overrides) {
  var supplied = overrides && typeof overrides === "object" && !Array.isArray(overrides) ? overrides : {}
  var normalized = {}
  for (var id in supplied) {
    if (!Object.prototype.hasOwnProperty.call(supplied, id)) continue
    var action = actionById(id)
    if (!action) return { ok: false, error: "Unknown keyboard action: " + id }
    var requested = Array.isArray(supplied[id]) ? supplied[id] : [supplied[id]]
    var values = []
    for (var i = 0; i < requested.length; i++) {
      if (String(requested[i] == null ? "" : requested[i]).trim() === "") continue
      var shortcut = normalizeShortcut(requested[i])
      if (!shortcut) return { ok: false, error: "Unsupported shortcut for " + action.label + "." }
      if (isFixed(shortcut)) return { ok: false, error: shortcut + " is reserved (Esc goes back, Tab moves between fields)." }
      if (values.indexOf(shortcut) < 0) values.push(shortcut)
    }
    normalized[id] = values
  }
  var conflict = findConflict(normalized)
  if (conflict) return { ok: false, error: conflict }
  return { ok: true, overrides: normalized }
}

function findConflict(overrides) {
  for (var a = 0; a < ACTIONS.length; a++) {
    var first = effectiveShortcuts(ACTIONS[a], overrides)
    for (var b = a + 1; b < ACTIONS.length; b++) {
      if (!contextsOverlap(ACTIONS[a], ACTIONS[b])) continue
      var second = effectiveShortcuts(ACTIONS[b], overrides)
      for (var x = 0; x < first.length; x++) {
        if (second.indexOf(first[x]) >= 0)
          return displayShortcut(first[x]) + " is used by both \"" + ACTIONS[a].label + "\" and \"" + ACTIONS[b].label + "\"."
      }
    }
  }
  return ""
}

// Replace every shortcut of an action by one recorded chord. Any other action
// in an overlapping context that already owns the chord loses it, so
// rebinding is one step instead of a conflict error the user must untangle.
// Returns validateOverrides' shape plus stolenFrom (labels that lost the key).
function rebind(overrides, actionId, shortcut) {
  var action = actionById(actionId)
  var chord = normalizeShortcut(shortcut)
  if (!action) return { ok: false, error: "Unknown keyboard action: " + actionId }
  if (!chord) return { ok: false, error: "That key can't be used." }
  if (isFixed(chord)) return { ok: false, error: chord + " is reserved (Esc goes back, Tab moves between fields)." }
  var next = Object.assign({}, overrides || {})
  var stolen = []
  ACTIONS.forEach(function(other) {
    if (other.id === actionId || !contextsOverlap(action, other)) return
    var current = effectiveShortcuts(other, next)
    if (current.indexOf(chord) < 0) return
    next[other.id] = current.filter(function(value) { return value !== chord })
    stolen.push(other.label)
  })
  next[actionId] = [chord]
  var result = validateOverrides(next)
  if (result.ok) result.stolenFrom = stolen
  return result
}

// Deliberately leave an action without any key.
function unbind(overrides, actionId) {
  if (!actionById(actionId)) return { ok: false, error: "Unknown keyboard action: " + actionId }
  var next = Object.assign({}, overrides || {})
  next[actionId] = []
  return validateOverrides(next)
}

function resetShortcut(overrides, actionId) {
  var next = Object.assign({}, overrides || {})
  delete next[actionId]
  return validateOverrides(next)
}

function displayShortcut(shortcut) {
  return String(shortcut || "").replace(/Meta/g, "Super")
}

function displayShortcuts(action, overrides) {
  var list = effectiveShortcuts(action, overrides).map(displayShortcut)
  return list.length ? list.join(" / ") : "unbound"
}

// First (primary) shortcut for hints such as footer legends; "" if unbound.
function primaryShortcut(actionId, overrides) {
  var action = actionById(actionId)
  if (!action) return ""
  var list = effectiveShortcuts(action, overrides)
  return list.length ? displayShortcut(list[0]) : ""
}

// Resolve a key event to an action in `context`. `options`:
//   overrides  saved rebindings (invalid ones are ignored, defaults apply)
//   editing    a text field has focus: only chords / function keys resolve
function resolve(event, context, options) {
  var shortcut = eventShortcut(event)
  if (!shortcut || isFixed(shortcut)) return { id: "" }
  var opts = options || {}
  if (opts.editing && !isChord(shortcut)) return { id: "" }
  var checked = validateOverrides(opts.overrides || {})
  var overrides = checked.ok ? checked.overrides : {}
  for (var i = 0; i < ACTIONS.length; i++) {
    var action = ACTIONS[i]
    if (action.contexts.indexOf(context) < 0) continue
    if (effectiveShortcuts(action, overrides).indexOf(shortcut) >= 0) return { id: action.id, action: action }
  }
  return { id: "" }
}

// Rows for the help overlay: every action matching `query` (all words must
// appear in label, category, keywords or the bound keys). Actions live in
// `context` come first and carry available = true.
function actionsForQuery(query, overrides, context) {
  var checked = validateOverrides(overrides || {})
  var effective = checked.ok ? checked.overrides : {}
  var words = String(query || "").toLowerCase().split(/\s+/).filter(function(word) { return word !== "" })
  var rows = []
  ACTIONS.forEach(function(action, index) {
    var shortcut = displayShortcuts(action, effective)
    var haystack = (action.label + " " + action.category + " " + action.keywords + " " + shortcut).toLowerCase()
    for (var i = 0; i < words.length; i++) if (haystack.indexOf(words[i]) < 0) return
    var copy = Object.assign({}, action)
    copy.shortcut = shortcut
    copy.customized = Object.prototype.hasOwnProperty.call(effective, action.id)
    copy.available = !context || action.contexts.indexOf(context) >= 0
    copy.group = copy.available ? "Available here" : "On other screens"
    copy.order = index
    rows.push(copy)
  })
  rows.sort(function(a, b) {
    if (a.available !== b.available) return a.available ? -1 : 1
    return a.order - b.order
  })
  return rows
}

if (typeof module !== "undefined") module.exports = {
  actions,
  actionById,
  normalizeShortcut,
  eventShortcut,
  isFixed,
  isChord,
  effectiveShortcuts,
  validateOverrides,
  rebind,
  unbind,
  resetShortcut,
  displayShortcut,
  displayShortcuts,
  primaryShortcut,
  resolve,
  actionsForQuery
}
