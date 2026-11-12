import QtQuick
import Quickshell
import Quickshell.Io
import "TaskModel.js" as TaskModel

Item {
  id: root

  property var shell: null
  property string provider: "evolution-data-server"
  property var calendars: []
  property var cachedCalendars: []
  readonly property int maxHelperBytes: 8 * 1024 * 1024
  readonly property int maxHelperErrorBytes: 64 * 1024
  property bool debugMode: false
  property var debugLogLines: []
  property string debugLogText: ""
  property int debugLogRevision: 0
  readonly property int maxDebugLogLines: 400

  // Tasks properties
  property string calendarId: ""
  property var allTasks: []
  property var pendingTasks: []
  property var doneTasks: []
  property var cachedTasks: []
  property string tasksStatus: "idle"
  property string tasksErrorMessage: ""
  property bool tasksSyncing: false
  property date tasksLastSyncAt: new Date(NaN)
  property string tasksLastSyncText: "Never synced"
  property int tasksGeneration: 0
  property int tasksLiveToken: 0
  property int tasksCacheRev: 0
  property bool tasksIgnoreCache: false
  property bool tasksSyncedOnce: false
  property bool tasksRerunRequested: false
  property int tasksSyncCompletions: 0
  property int tasksCacheStartSyncs: 0
  // Optimistic creates: FIFO of { seq, pendingId, optimistic, secret, command }.
  property var createQueue: []
  property int createSeq: 0
  property int createActiveSeq: 0
  readonly property string calendarCacheDir: {
    var override = String(Quickshell.env("OMARCHY_CALENDAR_CACHE") || "")
    if (override !== "") return override
    var home = String(Quickshell.env("HOME") || "")
    return home !== "" ? home + "/.local/share/omarchy-calendar" : ""
  }
  property var tasksPendingUpdateOriginal: null
  property string pendingDeleteUid: ""
  property string moduleName: "dev.enkeli.omarchy-dav-tasks"

  // Calendar enable/disable properties
  property string pendingToggleId: ""
  property string toggleError: ""

  // Calendar color properties
  property string pendingColorId: ""
  property string colorError: ""

  // CalDAV setup properties
  property string caldavSetupStatus: "idle"
  property string caldavSetupMessage: ""

  // Debug: log when allTasks changes
  onAllTasksChanged: {
    debugLog("allTasks changed: " + (allTasks ? allTasks.length : 0))
  }

  signal refreshed()
  signal taskCreated(var task)
  signal taskUpdated(var task)
  signal taskDeleted(string uid)
  signal taskCreateFailed(string reason)

  function plainDisplay(value, maxLen) {
    var text = String(value == null ? '' : value)
    text = text.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
    text = text.replace(/<[^>]*>/g, '')
    var limit = maxLen || 400
    if (text.length > limit) text = text.slice(0, limit)
    return text
  }

  function helperPath() {
    return decodeURIComponent(Qt.resolvedUrl("helper/omarchy-calendar-helper").toString().replace(/^file:\/\//, ""))
  }

  function debugLog(message) {
    if (!debugMode) return
    var line = "[" + new Date().toTimeString().slice(0, 8) + "] " + message
    debugLogLines.push(line)
    if (debugLogLines.length > maxDebugLogLines) debugLogLines.splice(0, debugLogLines.length - maxDebugLogLines)
    debugLogText = debugLogLines.join("\n")
    debugLogRevision++
    console.log("[Service]", message)
  }

  function clearDebugLog() {
    debugLogLines = []
    debugLogText = ""
    debugLogRevision++
  }

  function sanitizeUrl(url) {
    return String(url).replace(/^(\w+:\/\/)[^@\/]*@/, "$1")
  }

  function failMessage(payload, fallback) {
    return plainDisplay((payload && payload.error && payload.error.message) || fallback || "Calendar helper failed", 400)
  }

  function calendarById(id) {
    var wanted = String(id || "")
    var lists = [cachedCalendars, calendars]
    for (var l = 0; l < lists.length; l++) {
      var list = lists[l] || []
      for (var i = 0; i < list.length; i++) {
        var calendar = list[i]
        if (calendar && String(calendar.id || "") === wanted) return calendar
      }
    }
    return null
  }

  function calendarProviderById(id) {
    var calendar = calendarById(id)
    return calendar && calendar.provider ? String(calendar.provider) : provider
  }

  function cleanHelperErrorText(text, fallback) {
    var raw = String(text || "")
    var usage = raw.match(/^usage:[\s\S]*?\n\s*\n/)
    if (usage) raw = raw.slice(usage[0].length)
    raw = raw.replace(/\s*\n+\s*/g, " ").trim()
    return plainDisplay(raw, 400) || fallback
  }

  function helperText(out, err) {
    var text = String(out || "")
    if (text.length > maxHelperBytes)
      return JSON.stringify({ ok: false, error: { message: "Calendar response was too large." } })
    if (text)
      return text
    var e = String(err || "").trim()
    if (e.length > maxHelperErrorBytes)
      e = e.slice(0, maxHelperErrorBytes)
    if (!e)
      return ""
    return JSON.stringify({ ok: false, error: { message: plainDisplay(e, 400) } })
  }

  // ===== Tasks =====

  function tasksMutationBusy() {
    return tasksCreateProc.running || tasksUpdateProc.running || tasksEditProc.running || tasksDeleteProc.running
  }

  function listTasks(forceSync) {
    debugLog("action: list-tasks" + (forceSync ? " (force)" : ""))
    debugLog("listTasks called, cachedTasks.length: " + cachedTasks.length + " forceSync: " + forceSync)
    tasksGeneration += 1
    tasksErrorMessage = ""
    // The disk cache is read in-process by FileView, so there is no helper
    // spawn in front of the list.
    readTasksCache()
    var stale = !isNaN(tasksLastSyncAt.getTime()) && (Date.now() - tasksLastSyncAt.getTime() > 15 * 60 * 1000)
    // The first open after shell start always syncs once, even with a warm
    // cache, so the cached view is not left stale.
    var shouldSync = forceSync === true || !tasksSyncedOnce || cachedTasks.length === 0 || stale
    debugLog("shouldSync: " + shouldSync + " stale: " + stale)
    if (shouldSync) startTasksLiveSync(false)
  }

  function startTasksLiveSync(ifChanged) {
    debugLog("startTasksLiveSync ifChanged: " + ifChanged)
    if (tasksListProc.running) {
      // The fetch in flight may predate a change that just landed, so it is
      // discarded on arrival and one fresh fetch runs after it.
      debugLog("startTasksLiveSync - already running, queueing a rerun")
      tasksRerunRequested = true
      return
    }
    tasksLiveToken += 1
    tasksListProc.token = tasksLiveToken
    if (cachedTasks.length === 0 && ifChanged !== true) tasksStatus = "loading"
    tasksSyncing = true
    listTasksTimeout.restart()
    var cmd = [helperPath(), "list-tasks", "--provider", provider]
    if (calendarId) cmd.push("--calendar-id", calendarId)
    debugLog("startTasksLiveSync command: " + cmd)
    tasksListProc.command = cmd
    tasksListProc.running = true
  }

  function applyTaskCache(tasks, cals) {
    var list = withInflightCreates(tasks || [])
    debugLog("applyTaskCache tasks: " + list.length + " cals: " + (cals ? cals.length : 0))
    root.cachedTasks = list
    if (cals && cals.length > 0) {
      root.cachedCalendars = cals
      root.calendars = root.cachedCalendars
    }
    root.allTasks = list
    root.pendingTasks = list.filter(function(task) { return TaskModel.isPending(task) })
    root.doneTasks = list.filter(function(task) { return TaskModel.isCompleted(task) })
    debugLog("applyTaskCache result - allTasks: " + root.allTasks.length + " pending: " + root.pendingTasks.length + " done: " + root.doneTasks.length)
    root.tasksStatus = "ready"
    root.tasksErrorMessage = ""
    if (root.tasksSyncing) {
      root.tasksLastSyncAt = new Date()
      root.tasksLastSyncText = Qt.formatDateTime(root.tasksLastSyncAt, "MMM d HH:mm")
    } else if (isNaN(root.tasksLastSyncAt.getTime())) {
      root.tasksLastSyncText = "Cached"
    }
  }

  // Optimistic creates that are still queued or running stay visible across
  // any list refresh that lands while they are in flight.
  function withInflightCreates(tasks) {
    if (createQueue.length === 0) return tasks
    var out = tasks.slice()
    var seen = {}
    for (var i = 0; i < out.length; i++) if (out[i]) seen[out[i].id] = true
    for (var j = 0; j < createQueue.length; j++) {
      var optimistic = createQueue[j].optimistic
      if (!seen[optimistic.id]) out.push(optimistic)
    }
    return out
  }

  function readTasksCache() {
    if (tasksMutationBusy()) {
      debugLog("readTasksCache skipped - mutating")
      return
    }
    debugLog("readTasksCache starting")
    tasksCacheStartSyncs = tasksSyncCompletions
    tasksCacheFile.reload()
  }

  function writeCache() {
    if (tasksWriteCacheProc.running) {
      debugLog("writeCache skipped - already running")
      return
    }
    debugLog("writeCache - tasks: " + cachedTasks.length)
    tasksWriteCacheProc.secret = JSON.stringify({
      tasks: cachedTasks,
      calendars: cachedCalendars,
      rev: root.tasksCacheRev
    })
    tasksWriteCacheProc.command = [helperPath(), "tasks-save-cache", "--provider", provider]
    tasksWriteCacheProc.running = true
  }

  function finishListCache(text, exitCode) {
    debugLog("finishListCache exitCode: " + exitCode + " text length: " + (text ? text.length : 0))
    if (tasksIgnoreCache || tasksMutationBusy()) {
      debugLog("finishListCache skipped - ignoreCache or mutating")
      return
    }
    // A sync that finished after this read started is newer than the disk
    // copy; applying the disk copy would roll the list back.
    if (tasksCacheStartSyncs !== tasksSyncCompletions) {
      debugLog("finishListCache skipped - a sync completed meanwhile")
      return
    }
    var payload = TaskModel.parseHelperResponse(text)
    debugLog("finishListCache payload.ok: " + payload.ok + " tasks: " + (payload.tasks ? payload.tasks.length : 0))
    if (exitCode === 0 && payload.ok) {
      if (typeof payload.rev === "number") root.tasksCacheRev = payload.rev
      applyTaskCache(payload.tasks, payload.calendars)
    }
  }

  function finishListTasks(text, exitCode) {
    debugLog("finishListTasks exitCode: " + exitCode + " text length: " + (text ? text.length : 0))
    listTasksTimeout.stop()
    tasksSyncing = false
    var payload = TaskModel.parseHelperResponse(text)
    debugLog("finishListTasks payload.ok: " + payload.ok + " tasks: " + (payload.tasks ? payload.tasks.length : 0))
    if (exitCode === 0 && payload.ok) {
      tasksIgnoreCache = false
      tasksSyncedOnce = true
      tasksSyncCompletions += 1
      applyTaskCache(payload.tasks, payload.calendars)
      writeCache()
    } else if (cachedTasks.length === 0) {
      root.tasksStatus = "error"
      root.tasksErrorMessage = root.failMessage(payload, "Task helper failed")
      root.refreshed()
    }
  }

  // The new task appears in the list at once. Creates run through a FIFO
  // queue (one helper process at a time), so rapid submits never cancel each
  // other and each keeps its own pending entry until the helper confirms it.
  function createTask(calendarIdArg, title, due, priority, description, categories, dtstart) {
    debugLog("action: create-task calendar=" + calendarIdArg + " title=" + title)
    var targetCalendar = String(calendarIdArg || calendarId || defaultCalendarId())
    tasksErrorMessage = ""
    createSeq += 1
    var pendingId = "omarchy-task-pending-" + createSeq + "-" + Date.now()
    var optimistic = TaskModel.normalizedTask({
      id: pendingId,
      uid: pendingId,
      title: title,
      due: due || "",
      start: dtstart || "",
      status: "NEEDS-ACTION",
      priority: priority || "",
      description: description || "",
      categories: Array.isArray(categories) ? categories : [],
      calendarId: targetCalendar,
      calendarName: calendarNameById(targetCalendar)
    })
    optimistic._pending = true
    // Task content is private: it travels on the helper's stdin (written by
    // tasksCreateProc.onStarted) so titles, dates, descriptions, and
    // categories never appear in /proc/<pid>/cmdline or process listings.
    var secret = JSON.stringify({
      title: String(title || "(No title)"),
      due: String(due || ""),
      dtstart: String(dtstart || ""),
      priority: (priority !== undefined && priority !== null && String(priority) !== "") ? String(priority) : null,
      description: description ? String(description) : "",
      categories: Array.isArray(categories) ? categories.map(function(category) { return String(category) }) : []
    })
    createQueue = createQueue.concat([{
      seq: createSeq,
      pendingId: pendingId,
      optimistic: optimistic,
      secret: secret,
      command: [
        helperPath(), "create-task",
        "--provider", calendarProviderById(targetCalendar),
        "--calendar-id", targetCalendar
      ]
    }])
    applyTaskCache(cachedTasks, cachedCalendars)
    tasksStatus = "adding"
    if (!tasksCreateProc.running) startNextCreate()
  }

  function startNextCreate() {
    if (createQueue.length === 0) return
    var job = createQueue[0]
    createActiveSeq = job.seq
    tasksStatus = "adding"
    tasksCreateProc.token = job.seq
    tasksCreateProc.secret = job.secret
    job.secret = ""
    tasksCreateProc.command = job.command
    // onStarted closes stdin after writing, so re-open it for every run.
    tasksCreateProc.stdinEnabled = true
    createTimeout.restart()
    tasksCreateProc.running = true
  }

  function finishCreateTask(text, exitCode) {
    createTimeout.stop()
    var job = createQueue.length > 0 ? createQueue[0] : null
    createQueue = createQueue.slice(1)
    createActiveSeq = 0
    var pendingId = job ? job.pendingId : ""
    var payload = TaskModel.parseHelperResponse(text)
    if (exitCode === 0 && payload.ok) {
      removePendingTask(pendingId)
      var created = payload.tasks && payload.tasks.length > 0 ? payload.tasks[0] : null
      if (created) mergeTask(created)
      root.taskCreated(created || {})
      root.tasksErrorMessage = ""
      if (createQueue.length === 0) {
        root.tasksStatus = "added"
        taskAddedTimer.restart()
      }
    } else {
      removePendingTask(pendingId)
      root.tasksStatus = "error"
      root.tasksErrorMessage = root.failMessage(payload, "Could not create task.")
      root.taskCreateFailed(root.cleanHelperErrorText((payload && payload.error && payload.error.message) || "", "Could not create task."))
    }
    if (createQueue.length > 0) {
      startNextCreate()
    } else {
      root.startTasksLiveSync(true)
    }
  }

  function updateTask(task, statusArg, percentComplete) {
    debugLog("action: update-task uid=" + (task ? task.uid : "") + " status=" + statusArg + " percent=" + percentComplete)
    if (!task || !task.uid || task._pending) return
    tasksStatus = "saving"
    tasksErrorMessage = ""
    if (tasksUpdateProc.running) tasksUpdateProc.running = false
    tasksPendingUpdateOriginal = task
    var next = TaskModel.normalizedTask(task)
    next.status = statusArg || task.status
    next._pending = true
    mergeTask(next)
    var cmd = [
      helperPath(), "update-task",
      "--provider", calendarProviderById(task.calendarId),
      "--calendar-id", String(task.calendarId || defaultCalendarId()),
      "--uid", String(task.uid || ""),
      "--status", String(statusArg || task.status || "NEEDS-ACTION")
    ]
    if (percentComplete !== undefined && percentComplete !== null) {
      cmd.push("--percent-complete", String(percentComplete))
    }
    tasksUpdateProc.command = cmd
    tasksUpdateProc.running = true
  }

  // Edit title, description, due date (YYYY-MM-DD, "" clears) and categories
  // of an existing task. `fields` carries only what changed. Content travels
  // on the helper's stdin like create-task, never in argv.
  function editTask(task, fields) {
    debugLog("action: edit-task uid=" + (task ? task.uid : "") + " fields=" + Object.keys(fields || {}).join(","))
    if (!task || !task.uid || task._pending || !fields) return false
    tasksStatus = "saving"
    tasksErrorMessage = ""
    if (tasksEditProc.running) tasksEditProc.running = false
    tasksPendingUpdateOriginal = task
    var next = TaskModel.normalizedTask(task)
    var payload = {}
    if (fields.title !== undefined) { payload.title = String(fields.title); next.title = payload.title }
    if (fields.description !== undefined) { payload.description = String(fields.description); next.description = payload.description }
    if (fields.due !== undefined) { payload.due = String(fields.due); next.due = payload.due }
    if (fields.dtstart !== undefined) { payload.dtstart = String(fields.dtstart); next.start = payload.dtstart }
    if (fields.categories !== undefined) {
      payload.categories = Array.isArray(fields.categories) ? fields.categories.map(function(category) { return String(category) }) : []
      next.categories = payload.categories.slice()
    }
    next._pending = true
    mergeTask(next)
    tasksEditProc.secret = JSON.stringify(payload)
    // onStarted closes stdin after writing, so re-open it for every run.
    tasksEditProc.stdinEnabled = true
    // A calendar change is sent as --to-calendar-id; the helper copies the task
    // there and deletes the original.
    var toCalendarId = fields.calendarId !== undefined ? String(fields.calendarId) : ""
    tasksEditProc.command = [
      helperPath(), "edit-task",
      "--provider", calendarProviderById(task.calendarId),
      "--calendar-id", String(task.calendarId || defaultCalendarId()),
      "--to-calendar-id", toCalendarId,
      "--uid", String(task.uid || "")
    ]
    tasksEditProc.running = true
    return true
  }

  function finishUpdateTask(text, exitCode) {
    var payload = TaskModel.parseHelperResponse(text)
    if (exitCode === 0 && payload.ok) {
      if (payload.tasks && payload.tasks.length > 0) {
        // A move gives the task a new UID: drop the original entry first.
        var original = root.tasksPendingUpdateOriginal
        if (original && original.uid !== payload.tasks[0].uid) removeTaskByUid(original.uid)
        mergeTask(payload.tasks[0])
        root.taskUpdated(payload.tasks[0])
      }
      root.tasksStatus = "ready"
      root.tasksErrorMessage = ""
      root.startTasksLiveSync(true)
    } else {
      if (root.tasksPendingUpdateOriginal) mergeTask(root.tasksPendingUpdateOriginal)
      root.tasksStatus = "error"
      root.tasksErrorMessage = root.failMessage(payload, "Could not update task.")
    }
    root.tasksPendingUpdateOriginal = null
  }

  function completeTask(task) {
    debugLog("action: complete-task uid=" + (task ? task.uid : "") + " title=" + (task ? task.title : ""))
    updateTask(task, "COMPLETED", 100)
  }

  function deleteTask(task) {
    debugLog("action: delete-task uid=" + (task ? task.uid : "") + " title=" + (task ? task.title : ""))
    if (!task || !task.uid || task._pending) return
    tasksStatus = "saving"
    tasksErrorMessage = ""
    if (tasksDeleteProc.running) tasksDeleteProc.running = false
    pendingDeleteUid = task.uid
    removeTaskByUid(task.uid)
    tasksDeleteProc.command = [
      helperPath(), "delete-task",
      "--provider", calendarProviderById(task.calendarId),
      "--calendar-id", String(task.calendarId || defaultCalendarId()),
      "--uid", String(task.uid || "")
    ]
    tasksDeleteProc.running = true
  }

  function finishDeleteTask(text, exitCode) {
    if (exitCode !== 0) {
      var payload = TaskModel.parseHelperResponse(root.helperText(text, ""))
      root.tasksStatus = "error"
      root.tasksErrorMessage = root.failMessage(payload, "Could not delete task.")
      root.startTasksLiveSync(true)
    } else {
      root.taskDeleted(root.pendingDeleteUid)
      root.tasksStatus = "ready"
      root.tasksErrorMessage = ""
      root.startTasksLiveSync(true)
    }
    root.pendingDeleteUid = ""
  }

  function mergeTask(task) {
    if (!task || !task.id) return
    var next = []
    var replaced = false
    var source = cachedTasks.length ? cachedTasks : allTasks
    for (var i = 0; i < source.length; i++) {
      if (source[i] && source[i].id === task.id) {
        next.push(task)
        replaced = true
      } else {
        next.push(source[i])
      }
    }
    if (!replaced) next.push(task)
    applyTaskCache(TaskModel.normalizeTasks(next), cachedCalendars)
  }

  function removeTaskByUid(uid) {
    if (!uid) return
    var next = []
    var source = cachedTasks.length ? cachedTasks : allTasks
    for (var i = 0; i < source.length; i++) {
      if (!source[i] || source[i].uid !== uid) next.push(source[i])
    }
    applyTaskCache(TaskModel.normalizeTasks(next), cachedCalendars)
  }

  function removePendingTask(prefix) {
    if (!prefix) return
    var next = []
    var source = cachedTasks.length ? cachedTasks : allTasks
    for (var i = 0; i < source.length; i++) {
      if (!source[i] || String(source[i].id || "").indexOf(prefix) !== 0) next.push(source[i])
    }
    applyTaskCache(TaskModel.normalizeTasks(next), cachedCalendars)
  }

  function defaultCalendarId() {
    for (var i = 0; i < calendars.length; i++) {
      if (calendars[i] && calendars[i].id) return calendars[i].id
    }
    return calendarId || ""
  }

  function calendarNameById(id) {
    for (var i = 0; i < calendars.length; i++) {
      if (calendars[i] && calendars[i].id === id) return calendars[i].name || "Calendar"
    }
    return "Calendar"
  }

  // ===== Calendar Enable/Disable =====

  function setCalendarEnabled(calendarId, enabled) {
    debugLog("action: set-calendar-enabled id=" + calendarId + " enabled=" + enabled)
    var id = String(calendarId || "")
    if (!id || calendarToggleProc.running || pendingToggleId) return
    pendingToggleId = id
    toggleError = ""
    calendarToggleProc.command = [helperPath(), "set-calendar-enabled", "--provider", provider, "--calendar-id", id, "--enabled", enabled ? "true" : "false"]
    calendarToggleProc.running = true
  }

  function finishSetCalendarEnabled(text, exitCode) {
    var payload = TaskModel.parseHelperResponse(text)
    if (exitCode === 0 && payload.ok) {
      var id = pendingToggleId
      var enabled = !!payload.enabled
      var mapCalendars = function(cal) {
        return cal && cal.id === id ? Object.assign({}, cal, { enabled: enabled }) : cal
      }
      root.cachedCalendars = cachedCalendars.map(mapCalendars)
      root.calendars = root.cachedCalendars
      pendingToggleId = ""
      toggleError = ""
      listTasks(true)
    } else {
      toggleError = failMessage(payload, "Could not update calendar.")
      pendingToggleId = ""
    }
  }

  function setCalendarColor(calendarId, colorHex) {
    debugLog("action: set-calendar-color id=" + calendarId + " color=" + colorHex)
    var id = String(calendarId || "")
    if (!id || !colorHex || calendarColorProc.running || pendingColorId) return
    var cal = null
    for (var i = 0; i < calendars.length; i++) {
      if (calendars[i] && calendars[i].id === id) { cal = calendars[i]; break }
    }
    if (!cal) {
      colorError = "Calendar not found."
      return
    }
    pendingColorId = id
    colorError = ""
    calendarColorProc.secret = JSON.stringify({ calendars: [{ id: id, name: cal.name || "", color: String(colorHex) }] })
    calendarColorProc.command = [helperPath(), "update-calendars", "--provider", provider]
    calendarColorProc.running = true
  }

  function finishSetCalendarColor(text, exitCode) {
    var payload = TaskModel.parseHelperResponse(text)
    if (exitCode === 0 && payload.ok) {
      var id = pendingColorId
      var color = ""
      // Tolerate an ok payload without a calendars echo: skip the patch and
      // still finish cleanly instead of throwing with pendingColorId set.
      var payloadCalendars = payload.calendars || []
      for (var i = 0; i < payloadCalendars.length; i++) {
        if (payload.calendars[i] && payload.calendars[i].id === id) {
          color = String(payload.calendars[i].color || "")
          break
        }
      }
      if (color) {
        var mapCalendars = function(cal) {
          return cal && cal.id === id ? Object.assign({}, cal, { color: color }) : cal
        }
        root.cachedCalendars = cachedCalendars.map(mapCalendars)
        root.calendars = root.cachedCalendars
      }
      pendingColorId = ""
      colorError = ""
      listTasks(true)
    } else {
      colorError = failMessage(payload, "Could not update calendar color.")
      pendingColorId = ""
    }
  }

  // ===== CalDAV Setup =====

  function setupCaldav(displayName, url, username, password) {
    debugLog("action: setup-caldav url=" + sanitizeUrl(url))
    caldavSetupStatus = "connecting"
    caldavSetupMessage = ""
    caldavSetupProc.secret = JSON.stringify({
      "displayName": displayName,
      "url": url,
      "username": username,
      "password": password
    })
    caldavSetupProc.command = [helperPath(), "setup-caldav", "--provider", provider]
    setupTimeout.restart()
    caldavSetupProc.running = true
  }

  function finishSetupCaldav(text, exitCode) {
    setupTimeout.stop()
    var payload = TaskModel.parseHelperResponse(text)
    if (exitCode === 0 && payload.ok) {
      caldavSetupStatus = "success"
      caldavSetupMessage = ""
      listCalendars()
      listTasks(true)
    } else {
      caldavSetupStatus = "error"
      caldavSetupMessage = failMessage(payload)
    }
    debugLog("action: setup-caldav finished: " + caldavSetupStatus)
  }

  // Reset setup state after the UI has acknowledged a finished attempt so the
  // next run of the connect form starts clean instead of replaying the old
  // status message.
  function resetCaldavSetup() {
    caldavSetupStatus = "idle"
    caldavSetupMessage = ""
  }

  // ===== Task Processes =====

  Process {
    id: tasksListProc
    property int token: 0
    running: false

    stdout: StdioCollector { id: tasksListOut; waitForEnd: true }
    stderr: StdioCollector { id: tasksListErr; waitForEnd: true }

    onExited: function(exitCode) {
      debugLog("tasksListProc exited with code: " + exitCode)
      if (token !== root.tasksLiveToken) {
        debugLog("tasksListProc token mismatch, ignoring")
        root.tasksSyncing = false
        root.listTasksTimeout.stop()
        return
      }
      if (root.tasksRerunRequested) {
        // A change landed while this fetch ran: its result may predate it.
        root.tasksRerunRequested = false
        root.startTasksLiveSync(false)
        return
      }
      root.finishListTasks(root.helperText(tasksListOut.text, tasksListErr.text), exitCode)
    }
  }

  // The tasks cache is read in-process: no helper spawn before the list shows.
  FileView {
    id: tasksCacheFile
    path: root.calendarCacheDir !== "" ? root.calendarCacheDir + "/tasks-cache.json" : ""
    printErrors: false
    onLoaded: root.finishListCache(text(), 0)
    onLoadFailed: function(error) { root.finishListCache("", 1) }
  }

  Process {
    id: tasksWriteCacheProc
    property string secret: ""
    running: false
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
      stdinEnabled = false
    }

    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: caldavSetupProc
    property string secret: ""
    running: false
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
      stdinEnabled = false
    }
    stdout: StdioCollector { id: caldavSetupOut; waitForEnd: true }
    stderr: StdioCollector { id: caldavSetupErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.finishSetupCaldav(root.helperText(caldavSetupOut.text, caldavSetupErr.text), exitCode)
    }
  }

  Process {
    id: tasksCreateProc
    property string secret: ""
    property int token: 0
    running: false
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
      stdinEnabled = false
    }

    stdout: StdioCollector { id: tasksCreateOut; waitForEnd: true }
    stderr: StdioCollector { id: tasksCreateErr; waitForEnd: true }

    onExited: function(exitCode) {
      // Ignore exits from a job that already timed out and was dropped.
      if (token !== root.createActiveSeq) return
      root.finishCreateTask(root.helperText(tasksCreateOut.text, tasksCreateErr.text), exitCode)
    }
  }

  Process {
    id: tasksUpdateProc
    running: false

    stdout: StdioCollector { id: tasksUpdateOut; waitForEnd: true }
    stderr: StdioCollector { id: tasksUpdateErr; waitForEnd: true }

    onExited: function(exitCode) {
      root.finishUpdateTask(root.helperText(tasksUpdateOut.text, tasksUpdateErr.text), exitCode)
    }
  }

  Process {
    id: tasksEditProc
    property string secret: ""
    running: false
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
      stdinEnabled = false
    }

    stdout: StdioCollector { id: tasksEditOut; waitForEnd: true }
    stderr: StdioCollector { id: tasksEditErr; waitForEnd: true }

    onExited: function(exitCode) {
      root.finishUpdateTask(root.helperText(tasksEditOut.text, tasksEditErr.text), exitCode)
    }
  }

  Process {
    id: tasksDeleteProc
    running: false

    stdout: StdioCollector { id: tasksDeleteOut; waitForEnd: true }
    stderr: StdioCollector { id: tasksDeleteErr; waitForEnd: true }

    onExited: function(exitCode) {
      root.finishDeleteTask(root.helperText(tasksDeleteOut.text, tasksDeleteErr.text), exitCode)
    }
  }

  Process {
    id: calendarToggleProc
    running: false

    stdout: StdioCollector { id: toggleOut; waitForEnd: true }
    stderr: StdioCollector { id: toggleErr; waitForEnd: true }

    onExited: function(exitCode) {
      root.finishSetCalendarEnabled(root.helperText(toggleOut.text, toggleErr.text), exitCode)
    }
  }

  Process {
    id: calendarColorProc
    property string secret: ""
    running: false
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
      stdinEnabled = false
    }
    stdout: StdioCollector { id: calendarColorOut; waitForEnd: true }
    stderr: StdioCollector { id: calendarColorErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.finishSetCalendarColor(root.helperText(calendarColorOut.text, calendarColorErr.text), exitCode)
    }
  }

  // ===== List Calendars =====

  function listCalendars() {
    debugLog("action: list-calendars")
    if (listCalendarsProc.running) return
    listCalendarsProc.command = [helperPath(), "list-calendars", "--provider", provider]
    listCalendarsProc.running = true
  }

  function finishListCalendars(text, exitCode) {
    var payload = TaskModel.parseHelperResponse(text)
    if (exitCode === 0 && payload.ok) {
      root.calendars = payload.calendars || []
      root.cachedCalendars = payload.calendars || []
    } else {
      debugLog("listCalendars failed: " + failMessage(payload, "Failed to list calendars"))
    }
  }

  Process {
    id: listCalendarsProc
    running: false

    stdout: StdioCollector { id: listCalendarsOut; waitForEnd: true }
    stderr: StdioCollector { id: listCalendarsErr; waitForEnd: true }

    onExited: function(exitCode) {
      root.finishListCalendars(root.helperText(listCalendarsOut.text, listCalendarsErr.text), exitCode)
    }
  }

  Timer {
    id: listTasksTimeout
    interval: 60000
    repeat: false
    onTriggered: {
      if (!tasksListProc.running) return
      tasksListProc.running = false
      root.tasksSyncing = false
      if (root.cachedTasks.length === 0) {
        root.tasksStatus = "error"
        root.tasksErrorMessage = "Task sync timed out. Try again."
      } else {
        root.tasksStatus = "ready"
      }
      root.refreshed()
    }
  }

  // Success flash for task creation: hold "added" long enough for the panel
  // banner to display it, then fall back to the normal ready state. Guarded
  // so an intervening status change (e.g. a finished live sync) is not
  // reverted on top of.
  Timer {
    id: taskAddedTimer
    interval: 2000
    repeat: false
    onTriggered: if (root.tasksStatus === "added") root.tasksStatus = "ready"
  }

  // A hung create helper must not block the queue forever.
  Timer {
    id: createTimeout
    interval: 60000
    repeat: false
    onTriggered: {
      if (!tasksCreateProc.running) return
      debugLog("create-task timed out")
      root.createActiveSeq = 0
      tasksCreateProc.running = false
      root.finishCreateTask(JSON.stringify({ ok: false, error: { message: "Create timed out. Try again." } }), 1)
    }
  }

  Timer {
    id: setupTimeout
    interval: 30000
    running: false
    repeat: false
    onTriggered: {
      if (caldavSetupProc.running) caldavSetupProc.running = false
      caldavSetupStatus = "error"
      caldavSetupMessage = "Setup timed out"
      debugLog("setup-caldav timed out")
    }
  }

  Process {
    id: rightAnchorProc
    running: false
    stdout: StdioCollector { id: rightAnchorOut; waitForEnd: true }
    stderr: StdioCollector { id: rightAnchorErr; waitForEnd: true }
    onStarted: if (debugMode) console.log("[tasks-widget] ensure-right-anchor started", command)
    onExited: function(exitCode) {
      if (debugMode) console.log("[tasks-widget] ensure-right-anchor exited", exitCode,
        "stdout=", rightAnchorOut.text,
        "stderr=", rightAnchorErr.text)
    }
  }

  function ensureRightAnchor() {
    if (debugMode) console.log("[tasks-widget] ensureRightAnchor helper=", helperPath(), "running=", rightAnchorProc.running)
    if (!rightAnchorProc.running) {
      rightAnchorProc.command = [helperPath(), "ensure-right-anchor", "--title", root.moduleName]
      rightAnchorProc.running = true
    }
  }

  Component.onCompleted: {
    if (debugMode) console.log("[tasks-widget] Service.onCompleted moduleName=", root.moduleName)
    listCalendars()
    Qt.callLater(ensureRightAnchor)
  }
}
