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

function formatDueDate(task, timeFormat) {
  if (!task || !task.due) return ''
  var date = parseDateTime(task.due)
  if (!date) return ''
  var month = SHORT_MONTH_NAMES[date.getMonth()]
  var day = date.getDate()
  var year = date.getFullYear()
  var now = new Date()
  if (year === now.getFullYear()) return month + ' ' + day
  return month + ' ' + day + ', ' + year
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
  parseHelperResponse,
  formatDueDate,
  formatCompletedDate,
  canToggleCalendar,
  serverConnections,
  providerLabel,
  calendarDisplayName,
  calendarDisplayColor,
  colorsMatch,
  calendarChoiceLabel,
  DEFAULT_CALENDAR_COLORS
}
