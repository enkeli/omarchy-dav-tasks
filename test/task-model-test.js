const assert = require('assert')
const model = require('../TaskModel.js')

// normalizedTask
assert.equal(model.normalizedTask({}).id, '')
assert.equal(model.normalizedTask({}).title, '(No title)')
assert.equal(model.normalizedTask({}).status, 'NEEDS-ACTION')
assert.equal(model.normalizedTask({ id: '1', uid: 'u1', title: 'Buy milk', due: '2026-08-20', completed: '', status: 'NEEDS-ACTION', priority: '1', created: '2026-08-01', calendarId: 'work' }).id, '1')
assert.equal(model.normalizedTask({ id: '1', uid: 'u1', title: 'Buy milk', due: '2026-08-20', completed: '', status: 'NEEDS-ACTION', priority: '1', created: '2026-08-01', calendarId: 'work' }).uid, 'u1')
assert.equal(model.normalizedTask({ id: '1', uid: 'u1', title: 'Buy milk', due: '2026-08-20', completed: '', status: 'NEEDS-ACTION', priority: '1', created: '2026-08-01', calendarId: 'work' }).title, 'Buy milk')
assert.equal(model.normalizedTask({ id: '1', uid: 'u1', title: 'Buy milk', due: '2026-08-20', completed: '', status: 'NEEDS-ACTION', priority: '1', created: '2026-08-01', calendarId: 'work' }).calendarId, 'work')
assert.equal(model.normalizedTask({ summary: 'Alt title' }).title, 'Alt title')
assert.equal(model.normalizedTask({ uid: 'u2' }).id, 'u2')
assert.equal(model.normalizedTask({ title: '<script>alert(1)</script>Clean' }).title, 'alert(1)Clean')
assert.equal(model.normalizedTask({ calendar_uid: 'cal1', calendarName: 'Cal 1' }).calendarId, 'cal1')
assert.equal(model.normalizedTask({ calendar: 'Cal 2' }).calendarName, 'Cal 2')
assert.equal(model.normalizedTask({ calendarColor: '#a6e3a1' }).calendarColor, '#a6e3a1')
assert.equal(model.normalizedTask({}).calendarColor, '')
assert.deepEqual(model.normalizedTask({ categories: ['Work', 'Personal'] }).categories, ['Work', 'Personal'])
assert.deepEqual(model.normalizedTask({ categories: 'Work' }).categories, [])

// normalizeTasks
assert.deepEqual(model.normalizeTasks(null), [])
assert.deepEqual(model.normalizeTasks('bad'), [])
assert.equal(model.normalizeTasks([]).length, 0)
assert.equal(model.normalizeTasks([{ id: '1', title: 'A' }, { id: '2', title: 'B' }]).length, 2)
assert.equal(model.normalizeTasks([{ id: '1', title: 'A' }, { title: 'No id' }]).length, 1)
assert.equal(model.normalizeTasks([{ id: '1', title: 'A' }, { id: '2', title: 'B' }])[0].id, '1')

// isOverdue
assert.equal(model.isOverdue(null), false)
assert.equal(model.isOverdue({}), false)
assert.equal(model.isOverdue({ due: '2026-08-20T10:00:00Z' }, new Date('2026-08-20T15:00:00Z')), true)
assert.equal(model.isOverdue({ due: '2026-08-20T10:00:00Z' }, new Date('2026-08-20T09:00:00Z')), false)
assert.equal(model.isOverdue({ due: '2026-08-20T10:00:00Z', status: 'COMPLETED' }, new Date('2026-08-20T15:00:00Z')), false)
assert.equal(model.isOverdue({ due: 'bad-date' }, new Date('2026-08-20T15:00:00Z')), false)

// isPending
assert.equal(model.isPending(null), false)
assert.equal(model.isPending({ status: 'NEEDS-ACTION' }), true)
assert.equal(model.isPending({ status: 'IN-PROCESS' }), true)
assert.equal(model.isPending({ status: 'COMPLETED' }), false)
assert.equal(model.isPending({ status: 'CANCELLED' }), false)

// isCompleted
assert.equal(model.isCompleted(null), false)
assert.equal(model.isCompleted({ status: 'COMPLETED' }), true)
assert.equal(model.isCompleted({ status: 'NEEDS-ACTION' }), false)
assert.equal(model.isCompleted({ status: 'IN-PROCESS' }), false)
assert.equal(model.isCompleted({ status: 'CANCELLED' }), false)

// upcomingTasks - sorted by due ascending, limited by maxCount
const upcomingInput = [
  { id: '3', title: 'C', status: 'NEEDS-ACTION', due: '2026-08-22' },
  { id: '1', title: 'A', status: 'NEEDS-ACTION', due: '2026-08-20' },
  { id: '2', title: 'B', status: 'NEEDS-ACTION', due: '2026-08-21' },
  { id: '4', title: 'D', status: 'COMPLETED', due: '2026-08-19' },
  { id: '5', title: 'E', status: 'IN-PROCESS', due: '2026-08-23' }
]
const upcoming = model.upcomingTasks(upcomingInput)
assert.equal(upcoming.length, 4)
assert.equal(upcoming[0].id, '1')
assert.equal(upcoming[1].id, '2')
assert.equal(upcoming[2].id, '3')
assert.equal(upcoming[3].id, '5')
assert.equal(model.upcomingTasks(upcomingInput, 2).length, 2)
assert.equal(model.upcomingTasks(upcomingInput, 2)[0].id, '1')
assert.equal(model.upcomingTasks(upcomingInput, 2)[1].id, '2')
assert.equal(model.upcomingTasks([]).length, 0)

// upcomingTaskCount - total pending tasks with a due date, ignoring the display cap
assert.equal(model.upcomingTaskCount(null), 0)
assert.equal(model.upcomingTaskCount(undefined), 0)
assert.equal(model.upcomingTaskCount([]), 0)
assert.equal(model.upcomingTaskCount(upcomingInput), 4)
const upcomingCountInput = [
  { id: '1', title: 'A', status: 'NEEDS-ACTION', due: '2026-08-20' },
  { id: '2', title: 'B', status: 'IN-PROCESS', due: '2026-08-21' },
  { id: '3', title: 'C', status: 'NEEDS-ACTION', due: '2026-08-22' },
  { id: '4', title: 'D', status: 'NEEDS-ACTION', due: '2026-08-23' },
  { id: '5', title: 'E', status: 'NEEDS-ACTION', due: '2026-08-24' },
  { id: '6', title: 'F', status: 'NEEDS-ACTION', due: '2026-08-25' },
  { id: '7', title: 'G', status: 'COMPLETED', due: '2026-08-19' },
  { id: '8', title: 'H', status: 'NEEDS-ACTION' }
]
assert.equal(model.upcomingTaskCount(upcomingCountInput), 6)
assert.equal(model.upcomingTasks(upcomingCountInput, 5).length, 5)

// allUpcomingTasks - full sorted upcoming list, no display cap
assert.equal(model.allUpcomingTasks(null).length, 0)
assert.equal(model.allUpcomingTasks(undefined).length, 0)
assert.equal(model.allUpcomingTasks([]).length, 0)
assert.equal(model.allUpcomingTasks(upcomingInput).length, 4)
assert.equal(model.allUpcomingTasks(upcomingInput)[0].id, '1')
const allUpcoming = model.allUpcomingTasks(upcomingCountInput)
assert.equal(allUpcoming.length, 6)
assert.equal(allUpcoming[0].id, '1')
assert.equal(allUpcoming[5].id, '6')
assert.equal(model.upcomingTasks(upcomingCountInput, 5).length, 5)

// backlogTasks - pending tasks without due date, sorted by created desc
const backlogInput = [
  { id: '1', title: 'A', status: 'NEEDS-ACTION', created: '2026-08-01T12:00:00Z' },
  { id: '2', title: 'B', status: 'NEEDS-ACTION', due: '2026-08-20', created: '2026-08-02T12:00:00Z' },
  { id: '3', title: 'C', status: 'IN-PROCESS', created: '2026-08-03T12:00:00Z' },
  { id: '4', title: 'D', status: 'COMPLETED', created: '2026-08-04T12:00:00Z' }
]
const backlog = model.backlogTasks(backlogInput)
assert.equal(backlog.length, 2)
assert.equal(backlog[0].id, '3')
assert.equal(backlog[1].id, '1')
assert.equal(model.backlogTasks([]).length, 0)

// backlogTaskCount - total pending tasks without a due date (list is uncapped)
assert.equal(model.backlogTaskCount(null), 0)
assert.equal(model.backlogTaskCount(undefined), 0)
assert.equal(model.backlogTaskCount([]), 0)
assert.equal(model.backlogTaskCount(backlogInput), 2)
assert.equal(model.backlogTaskCount(backlogInput), model.backlogTasks(backlogInput).length)

// doneTasks - completed tasks sorted by completed desc
const doneInput = [
  { id: '1', title: 'A', status: 'COMPLETED', completed: '2026-08-15' },
  { id: '2', title: 'B', status: 'COMPLETED', completed: '2026-08-18' },
  { id: '3', title: 'C', status: 'NEEDS-ACTION', completed: '2026-08-10' },
  { id: '4', title: 'D', status: 'COMPLETED', completed: '2026-08-12' }
]
const done = model.doneTasks(doneInput)
assert.equal(done.length, 3)
assert.equal(done[0].id, '2')
assert.equal(done[1].id, '1')
assert.equal(done[2].id, '4')
assert.equal(model.doneTasks(doneInput, 2).length, 2)
assert.equal(model.doneTasks(doneInput, 2)[0].id, '2')
assert.equal(model.doneTasks(doneInput, 2)[1].id, '1')
assert.equal(model.doneTasks([]).length, 0)

// doneTaskCount - total completed tasks, exceeds the doneTasks display cap
assert.equal(model.doneTaskCount(null), 0)
assert.equal(model.doneTaskCount(undefined), 0)
assert.equal(model.doneTaskCount([]), 0)
assert.equal(model.doneTaskCount(doneInput), 3)
const doneCountInput = [
  { id: '1', title: 'T1', status: 'COMPLETED', completed: '2026-08-01' },
  { id: '2', title: 'T2', status: 'COMPLETED', completed: '2026-08-02' },
  { id: '3', title: 'T3', status: 'COMPLETED', completed: '2026-08-03' },
  { id: '4', title: 'T4', status: 'COMPLETED', completed: '2026-08-04' },
  { id: '5', title: 'T5', status: 'COMPLETED', completed: '2026-08-05' },
  { id: '6', title: 'T6', status: 'COMPLETED', completed: '2026-08-06' },
  { id: '7', title: 'T7', status: 'COMPLETED', completed: '2026-08-07' },
  { id: '8', title: 'T8', status: 'COMPLETED', completed: '2026-08-08' },
  { id: '9', title: 'T9', status: 'COMPLETED', completed: '2026-08-09' },
  { id: '10', title: 'T10', status: 'COMPLETED', completed: '2026-08-10' },
  { id: '11', title: 'T11', status: 'COMPLETED', completed: '2026-08-11' },
  { id: '12', title: 'T12', status: 'COMPLETED', completed: '2026-08-12' }
]
assert.equal(model.doneTaskCount(doneCountInput), 12)
assert.equal(model.doneTasks(doneCountInput).length, 10)

// allDoneTasks - full sorted completed list, no display cap
assert.equal(model.allDoneTasks(null).length, 0)
assert.equal(model.allDoneTasks(undefined).length, 0)
assert.equal(model.allDoneTasks([]).length, 0)
assert.equal(model.allDoneTasks(doneInput).length, 3)
assert.equal(model.allDoneTasks(doneInput)[0].id, '2')
const allDone = model.allDoneTasks(doneCountInput)
assert.equal(allDone.length, 12)
assert.equal(allDone[0].id, '12')
assert.equal(allDone[11].id, '1')
assert.equal(model.doneTasks(doneCountInput).length, 10)

// parseHelperResponse
const okResponse = model.parseHelperResponse(JSON.stringify({ ok: true, provider: 'eds', calendars: [], tasks: [{ id: '1', title: 'A' }] }))
assert.equal(okResponse.ok, true)
assert.equal(okResponse.provider, 'eds')
assert.equal(okResponse.tasks.length, 1)
assert.equal(okResponse.tasks[0].id, '1')
assert.equal(okResponse.error, null)

const singularTaskResponse = model.parseHelperResponse(JSON.stringify({ ok: true, provider: 'caldav', task: { id: '9', uid: 'u9', title: 'New', status: 'NEEDS-ACTION' } }))
assert.equal(singularTaskResponse.ok, true)
assert.equal(singularTaskResponse.tasks.length, 1)
assert.equal(singularTaskResponse.tasks[0].id, '9')
assert.equal(singularTaskResponse.tasks[0].title, 'New')

const categorizedResponse = model.parseHelperResponse(JSON.stringify({ ok: true, tasks: [{ id: '1', categories: ['Work', 'Personal'] }] }))
assert.deepEqual(categorizedResponse.tasks[0].categories, ['Work', 'Personal'])

const badResponse = model.parseHelperResponse('{')
assert.equal(badResponse.ok, false)
assert.equal(badResponse.error.code, 'invalid-json')

const emptyResponse = model.parseHelperResponse('')
assert.equal(emptyResponse.ok, false)
assert.equal(emptyResponse.tasks.length, 0)

const noTasksResponse = model.parseHelperResponse(JSON.stringify({ ok: true, provider: 'local' }))
assert.equal(noTasksResponse.tasks.length, 0)
assert.equal(noTasksResponse.calendars.length, 0)

const revResponse = model.parseHelperResponse(JSON.stringify({ ok: true, provider: 'caldav', tasks: [], rev: 7 }))
assert.equal(revResponse.ok, true)
assert.equal(revResponse.rev, 7)

const noRevResponse = model.parseHelperResponse(JSON.stringify({ ok: true, provider: 'caldav', tasks: [] }))
assert.equal(noRevResponse.rev, null)

const badRevResponse = model.parseHelperResponse(JSON.stringify({ ok: true, tasks: [], rev: 'stale' }))
assert.equal(badRevResponse.rev, null)

const errorRevResponse = model.parseHelperResponse('{')
assert.equal(errorRevResponse.rev, null)

// canToggleCalendar
assert.equal(model.canToggleCalendar({ id: 'omarchy-calendar-caldav-abc' }), true)
assert.equal(model.canToggleCalendar({ id: 'omarchy-calendar-local-123' }), true)
assert.equal(model.canToggleCalendar({ id: 'c3742f32c586dbe48f75eeb0' }), false)
assert.equal(model.canToggleCalendar({ id: 'local-stub' }), false)
assert.equal(model.canToggleCalendar({}), false)
assert.equal(model.canToggleCalendar(null), false)

// parseHelperResponse carries the enabled flag for set-calendar-enabled
const toggleResponse = model.parseHelperResponse(JSON.stringify({ ok: true, provider: 'evolution-data-server', calendarId: 'c1', enabled: false }))
assert.equal(toggleResponse.ok, true)
assert.equal(toggleResponse.enabled, false)
const enableResponse = model.parseHelperResponse(JSON.stringify({ ok: true, provider: 'evolution-data-server', calendarId: 'c1', enabled: true }))
assert.equal(enableResponse.enabled, true)
const noEnabledResponse = model.parseHelperResponse(JSON.stringify({ ok: true, provider: 'eds' }))
assert.equal(noEnabledResponse.enabled, null)

// serverConnections - distinct plugin-created servers grouped by host
const serverInput = [
  { id: 'omarchy-calendar-caldav-a', host: 'Caldav.Fastmail.com' },
  { id: 'omarchy-calendar-caldav-b', host: 'www.caldav.fastmail.com' },
  { id: 'omarchy-calendar-caldav-c', host: 'caldav.icloud.com' },
  { id: 'omarchy-calendar-local-d', host: '' },
  { id: 'c3742f32c586dbe48f75eeb0', host: 'google.com' },
  null
]
const servers = model.serverConnections(serverInput)
assert.deepEqual(servers, [
  { host: 'caldav.fastmail.com', count: 2 },
  { host: 'caldav.icloud.com', count: 1 }
])
assert.equal(model.serverConnections([]).length, 0)
assert.equal(model.serverConnections(undefined).length, 0)
assert.equal(model.serverConnections(null).length, 0)
assert.equal(model.serverConnections('bad').length, 0)
assert.equal(model.serverConnections([{ id: 'omarchy-calendar-x', host: 'caldav.example.com' }]).length, 1)

// formatDueDate
assert.equal(model.formatDueDate(null), '')
assert.equal(model.formatDueDate({}), '')
assert.equal(model.formatDueDate({ due: 'bad-date' }), '')
assert.equal(model.formatDueDate({ due: '2026-08-20T12:00:00Z' }), 'Aug 20')
assert.equal(model.formatDueDate({ due: '2025-12-25T12:00:00Z' }), 'Dec 25, 2025')
assert.equal(model.formatDueDate({ due: '2027-01-01T12:00:00Z' }), 'Jan 1, 2027')

// formatCompletedDate
assert.equal(model.formatCompletedDate(null), '')
assert.equal(model.formatCompletedDate({}), '')
assert.equal(model.formatCompletedDate({ completed: 'bad-date' }), '')
assert.equal(model.formatCompletedDate({ completed: '2026-08-18T12:00:00Z' }), 'Aug 18')
assert.equal(model.formatCompletedDate({ completed: '2025-06-01T12:00:00Z' }), 'Jun 1, 2025')

// colorsMatch - case-insensitive, non-empty comparison of two color strings
assert.equal(model.colorsMatch('#8AADF4', '#8aadf4'), true)
assert.equal(model.colorsMatch('', '#fff'), false)
assert.equal(model.colorsMatch('#fff', ''), false)
assert.equal(model.colorsMatch(undefined, undefined), false)
assert.equal(model.colorsMatch('#a6e3a1', '#a6e3a1'), true)
assert.equal(model.colorsMatch(' #a6e3a1 ', '#a6e3a1'), true)
assert.equal(model.colorsMatch('#8aadf4', '#a6e3a1'), false)

// calendarDisplayColor - settings override beats calendar.color beats palette
assert.equal(model.calendarDisplayColor({ id: 'c1', color: '#111111' }, { c1: '#222222' }), '#222222')
assert.equal(model.calendarDisplayColor({ id: 'c1', color: '#111111' }, {}), '#111111')
assert.equal(model.calendarDisplayColor({ id: 'c1' }, {}, 0), '#8aadf4')
assert.equal(model.calendarDisplayColor({ id: 'c1' }, {}, 3), '#f38ba8')
assert.equal(model.calendarDisplayColor({ id: 'c1' }, {}, 12), '#f9e2af')
assert.equal(model.calendarDisplayColor(null, {}, 5), '#8aadf4')
assert.equal(model.calendarDisplayColor({ id: 'c1' }, {}, -1), '#a6e3a1')

console.log('ok - task model')
