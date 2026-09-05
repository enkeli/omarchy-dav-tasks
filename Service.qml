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
  property int tasksCacheToken: 0
  property bool tasksIgnoreCache: false
  property string tasksPendingCreateId: ""
  property var tasksPendingUpdateOriginal: null
  property string pendingDeleteUid: ""
  property string moduleName: "dev.enkeli.omarchy-dav-tasks"

  // Calendar removal properties
  property string pendingRemoveId: ""
  property string removeError: ""

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
    console.log("[Service]", message)
  }

  function sanitizeUrl(url) {
    return String(url).replace(/^(\w+:\/\/)[^@\/]*@/, "$1")
  }

  function failMessage(payload, fallback) {
    return plainDisplay((payload && payload.error && payload.error.message) || fallback || "Calendar helper failed", 400)
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
    return tasksCreateProc.running || tasksUpdateProc.running || tasksDeleteProc.running
  }

  function listTasks(forceSync) {
    debugLog("action: list-tasks" + (forceSync ? " (force)" : ""))
    debugLog("listTasks called, cachedTasks.length: " + cachedTasks.length + " forceSync: " + forceSync)
    tasksGeneration += 1
    tasksErrorMessage = ""
    if (cachedTasks.length > 0) {
      debugLog("applying cached tasks: " + cachedTasks.length)
      applyTaskCache(cachedTasks, cachedCalendars)
      tasksStatus = "ready"
    }
    readTasksCache()
    var stale = !isNaN(tasksLastSyncAt.getTime()) && (Date.now() - tasksLastSyncAt.getTime() > 15 * 60 * 1000)
    var shouldSync = forceSync === true || (cachedTasks.length === 0 && !tasksListProc.running) || stale
    debugLog("shouldSync: " + shouldSync + " stale: " + stale)
    if (shouldSync) startTasksLiveSync(false)
  }

  function startTasksLiveSync(ifChanged) {
    debugLog("startTasksLiveSync ifChanged: " + ifChanged)
    if (tasksListProc.running) {
      debugLog("startTasksLiveSync - already running, incrementing token")
      tasksLiveToken += 1
      tasksListProc.token = -1
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
    debugLog("applyTaskCache tasks: " + (tasks ? tasks.length : 0) + " cals: " + (cals ? cals.length : 0))
    root.cachedTasks = tasks
    if (cals && cals.length > 0) {
      root.cachedCalendars = cals
      root.calendars = root.cachedCalendars
    }
    root.allTasks = tasks
    root.pendingTasks = tasks.filter(function(task) { return TaskModel.isPending(task) })
    root.doneTasks = tasks.filter(function(task) { return TaskModel.isCompleted(task) })
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

  function readTasksCache() {
    if (tasksCacheProc.running || tasksMutationBusy()) {
      debugLog("readTasksCache skipped - already running or mutating")
      return
    }
    debugLog("readTasksCache starting")
    tasksCacheProc.token = tasksCacheToken
    tasksCacheProc.command = [helperPath(), "list-tasks", "--from-cache", "--provider", provider]
    if (calendarId) tasksCacheProc.command.push("--calendar-id", calendarId)
    tasksCacheProc.running = true
  }

  function writeCache() {
    if (tasksWriteCacheProc.running) {
      debugLog("writeCache skipped - already running")
      return
    }
    debugLog("writeCache - tasks: " + cachedTasks.length)
    tasksWriteCacheProc.secret = JSON.stringify({
      tasks: cachedTasks,
      calendars: cachedCalendars
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
    if (tasksCacheProc.token !== root.tasksCacheToken) {
      debugLog("finishListCache skipped - token mismatch")
      return
    }
    var payload = TaskModel.parseHelperResponse(text)
    debugLog("finishListCache payload.ok: " + payload.ok + " tasks: " + (payload.tasks ? payload.tasks.length : 0))
    if (exitCode === 0 && payload.ok) {
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
      applyTaskCache(payload.tasks, payload.calendars)
      writeCache()
    } else if (cachedTasks.length === 0) {
      root.tasksStatus = "error"
      root.tasksErrorMessage = root.failMessage(payload, "Task helper failed")
      root.refreshed()
    }
  }

  function createTask(calendarIdArg, title, due, priority) {
    debugLog("action: create-task calendar=" + calendarIdArg + " title=" + title)
    var targetCalendar = String(calendarIdArg || calendarId || defaultCalendarId())
    tasksStatus = "saving"
    tasksErrorMessage = ""
    if (tasksCreateProc.running) tasksCreateProc.running = false
    tasksPendingCreateId = "omarchy-task-pending-" + Date.now()
    var optimistic = TaskModel.normalizedTask({
      id: tasksPendingCreateId,
      uid: tasksPendingCreateId,
      title: title,
      due: due || "",
      status: "NEEDS-ACTION",
      priority: priority || "",
      calendarId: targetCalendar,
      calendarName: calendarNameById(targetCalendar)
    })
    optimistic._pending = true
    var next = cachedTasks.slice()
    next.push(optimistic)
    applyTaskCache(next, cachedCalendars)
    tasksCreateProc.command = [
      helperPath(), "create-task",
      "--provider", provider,
      "--calendar-id", targetCalendar,
      "--title", String(title || "(No title)"),
      "--due", String(due || ""),
      "--priority", String(priority || "")
    ]
    tasksCreateProc.running = true
  }

  function finishCreateTask(text, exitCode) {
    var payload = TaskModel.parseHelperResponse(text)
    if (exitCode === 0 && payload.ok) {
      removePendingTask(root.tasksPendingCreateId)
      if (payload.tasks && payload.tasks.length > 0) {
        mergeTask(payload.tasks[0])
        root.taskCreated(payload.tasks[0])
      }
      root.tasksStatus = "ready"
      root.tasksErrorMessage = ""
      root.startTasksLiveSync(true)
    } else {
      removePendingTask(root.tasksPendingCreateId)
      root.tasksStatus = "error"
      root.tasksErrorMessage = root.failMessage(payload, "Could not create task.")
    }
    root.tasksPendingCreateId = ""
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
      "--provider", provider,
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

  function finishUpdateTask(text, exitCode) {
    var payload = TaskModel.parseHelperResponse(text)
    if (exitCode === 0 && payload.ok) {
      if (payload.tasks && payload.tasks.length > 0) {
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
      "--provider", provider,
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

  // ===== Calendar Removal =====

  function removeCalendar(calendarId) {
    debugLog("action: remove-calendar id=" + calendarId)
    var id = String(calendarId || "")
    if (!id || removeProc.running || pendingRemoveId) return
    pendingRemoveId = id
    removeError = ""
    removeProc.command = [helperPath(), "remove-calendar", "--provider", provider, "--calendar-id", id]
    removeProc.running = true
  }

  function finishRemoveCalendar(text, exitCode) {
    var payload = TaskModel.parseHelperResponse(text)
    if (exitCode === 0 && payload.ok) {
      var id = pendingRemoveId
      root.cachedCalendars = cachedCalendars.filter(function(cal) { return cal && cal.id !== id })
      root.calendars = root.cachedCalendars
      pendingRemoveId = ""
      removeError = ""
      listTasks(true)
    } else {
      removeError = failMessage(payload, "Could not remove calendar.")
      pendingRemoveId = ""
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
      root.finishListTasks(root.helperText(tasksListOut.text, tasksListErr.text), exitCode)
    }
  }

  Process {
    id: tasksCacheProc
    property int token: 0
    running: false

    stdout: StdioCollector { id: tasksCacheOut; waitForEnd: true }
    stderr: StdioCollector { id: tasksCacheErr; waitForEnd: true }

    onExited: function(exitCode) {
      debugLog("tasksCacheProc exited with code: " + exitCode)
      root.finishListCache(root.helperText(tasksCacheOut.text, tasksCacheErr.text), exitCode)
    }
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
    running: false

    stdout: StdioCollector { id: tasksCreateOut; waitForEnd: true }
    stderr: StdioCollector { id: tasksCreateErr; waitForEnd: true }

    onExited: function(exitCode) {
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
    id: tasksDeleteProc
    running: false

    stdout: StdioCollector { id: tasksDeleteOut; waitForEnd: true }
    stderr: StdioCollector { id: tasksDeleteErr; waitForEnd: true }

    onExited: function(exitCode) {
      root.finishDeleteTask(root.helperText(tasksDeleteOut.text, tasksDeleteErr.text), exitCode)
    }
  }

  Process {
    id: removeProc
    running: false

    stdout: StdioCollector { id: removeOut; waitForEnd: true }
    stderr: StdioCollector { id: removeErr; waitForEnd: true }

    onExited: function(exitCode) {
      root.finishRemoveCalendar(root.helperText(removeOut.text, removeErr.text), exitCode)
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
