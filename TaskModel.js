var debugEnabled = false

// Plain module-level vars work fine here: the file is imported as a shared JS
// library (import "TaskModel.js" as TaskModel) by the QML files that need it.
function setDebugEnabled(value) {
  debugEnabled = value === true
}

function parseDateTime(value) {
  var timestamp = Date.parse(String(value || ''))
  return isNaN(timestamp) ? null : new Date(timestamp)
}

function plainDisplay(value, maxLen) {
  var text = String(value == null ? '' : value)
  text = text.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
  text = text.replace(/<[^>]*>/g, '')
  var limit = maxLen || 400
  if (text.length > limit) text = text.slice(0, limit)
  return text
}

var MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']
var SHORT_MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

function normalizedTask(raw) {
  var task = raw || {}
  return {
    id: String(task.id || task.uid || ''),
    uid: String(task.uid || ''),
    title: plainDisplay(task.title || task.summary || '(No title)', 400) || '(No title)',
    due: String(task.due || ''),
    start: String(task.start || ''),
    completed: String(task.completed || ''),
    status: String(task.status || 'NEEDS-ACTION'),
    priority: String(task.priority || ''),
    created: String(task.created || ''),
    calendarId: String(task.calendarId || task.calendar_uid || ''),
    calendarName: plainDisplay(task.calendarName || task.calendar || 'Calendar', 120),
    calendarColor: String(task.calendarColor || ''),
    description: plainDisplay(task.description, 2000),
    categories: Array.isArray(task.categories) ? task.categories.slice() : []
  }
}

function normalizeTasks(tasks) {
  if (!Array.isArray(tasks)) {
    if (debugEnabled) console.log("[TaskModel] normalizeTasks: input is not array:", typeof tasks)
    return []
  }
  var result = tasks.map(normalizedTask).filter(function(task) { return task.id })
  if (debugEnabled) console.log("[TaskModel] normalizeTasks: input:", tasks.length, "output:", result.length)
  return result
}

// Case-insensitive keyword filter for the keyboard "/" search: every
// whitespace-separated word must appear in the title, description, calendar
// name or a category. An empty query returns the list untouched.
function filterTasks(tasks, query) {
  var words = String(query == null ? '' : query).toLowerCase().split(/\s+/).filter(function(word) { return word !== '' })
  if (!Array.isArray(tasks) || words.length === 0) return tasks
  return tasks.filter(function(task) {
    if (!task) return false
    var haystack = [task.title, task.description, task.calendarName, (task.categories || []).join(' ')].join(' ').toLowerCase()
    for (var i = 0; i < words.length; i++) if (haystack.indexOf(words[i]) < 0) return false
    return true
  })
}

function isOverdue(task, now) {
  if (!task || !task.due) return false
  if (task.status === 'COMPLETED') return false
  var due = parseDateTime(task.due)
  if (!due) return false
  var current = now && !isNaN(now.getTime()) ? now : new Date()
  return due.getTime() < current.getTime()
}

function isPending(task) {
  if (!task) return false
  var s = String(task.status || '').toUpperCase()
  return s === 'NEEDS-ACTION' || s === 'IN-PROCESS'
}

function isCompleted(task) {
  if (!task) return false
  return String(task.status || '').toUpperCase() === 'COMPLETED'
}

function upcomingTasks(tasks, maxCount) {
  var limit = maxCount || 5
  var list = normalizeTasks(tasks)
  var pending = list.filter(function(task) { return isPending(task) })
  var withDue = pending.filter(function(task) { return !!task.due })
  if (debugEnabled) console.log("[TaskModel] upcomingTasks: total:", list.length, "pending:", pending.length, "withDue:", withDue.length)
  return withDue
    .sort(function(a, b) {
      var dueA = String(a.due || '')
      var dueB = String(b.due || '')
      return dueA.localeCompare(dueB)
    })
    .slice(0, limit)
}

// Uncapped counterpart of upcomingTasks: same filter+sort, no slice. The
// tasks popup hands the full list to the view, which owns pagination.
function allUpcomingTasks(tasks) {
  var list = normalizeTasks(tasks)
  var pending = list.filter(function(task) { return isPending(task) })
  var withDue = pending.filter(function(task) { return !!task.due })
  if (debugEnabled) console.log("[TaskModel] allUpcomingTasks: total:", list.length, "withDue:", withDue.length)
  return withDue
    .sort(function(a, b) {
      var dueA = String(a.due || '')
      var dueB = String(b.due || '')
      return dueA.localeCompare(dueB)
    })
}

// Totals for the section headers: same predicates/filters as the list
// functions but uncapped, so counters report the full category even when the
// visible list is sliced to a display limit.
function upcomingTaskCount(tasks) {
  var list = normalizeTasks(tasks)
  var pending = list.filter(function(task) { return isPending(task) })
  var withDue = pending.filter(function(task) { return !!task.due })
  if (debugEnabled) console.log("[TaskModel] upcomingTaskCount: total:", list.length, "count:", withDue.length)
  return withDue.length
}

function backlogTasks(tasks) {
  var list = normalizeTasks(tasks)
  var result = list
    .filter(function(task) { return isPending(task) && !task.due })
    .sort(function(a, b) {
      var createdA = String(a.created || '')
      var createdB = String(b.created || '')
      return createdB.localeCompare(createdA)
    })
  if (debugEnabled) console.log("[TaskModel] backlogTasks: total:", list.length, "result:", result.length)
  return result
}

function backlogTaskCount(tasks) {
  var list = normalizeTasks(tasks)
  var result = list.filter(function(task) { return isPending(task) && !task.due })
  if (debugEnabled) console.log("[TaskModel] backlogTaskCount: total:", list.length, "count:", result.length)
  return result.length
}

function doneTasks(tasks, maxCount) {
  var limit = maxCount || 10
  var list = normalizeTasks(tasks)
  var result = list
    .filter(function(task) { return isCompleted(task) })
    .sort(function(a, b) {
      var completedA = String(a.completed || '')
      var completedB = String(b.completed || '')
      return completedB.localeCompare(completedA)
    })
    .slice(0, limit)
  if (debugEnabled) console.log("[TaskModel] doneTasks: total:", list.length, "result:", result.length)
  return result
}

// Uncapped counterpart of doneTasks: same filter+sort, no slice.
function allDoneTasks(tasks) {
  var list = normalizeTasks(tasks)
  var result = list
    .filter(function(task) { return isCompleted(task) })
    .sort(function(a, b) {
      var completedA = String(a.completed || '')
      var completedB = String(b.completed || '')
      return completedB.localeCompare(completedA)
    })
  if (debugEnabled) console.log("[TaskModel] allDoneTasks: total:", list.length, "result:", result.length)
  return result
}

function doneTaskCount(tasks) {
  var list = normalizeTasks(tasks)
  var result = list.filter(function(task) { return isCompleted(task) })
  if (debugEnabled) console.log("[TaskModel] doneTaskCount: total:", list.length, "count:", result.length)
  return result.length
}

function parseHelperResponse(text) {
  try {
    var parsed = JSON.parse(String(text || '{}'))
    // Write ops (create/update) return a singular `task`; list ops return a
    // `tasks` array — normalize both so finish handlers see one shape.
    var rawTasks = Array.isArray(parsed.tasks) ? parsed.tasks : (parsed.task ? [parsed.task] : [])
    return {
      ok: parsed.ok === true,
      provider: String(parsed.provider || ''),
      enabled: typeof parsed.enabled === 'boolean' ? parsed.enabled : null,
      calendars: Array.isArray(parsed.calendars) ? parsed.calendars : [],
      tasks: normalizeTasks(rawTasks),
      rev: typeof parsed.rev === 'number' ? parsed.rev : null,
      error: parsed.error || null
    }
  } catch (error) {
    return { ok: false, provider: '', enabled: null, calendars: [], tasks: [], rev: null, error: { code: 'invalid-json', message: String(error) } }
  }
}

// "Mon d" this year, "Mon d, YYYY" otherwise, for any stored task date.
function formatTaskDate(value) {
  var date = parseDateTime(value)
  if (!date) return ''
  var month = SHORT_MONTH_NAMES[date.getMonth()]
  var day = date.getDate()
  var year = date.getFullYear()
  var now = new Date()
  if (year === now.getFullYear()) return month + ' ' + day
  return month + ' ' + day + ', ' + year
}

function formatDueDate(task, timeFormat) {
  if (!task || !task.due) return ''
  return formatTaskDate(task.due)
}

function formatStartDate(task) {
  if (!task || !task.start) return ''
  return formatTaskDate(task.start)
}

// --- Typed date input -------------------------------------------------------
// The due and starts-by fields take a date in the user's locale (the shell passes
// Qt's short date pattern in). This is only the fallback when none is given:
// ISO order is unambiguous on every locale.
var DATE_INPUT_PATTERN = 'yyyy-MM-dd'

function padTwo(value) {
  var s = String(value)
  return s.length < 2 ? '0' + s : s
}

// Placeholder text such as "DD.MM.YYYY" for a pattern.
function dateInputHint(pattern) {
  return String(pattern || DATE_INPUT_PATTERN).replace(/d+/g, 'DD').replace(/M+/g, 'MM').replace(/y+/g, 'YYYY')
}

// Typed text -> day key 'YYYY-MM-DD', or '' when it is not a real date.
// Accepts separators (space . / - ,), a missing year (current year), two-digit
// years, and eight digits with no separators.
function parseDateInput(text, pattern, now) {
  var s = String(text == null ? '' : text).replace(/^\s+|\s+$/g, '')
  var order = (pattern || DATE_INPUT_PATTERN).match(/[dMy]+/g) || []
  order = order.map(function (token) { return token.charAt(0) })
  var parts = null
  var fields = order
  if (/^\d{8}$/.test(s) && order.length === 3) {
    parts = []
    var at = 0
    for (var k = 0; k < order.length; k++) {
      var width = order[k] === 'y' ? 4 : 2
      parts.push(s.substr(at, width))
      at += width
    }
  } else if (/^\d+([\s.\/\-,]+\d+){1,2}$/.test(s)) {
    parts = s.split(/[\s.\/\-,]+/)
    if (parts.length === 2) fields = order.filter(function (f) { return f !== 'y' })
    if (parts.length !== fields.length) return ''
  }
  if (!parts || parts.length !== fields.length) return ''
  var values = {}
  var year = now ? now.getFullYear() : new Date().getFullYear()
  for (var i = 0; i < fields.length; i++) {
    if (fields[i] === 'y') {
      if (parts[i].length === 3 || parts[i].length > 4) return ''
      year = parseInt(parts[i], 10)
      if (parts[i].length <= 2) year += 2000
    } else {
      values[fields[i]] = parseInt(parts[i], 10)
    }
  }
  var day = values.d
  var month = values.M
  if (year < 1000 || !(month >= 1 && month <= 12) || !(day >= 1 && day <= 31)) return ''
  var date = new Date(year, month - 1, day)
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) return ''
  return year + '-' + padTwo(month) + '-' + padTwo(day)
}

// Day key 'YYYY-MM-DD' -> text in the pattern, or '' for an empty key.
function formatDateInput(key, pattern) {
  var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key || ''))
  if (!match) return ''
  var year = parseInt(match[1], 10)
  var month = parseInt(match[2], 10)
  var day = parseInt(match[3], 10)
  return (pattern || DATE_INPUT_PATTERN).replace(/d+|M+|y+/g, function (token) {
    var letter = token.charAt(0)
    if (letter === 'y') return token.length === 2 ? padTwo(year % 100) : String(year)
    var value = letter === 'd' ? day : month
    return token.length === 2 ? padTwo(value) : String(value)
  })
}

function formatCompletedDate(task, timeFormat) {
  if (!task || !task.completed) return ''
  var date = parseDateTime(task.completed)
  if (!date) return ''
  var month = SHORT_MONTH_NAMES[date.getMonth()]
  var day = date.getDate()
  var year = date.getFullYear()
  var now = new Date()
  if (year === now.getFullYear()) return month + ' ' + day
  return month + ' ' + day + ', ' + year
}

var DEFAULT_CALENDAR_COLORS = ['#8aadf4', '#a6e3a1', '#f9e2af', '#f38ba8', '#cba6f7', '#94e2d5', '#fab387', '#89dceb', '#f2cdcd', '#b4befe']

function canToggleCalendar(calendar) {
  return String(calendar && calendar.id || '').indexOf('omarchy-calendar-') === 0
}

function serverConnections(calendars) {
  var servers = []
  var byHost = {}
  var list = Array.isArray(calendars) ? calendars : []
  for (var i = 0; i < list.length; i++) {
    var cal = list[i]
    if (!cal) continue
    var id = String(cal.id || '')
    if (id.indexOf('omarchy-calendar-') !== 0) continue
    var host = String(cal.host || '').toLowerCase().replace(/^www\./, '')
    if (!host) continue
    if (!byHost[host]) { byHost[host] = { host: host, count: 0 }; servers.push(byHost[host]) }
    byHost[host].count++
  }
  servers.sort(function(a, b) { return a.host < b.host ? -1 : a.host > b.host ? 1 : 0 })
  return servers
}

function providerLabel(provider, host) {
  var hostname = String(host || '').toLowerCase().replace(/^www\./, '')
  if (hostname) {
    var labels = hostname.split('.')
    if (labels[0] === 'caldav' || labels[0] === 'carddav' || labels[0] === 'dav') labels = labels.slice(1)
    var domain = labels.slice(-2).join('.')
    var named = {
      'icloud.com': 'iCloud',
      'icloud.com.cn': 'iCloud',
      'google.com': 'Google',
      'googleapis.com': 'Google',
      'fastmail.com': 'Fastmail',
      'fastmail.fm': 'Fastmail',
      'yahoo.com': 'Yahoo'
    }
    if (named[domain]) return named[domain]
    if (named[hostname]) return named[hostname]
    var label = labels[0] || hostname
    return label.charAt(0).toUpperCase() + label.slice(1)
  }
  if (provider === 'caldav') return 'CalDAV'
  if (provider === 'local') return 'On this computer'
  if (provider === 'gnome-online-accounts') return 'Online account'
  return 'Local'
}

function calendarDisplayName(calendar, names) {
  if (!calendar) return 'Calendar'
  var overrides = names || {}
  var override = overrides[calendar.id]
  if (override) return String(override)
  return plainDisplay(calendar.name || 'Calendar', 120) || 'Calendar'
}

function calendarDisplayColor(calendar, colors, index) {
  if (!calendar) return DEFAULT_CALENDAR_COLORS[0]
  var overrides = colors || {}
  if (overrides[calendar.id]) return String(overrides[calendar.id])
  if (calendar.color) return String(calendar.color)
  return DEFAULT_CALENDAR_COLORS[Math.abs(index || 0) % DEFAULT_CALENDAR_COLORS.length]
}

function colorsMatch(a, b) {
  var norm = function(v) { return String(v || '').trim().toLowerCase() }
  var left = norm(a)
  var right = norm(b)
  if (!left || !right) return false
  return left === right
}

function calendarChoiceLabel(calendar, names) {
  if (!calendar) return 'Calendar'
  return calendarDisplayName(calendar, names) + ' · ' + providerLabel(calendar.provider, calendar.host)
}

// Packs measured rows into wide-view columns of at most `budget` pixels, with
// `gap` pixels between rows. heights[i] is the rendered height of tasks[i];
// heights can be shorter than tasks while later rows are still unmeasured.
// Returns { status: 'pending' } while a measured row has not laid out yet,
// { status: 'grow' } when more rows must be measured to fill the columns, or
// { status: 'ok', pages } with at most `cap` columns.
function packWideColumns(tasks, heights, budget, gap, cap, canGrow) {
  var out = []
  var page = []
  var used = 0
  var unmeasured = false
  for (var i = 0; i < tasks.length; i++) {
    if (i >= heights.length) {
      unmeasured = true
      break
    }
    var height = heights[i]
    if (!(height > 0)) return { status: 'pending' }
    var cost = height + gap
    if (page.length > 0 && used + cost > budget) {
      out.push(page)
      page = []
      used = 0
      if (out.length >= cap) break
    }
    page.push(tasks[i])
    used += cost
  }
  if (unmeasured && out.length < cap && canGrow) return { status: 'grow' }
  if (page.length > 0 && out.length < cap) out.push(page)
  return { status: 'ok', pages: out }
}

if (typeof module !== 'undefined') module.exports = {
  isCompleted,
  isOverdue,
  isPending,
  backlogTasks,
  backlogTaskCount,
  doneTasks,
  allDoneTasks,
  doneTaskCount,
  upcomingTasks,
  allUpcomingTasks,
  upcomingTaskCount,
  normalizeTasks,
  normalizedTask,
  filterTasks,
  packWideColumns,
  parseHelperResponse,
  formatDueDate,
  formatStartDate,
  formatCompletedDate,
  DATE_INPUT_PATTERN,
  dateInputHint,
  parseDateInput,
  formatDateInput,
  canToggleCalendar,
  serverConnections,
  providerLabel,
  calendarDisplayName,
  calendarDisplayColor,
  colorsMatch,
  calendarChoiceLabel,
  DEFAULT_CALENDAR_COLORS
}
