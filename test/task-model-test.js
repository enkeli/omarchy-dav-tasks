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

console.log('ok - task model')
