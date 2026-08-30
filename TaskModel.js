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
    description: plainDisplay(task.description, 2000)
  }
}

function normalizeTasks(tasks) {
  if (!Array.isArray(tasks)) return []
  return tasks.map(normalizedTask).filter(function(task) { return task.id })
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
  return list
    .filter(function(task) { return isPending(task) && !!task.due })
    .sort(function(a, b) {
      var dueA = String(a.due || '')
      var dueB = String(b.due || '')
      return dueA.localeCompare(dueB)
    })
    .slice(0, limit)
}

function backlogTasks(tasks) {
  var list = normalizeTasks(tasks)
  return list
    .filter(function(task) { return isPending(task) && !task.due })
    .sort(function(a, b) {
      var createdA = String(a.created || '')
      var createdB = String(b.created || '')
      return createdB.localeCompare(createdA)
    })
}

function doneTasks(tasks, maxCount) {
  var limit = maxCount || 10
  var list = normalizeTasks(tasks)
  return list
    .filter(function(task) { return isCompleted(task) })
    .sort(function(a, b) {
      var completedA = String(a.completed || '')
      var completedB = String(b.completed || '')
      return completedB.localeCompare(completedA)
    })
    .slice(0, limit)
}

function parseHelperResponse(text) {
  try {
    var parsed = JSON.parse(String(text || '{}'))
    return {
      ok: parsed.ok === true,
      provider: String(parsed.provider || ''),
      calendars: Array.isArray(parsed.calendars) ? parsed.calendars : [],
      tasks: normalizeTasks(parsed.tasks),
      error: parsed.error || null
    }
  } catch (error) {
    return { ok: false, provider: '', calendars: [], tasks: [], error: { code: 'invalid-json', message: String(error) } }
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

if (typeof module !== 'undefined') module.exports = {
  isCompleted,
  isOverdue,
  isPending,
  backlogTasks,
  doneTasks,
  upcomingTasks,
  normalizeTasks,
  normalizedTask,
  parseHelperResponse,
  formatDueDate,
  formatCompletedDate
}
