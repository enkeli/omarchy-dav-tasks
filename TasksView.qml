import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "TaskModel.js" as TaskModel

Column {
  id: tasksView
  spacing: Style.space(4)

  // Accept service as property from Panel.qml (root is not accessible from separate file)
  property var calendarService: null
  property var panel: null
  property string viewMode: "month"
  property bool opened: false

  readonly property var taskService: calendarService
  property string activeTab: "pending"
  property date now: new Date()

  // One entry per distinct plugin-managed CalDAV server, sorted by host, each
  // with its calendar count (disabled ones included). Drives the read-only
  // Servers section in the config tab.
  readonly property var serverConnections: TaskModel.serverConnections(calendarService ? calendarService.calendars : [])

  // --- Keyboard model ---------------------------------------------------
  // Panel.qml owns the key dispatcher and the help overlay; this view owns
  // the cursor and every action a key can trigger (performAction). Contexts
  // match the registry in Keybindings.js.

  // Pending/Done list filter ("/"). The field doubles as the applied filter:
  // it stays visible while it has text, even after it loses focus.
  readonly property string filterText: filterField.text
  readonly property bool filterActive: filterText.trim() !== ""
  property bool filterOpen: false
  readonly property bool editingTask: addTaskView.editing
  // Why the last edit attempt was refused (shown above the list).
  property string editError: ""

  // Task cursor: which section on the active list tab, and which row of the
  // page that section currently shows. Config tab uses configIndex instead.
  property int cursorSection: 0
  property int cursorRow: 0
  property int configIndex: 0
  // Color palette popup currently open on a config row (null when closed).
  property var activePalette: null
  // Wide view (F11): the pending tab lays every page out as a column across
  // the panel. Rows per column follow the height of the scroll area `viewport`.
  property bool wideMode: false
  property var viewport: null
  readonly property real wideColumnWidth: Style.space(350)
  readonly property real wideHeaderHeight: wideHeaderProbe.implicitHeight + Style.space(4) + 1
  readonly property bool wideActive: wideMode && activeTab === "pending"
  readonly property real wideRowPitch: wideRowProbe.height + Style.space(4)
  readonly property real wideColumnPitch: wideColumnWidth + Style.space(12)
  function wideColumnsOf(section) { return section.tasks.length === 0 ? 1 : section.pageCount }
  // Done columns that still fit after Upcoming and Backlog. Columns plus two
  // 1px dividers and 12px of gap come to N * pitch + 14 in total.
  readonly property int wideDoneFit: wideActive && doneSection.tasks.length > 0
    ? Math.max(0, Math.floor((wideStrip.width - 14) / wideColumnPitch) - wideColumnsOf(upcomingSection) - wideColumnsOf(backlogSection))
    : 0
  readonly property real wideAvailableHeight: viewport
    ? Math.max(0, viewport.height - tasksView.mapToItem(viewport.contentItem, 0, 0).y - pendingColumn.y)
    : 0

  readonly property var navSections: activeTab === "pending"
    ? (wideDoneFit > 0 ? [upcomingSection, backlogSection, doneSection] : [upcomingSection, backlogSection])
    : activeTab === "done" ? [doneSection] : []

  // Text fields consume some Ctrl chords themselves (Ctrl+D deletes, Ctrl+K
  // kills the line), which would never reach an ancestor's handler. Each field
  // forwards its keys to the panel's dispatcher first; plain typing is left
  // unaccepted there and falls back to the field.
  readonly property var keyForward: panel && panel.keyCatcherItem ? [panel.keyCatcherItem] : []

  // A text field has focus: plain keys must reach it instead of the cursor.
  readonly property bool textEditing: filterField.activeFocus
    || addSummaryField.activeFocus
    || addDescriptionField.activeFocus
    || addCategoryField.activeFocus
    || addStartInput.field.activeFocus
    || addDueInput.field.activeFocus
    || caldavUrlField.activeFocus
    || caldavUsernameField.activeFocus
    || caldavPasswordField.activeFocus

  // The shared Dropdown popup runs its own list navigation.
  readonly property bool modalBlocked: addCalendarDropdown.popupOpen

  readonly property string keyContext: {
    if (activePalette) return "palette"
    if (activeTab === "add") return addTaskView.duePickerOpen ? "picker" : "form"
    if (activeTab === "config") return "config"
    return "list"
  }

  // Direct binding to taskService.allTasks - this should update when the property changes
  readonly property var allTasks: taskService ? taskService.allTasks : []

  // Debug: log when allTasks changes
  onAllTasksChanged: {
    debugLog("allTasks property changed: " + (allTasks ? allTasks.length : 0))
  }

  function debugLog(message) {
    if (calendarService) calendarService.debugLog(message)
  }

  function sanitizeUrl(url) {
    return String(url).replace(/^(\w+:\/\/)[^@\/]*@/, "$1")
  }

  // Dismiss the connect-server form and drop any finished setup state so the
  // next attempt starts clean. Password must never linger in the field.
  function closeCaldavForm() {
    caldavSuccessCloseTimer.stop()
    caldavUrlField.text = ""
    caldavUsernameField.text = ""
    caldavPasswordField.text = ""
    caldavForm.visible = false
    if (calendarService && calendarService.caldavSetupStatus === "success") {
      calendarService.resetCaldavSetup()
    }
  }

  function openCaldavForm() {
    debugLog("action: open caldav form")
    caldavForm.visible = true
    Qt.callLater(function() { caldavUrlField.forceActiveFocus() })
  }

  function submitCaldav() {
    if (!calendarService || calendarService.caldavSetupStatus === "connecting") return
    debugLog("action: caldav connect " + sanitizeUrl(caldavUrlField.text))
    calendarService.setupCaldav("", caldavUrlField.text, caldavUsernameField.text, caldavPasswordField.text)
  }

  // --- Keyboard actions ---------------------------------------------------

  function focusPanel() {
    if (panel && typeof panel.focusKeyCatcher === "function") panel.focusKeyCatcher()
  }

  // Scroll the panel so a cursor target is on screen (rows can sit below the
  // fold when details are expanded or the add form is tall).
  function reveal(item) {
    if (item && panel && typeof panel.revealItem === "function") panel.revealItem(item)
  }

  // Reveal after layout settles; owned by the view (not a delegate) so a
  // row rebuilt in between can't leave a dangling callback.
  function setWide(on) {
    if (wideMode === on) return
    wideMode = on
    upcomingSection.page = 1
    backlogSection.page = 1
    doneSection.page = 1
    resetCursor()
    scheduleReveal()
  }
  function toggleWide() { setWide(!wideMode) }
  // Scroll the wide strip so the cursor's page column is fully visible.
  function revealWide() {
    var section = currentSection()
    if (!wideActive || !section || section.tasks.length === 0) return
    var block = section === upcomingSection ? wideUpcoming : section === backlogSection ? wideBacklog : section === doneSection ? wideDone : null
    if (!block) return
    var column = block.pageItem(section.currentPage - 1)
    if (!column) return
    var left = column.mapToItem(wideStrip.contentItem, 0, 0).x
    var right = left + column.width
    var x = wideStrip.contentX
    if (left < x) x = left
    else if (right > x + wideStrip.width) x = right - wideStrip.width
    wideStrip.contentX = Math.max(0, Math.min(x, Math.max(0, wideStrip.contentWidth - wideStrip.width)))
  }
  function revealCurrent() {
    if (wideMode) { revealWide(); return }
    var item = keyContext === "list" ? currentItem() : null
    if (item) reveal(item)
  }

  function scheduleReveal() { Qt.callLater(revealCurrent) }

  onCursorRowChanged: scheduleReveal()
  onCursorSectionChanged: scheduleReveal()

  function formStep(direction) { addTaskView.formStep(direction) }

  function sectionRows(section) {
    return section ? section.pageTasks.length : 0
  }

  // Keep the cursor on a real row after the model, filter or page changed.
  function clampCursor() {
    var sections = navSections
    if (sections.length === 0) return
    cursorSection = Math.max(0, Math.min(cursorSection, sections.length - 1))
    if (sectionRows(sections[cursorSection]) === 0) {
      for (var i = 0; i < sections.length; i++) {
        if (sectionRows(sections[i]) > 0) { cursorSection = i; break }
      }
    }
    var rows = sectionRows(sections[cursorSection])
    cursorRow = rows === 0 ? 0 : Math.max(0, Math.min(cursorRow, rows - 1))
  }

  function resetCursor() {
    cursorSection = 0
    cursorRow = 0
    configIndex = 0
    Qt.callLater(clampCursor)
  }

  function currentSection() {
    var sections = navSections
    return sections.length > 0 ? sections[Math.max(0, Math.min(cursorSection, sections.length - 1))] : null
  }

  // Wide view: the card under the keyboard cursor. Columns are not part of the
  // list model, so walk the wide block's item tree (flickable content included).
  function wideCursorItem(node) {
    if (!node) return null
    if (node.cursor === true && node.toggleExpanded) return node
    var kids = node.children || []
    for (var i = 0; i < kids.length; i++) {
      var found = wideCursorItem(kids[i])
      if (found) return found
    }
    return wideCursorItem(node.contentItem)
  }

  function currentItem() {
    var section = currentSection()
    return section ? section.rowItem(cursorRow) : null
  }

  function moveCursor(dy) {
    if (activeTab === "config") { moveConfig(dy); return }
    var sections = navSections
    if (sections.length === 0) return
    clampCursor()
    var section = sections[cursorSection]
    var rows = sectionRows(section)
    var target = cursorRow + dy
    if (target >= 0 && target < rows) { cursorRow = target; return }
    if (dy > 0) {
      // Past the last row: next page of this section, then the next section.
      if (section.currentPage < section.pageCount) {
        section.page = section.currentPage + 1
        cursorRow = 0
        return
      }
      for (var i = cursorSection + 1; i < sections.length; i++) {
        if (sectionRows(sections[i]) > 0) { cursorSection = i; cursorRow = 0; return }
      }
    } else {
      if (section.currentPage > 1) {
        section.page = section.currentPage - 1
        cursorRow = sectionRows(section) - 1
        return
      }
      for (var j = cursorSection - 1; j >= 0; j--) {
        var count = sectionRows(sections[j])
        if (count > 0) { cursorSection = j; cursorRow = count - 1; return }
      }
    }
  }

  function jumpCursor(toEnd) {
    if (activeTab === "config") { configIndex = toEnd ? configCount - 1 : 0; revealConfig(); return }
    var sections = navSections
    var order = []
    for (var i = 0; i < sections.length; i++) if (sectionRows(sections[i]) > 0 || sections[i].tasks.length > 0) order.push(i)
    if (order.length === 0) return
    var index = toEnd ? order[order.length - 1] : order[0]
    var section = sections[index]
    section.page = toEnd ? section.pageCount : 1
    cursorSection = index
    cursorRow = toEnd ? Math.max(0, sectionRows(section) - 1) : 0
  }

  function movePage(delta) {
    var section = currentSection()
    if (!section) return
    var next = section.currentPage + delta
    if (next < 1 || next > section.pageCount) return
    section.page = next
    clampCursor()
  }

  function cycleTab(delta) {
    var tabs = ["pending", "done", "config"]
    var index = tabs.indexOf(activeTab)
    activeTab = tabs[((index < 0 ? 0 : index) + delta + tabs.length) % tabs.length]
  }

  function openFilter() {
    filterOpen = true
    Qt.callLater(function() { filterField.forceActiveFocus() })
  }

  function clearFilter() {
    filterField.text = ""
    filterOpen = false
    Qt.callLater(clampCursor)
  }

  // --- Config tab cursor ---
  // Rows are the calendars, then Connect Server (while its form is closed),
  // the debug toggle and, with debug on, Clear logs.
  readonly property int calendarCount: calendarService && calendarService.calendars ? calendarService.calendars.length : 0
  readonly property bool debugOn: calendarService ? calendarService.debugMode : false
  readonly property var configKinds: {
    var kinds = []
    if (!caldavForm.visible) kinds.push("connect")
    kinds.push("debug")
    if (debugOn) kinds.push("clearLogs")
    return kinds
  }
  readonly property int configCount: calendarCount + configKinds.length
  readonly property string configCursorKind: {
    if (activeTab !== "config") return ""
    var index = Math.max(0, Math.min(configIndex, configCount - 1))
    return index < calendarCount ? "calendar" : configKinds[index - calendarCount]
  }

  function moveConfig(dy) {
    if (configCount === 0) return
    configIndex = Math.max(0, Math.min(configIndex + dy, configCount - 1))
    revealConfig()
  }

  function configRow(index) {
    return index >= 0 && index < calendarCount ? calendarRows.itemAt(index) : null
  }

  function revealConfig() {
    var index = Math.max(0, Math.min(configIndex, configCount - 1))
    var kind = configCursorKind
    var item = kind === "calendar" ? configRow(index)
      : kind === "connect" ? connectServerButton
      : kind === "debug" ? debugToggle
      : kind === "clearLogs" ? clearLogsButton : null
    Qt.callLater(function() { reveal(item) })
  }

  function activateConfig() {
    var kind = configCursorKind
    if (kind === "calendar") {
      var row = configRow(Math.min(configIndex, calendarCount - 1))
      if (row) row.toggleEnabled()
    } else if (kind === "connect") {
      openCaldavForm()
    } else if (kind === "debug") {
      toggleDebugMode()
    } else if (kind === "clearLogs") {
      if (calendarService) calendarService.clearDebugLog()
    }
  }

  function toggleDebugMode() {
    var next = !(calendarService && calendarService.debugMode)
    if (calendarService) calendarService.debugMode = next
    if (panel) panel.persistSettings({ debug: next })
    debugLog("action: toggle debug mode -> " + next)
  }

  // Esc peels one layer at a time; returns false when nothing was left to
  // close, which tells Panel.qml to close the panel itself.
  function handleEscape() {
    if (activePalette) { activePalette.closePalette(); return true }
    if (activeTab === "add") {
      if (addTaskView.duePickerOpen) {
        addTaskView.closeDuePicker()
        return true
      }
      addTaskView.escapeAdd()
      return true
    }
    if (wideMode) { setWide(false); return true }
    if (filterField.activeFocus) {
      filterField.focus = false
      focusPanel()
      return true
    }
    if (caldavForm.visible) {
      closeCaldavForm()
      focusPanel()
      return true
    }
    if (filterActive || filterOpen) { clearFilter(); return true }
    if (activeTab !== "pending") { activeTab = "pending"; return true }
    return false
  }

  // Run a registry action (see Keybindings.js). Returns true when handled.
  function performAction(id) {
    var item = null
    switch (id) {
    case "help": if (panel) panel.openHelp(); return true
    case "sync": if (panel) panel.refresh(); return true
    case "wide": toggleWide(); return true
    case "addTask": activeTab = "add"; return true
    case "tabPending": activeTab = "pending"; return true
    case "tabDone": activeTab = "done"; return true
    case "tabConfig": activeTab = "config"; return true
    case "tabNext": cycleTab(1); return true
    case "tabPrev": cycleTab(-1); return true
    case "cursorDown": moveCursor(1); return true
    case "cursorUp": moveCursor(-1); return true
    case "cursorTop": jumpCursor(false); return true
    case "cursorBottom": jumpCursor(true); return true
    case "pagePrev": movePage(-1); return true
    case "pageNext": movePage(1); return true
    case "filter": openFilter(); return true
    case "toggleExpand":
      if (wideActive) {
        item = wideCursorItem(wideBlock)
        if (item) item.toggleExpanded()
        return true
      }
      item = currentItem()
      if (item) item.toggleExpanded()
      return true
    case "toggleComplete":
      item = currentItem()
      if (item) item.toggleComplete()
      return true
    case "deleteTask":
      item = currentItem()
      if (item) item.requestDelete()
      return true
    case "editTask":
      item = currentItem()
      if (item) item.requestEdit()
      return true
    case "configActivate": activateConfig(); return true
    case "configColor":
      if (configCursorKind === "calendar") {
        var row = configRow(Math.min(configIndex, calendarCount - 1))
        if (row) row.openPalette()
      }
      return true
    case "connectServer": openCaldavForm(); return true
    case "formSubmit": addTaskView.trySubmit(); return true
    case "formPickDue": addTaskView.toggleDuePicker("due"); return true
    case "formPickStart": addTaskView.toggleDuePicker("start"); return true
    case "formCalendarPopup": addCalendarDropdown.open(); return true
    case "formCalendarNext": addTaskView.stepCalendar(1); return true
    case "formCalendarPrev": addTaskView.stepCalendar(-1); return true
    case "pickerLeft": addDueGrid.moveDays(-1); return true
    case "pickerRight": addDueGrid.moveDays(1); return true
    case "pickerUp": addDueGrid.moveDays(-7); return true
    case "pickerDown": addDueGrid.moveDays(7); return true
    case "pickerPrevMonth": addDueGrid.moveMonths(-1); return true
    case "pickerNextMonth": addDueGrid.moveMonths(1); return true
    case "pickerToday": addDueGrid.cursorToday(); return true
    case "pickerSelect": addDueGrid.pickCursor(); return true
    case "pickerClear":
      addTaskView.clearActiveDate()
      addTaskView.closeDuePicker()
      return true
    case "palettePrev": if (activePalette) activePalette.movePalette(-1); return true
    case "paletteNext": if (activePalette) activePalette.movePalette(1); return true
    case "paletteSelect": if (activePalette) activePalette.pickPalette(); return true
    }
    return false
  }

  onFilterTextChanged: Qt.callLater(clampCursor)
  onCalendarCountChanged: Qt.callLater(clampConfig)
  onConfigCountChanged: Qt.callLater(clampConfig)

  function clampConfig() {
    configIndex = Math.max(0, Math.min(configIndex, Math.max(0, configCount - 1)))
  }

  // VTODO priority is the string "1"-"9" (1 = highest) or "" when unset.
  // Map to display wording; anything unparsable maps to "" so the field hides.
  function priorityLabel(value) {
    var p = parseInt(value, 10)
    if (!isFinite(p) || p < 1 || p > 9) return ""
    if (p <= 4) return "High"
    if (p === 5) return "Medium"
    return "Low"
  }

  // RFC 5545 VTODO status to readable wording. Status may vary in case, so
  // compare uppercased; unknown values fall through as-is instead of hiding.
  function statusLabel(value) {
    var s = String(value || "").toUpperCase()
    if (s === "NEEDS-ACTION") return "Needs action"
    if (s === "IN-PROCESS") return "In progress"
    if (s === "COMPLETED") return "Completed"
    if (s === "CANCELLED") return "Cancelled"
    return String(value || "")
  }

  function syncTaskModelDebug() {
    TaskModel.setDebugEnabled(calendarService && calendarService.debugMode === true)
  }

  // --- Inline sub-components ---

  component TaskSection: Column {
    id: taskSection
    property string title: ""
    property var tasks: []
    // Total tasks in this category (uncapped), shown next to the title.
    property int count: 0
    property string emptyText: "No tasks"
    property string dateLabel: "due"
    property bool showOverdue: false
    // Pagination: `tasks` carries the full uncapped list and the view owns
    // slicing; the Repeater renders only the current page.
    property int pageSize: 5
    property int page: 1
    readonly property int pageCount: tasksView.wideActive ? Math.max(1, Math.min(widePageRows.length, maxWidePages)) : Math.max(1, Math.ceil(tasks.length / pageSize))
    // Clamped read-only view of `page`, so a shrunken list can never drive
    // the slice or the pager label out of range.
    readonly property int currentPage: Math.min(Math.max(page, 1), pageCount)
    readonly property var pageTasks: tasksView.wideActive ? (widePageRows[currentPage - 1] || []) : tasks.slice((currentPage - 1) * pageSize, currentPage * pageSize)
    // Exactly pageSize slots whenever the section is populated: real tasks
    // for the first pageTasks.length entries, null fillers after. The
    // Repeater therefore always lays out a full page, so a short list can
    // never shrink the section and pull the next one up. Section height
    // falls out of the Column's natural layout — no height overrides and no
    // cross-item measurements that could defer or latch.
    // Wide view: rows packed into columns by measured height (see WidePages).
    property var widePageRows: []
    // Wide view: caps how many packed pages are used (Done shows only what fits).
    property int maxWidePages: 1000000
    onWidePageRowsChanged: Qt.callLater(tasksView.clampCursor)
    // Keyboard cursor sits on this row of the given page.
    function cursorOn(p, row) {
      return tasksView.keyContext === "list"
        && tasksView.navSections.indexOf(taskSection) === tasksView.cursorSection
        && p === currentPage && row === tasksView.cursorRow
    }
    onPageChanged: tasksView.scheduleReveal()
    readonly property var pageSlots: {
      if (tasks.length === 0) return []
      var slots = []
      var shown = pageTasks.length
      for (var i = 0; i < pageSize; i++) slots.push(i < shown ? pageTasks[i] : null)
      return slots
    }
    // Canonical stand-in for filler slots. It mirrors a real collapsed row's
    // structure — calendar meta line shown, like every normalized task — so
    // placeholder height matches real row height exactly (layout
    // replication, not measurement). TaskItem blanks and disables the
    // stand-in via its `inert` flag.
    readonly property var placeholderStandIn: ({ id: "", title: "", calendarName: "Calendar", status: "NEEDS-ACTION" })
    width: parent.width
    spacing: Style.space(4)

    // Row (within the visible page) the keyboard cursor is on, or -1 when the
    // cursor lives in another section or screen.
    readonly property int cursorRow: tasksView.keyContext === "list"
      && tasksView.navSections.indexOf(taskSection) === tasksView.cursorSection
      ? tasksView.cursorRow : -1

    function rowItem(index) {
      return index >= 0 ? rowRepeater.itemAt(index) : null
    }

    // Model rebuilds hand back a fresh array; that reference change snaps
    // back to the first page, mirroring how delegate rebuilds reset
    // TaskItem.expanded. Imperative write, so no binding loop.
    onTasksChanged: taskSection.page = 1

    // Title row: bold accent label followed inline by the total count in
    // parentheses, muted and one step smaller. Always rendered so the
    // counter keeps a stable home as the underlying data changes.
    Item {
      width: parent.width
      height: taskSectionTitle.implicitHeight

      Text {
        id: taskSectionTitle
        anchors.left: parent.left
        text: taskSection.title
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        anchors.left: taskSectionTitle.right
        anchors.leftMargin: Style.space(4)
        anchors.baseline: taskSectionTitle.baseline
        text: "(" + taskSection.count + ")"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Color.accent
    }

    Repeater {
      id: rowRepeater
      model: taskSection.pageSlots

      TaskItem {
        required property var modelData
        required property int index
        readonly property bool placeholder: !modelData
        cursor: !placeholder && taskSection.cursorRow === index
        width: taskSection.width
        // Filler slots (modelData null) render the stand-in so the row's
        // internal layout matches real rows exactly; `inert` blanks and
        // disables everything the stand-in would otherwise paint.
        task: modelData || taskSection.placeholderStandIn
        inert: placeholder
        showOverdue: taskSection.showOverdue
        dateLabel: taskSection.dateLabel
      }
    }

    // Pager: flat muted text row, centered. It occupies its slot in every
    // populated section so the 5↔6 boundary — where the pager first
    // appears — never shifts the layout either: with a single page it
    // renders as a same-height blank spacer (opacity 0; both arrows are
    // disabled because currentPage equals pageCount). Hovered arrows pick
    // up the accent like the status circle; spent ends dim out the way
    // disabled due-date cells do. Hidden entirely on empty sections, which
    // stay compact.
    Row {
      visible: taskSection.tasks.length > 0
      opacity: taskSection.pageCount > 1 ? 1 : 0
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(6)

      Item {
        width: Style.space(12)
        height: pagerLabel.implicitHeight
        enabled: taskSection.currentPage > 1

        Text {
          anchors.centerIn: parent
          text: "‹"
          color: !parent.enabled ? Util.alpha(Color.muted, 0.35)
            : prevPageMouse.containsMouse ? Color.accent
            : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
        }

        MouseArea {
          id: prevPageMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: taskSection.page = Math.max(1, taskSection.page - 1)
        }
      }

      Text {
        id: pagerLabel
        text: taskSection.currentPage + " / " + taskSection.pageCount
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
      }

      Item {
        width: Style.space(12)
        height: pagerLabel.implicitHeight
        enabled: taskSection.currentPage < taskSection.pageCount

        Text {
          anchors.centerIn: parent
          text: "›"
          color: !parent.enabled ? Util.alpha(Color.muted, 0.35)
            : nextPageMouse.containsMouse ? Color.accent
            : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
        }

        MouseArea {
          id: nextPageMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: taskSection.page = Math.min(taskSection.pageCount, taskSection.page + 1)
        }
      }
    }

    Text {
      visible: taskSection.tasks.length === 0
      width: parent.width
      text: taskSection.emptyText
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
    }
  }

  // Wide view header: section title plus page number, with the accent rule.
  component WideHeader: Column {
    id: wideHeader
    property string label: ""
    width: tasksView.wideColumnWidth
    spacing: Style.space(4)
    Text {
      width: parent.width
      text: wideHeader.label
      color: Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
      textFormat: Text.PlainText
      elide: Text.ElideRight
    }
    Rectangle {
      width: parent.width
      height: 1
      color: Color.accent
    }
  }
  // Estimated height of one wide row, without building a TaskItem: the title is
  // wrapped at the width the row leaves for it, and each extra title line adds
  // one line height to the single-line row. Bold is assumed (the wider case),
  // so the estimate errs tall rather than clipping.
  component WideRowMeasure: Item {
    id: measure
    property var task: null
    property string dateLabel: "due"
    readonly property string createdString: {
      if (!task) return ""
      var d = TaskModel.parseDateTime(task.created)
      if (!d) return ""
      var month = TaskModel.SHORT_MONTH_NAMES[d.getMonth()]
      var day = d.getDate()
      var year = d.getFullYear()
      if (year === new Date().getFullYear()) return month + " " + day
      return month + " " + day + ", " + year
    }
    readonly property string dateString: {
      if (!task) return ""
      if (dateLabel === "completed") return TaskModel.formatCompletedDate(task)
      if (dateLabel === "created") return createdString
      return TaskModel.formatDueDate(task)
    }
    width: tasksView.wideColumnWidth
    height: wideRowProbe.height + Math.max(0, titleM.lineCount - 1) * tasksView.wideLineHeight
    Text {
      id: dateM
      text: measure.dateString
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
      opacity: 0
    }
    Text {
      id: titleM
      width: Math.max(1, tasksView.wideColumnWidth - Style.space(16) - Style.space(12) - tasksView.wideStatusWidth - dateM.implicitWidth)
      text: measure.task ? TaskModel.plainDisplay(measure.task.title, 200) : ""
      wrapMode: Text.WordWrap
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      textFormat: Text.PlainText
      opacity: 0
    }
  }
  // One section in the wide view: a column per page, each filled to the rows
  // that fit the height. Empty sections show their empty text instead. Rows are
  // measured off-screen, only as many as the visible columns can use (see
  // measureLimit), and packed once per change rather than on every height.
  component WidePages: Item {
    id: widePages
    property var section: null
    readonly property var sectionTasks: section !== null ? section.tasks : []
    // Tasks rendered for measuring. A capped section (Done) starts with enough
    // for the columns that fit and doubles only if packing comes up short.
    property int measureLimit: 0
    readonly property int rowsPerColumn: Math.max(1, Math.floor((tasksView.wideAvailableHeight - tasksView.wideHeaderHeight + Style.space(4)) / Math.max(1, tasksView.wideRowPitch)))
    readonly property var packKey: [tasksView.wideMode, tasksView.wideAvailableHeight, sectionTasks, section !== null ? section.maxWidePages : 0]
    width: pageRow.width
    height: pageRow.height
    function pageItem(index) { return pageRepeater.itemAt(index) }
    function initialLimit() {
      if (section === null) return 0
      var total = sectionTasks.length
      if (section.maxWidePages >= 1000000) return total
      return Math.min(total, Math.max(10, section.maxWidePages * rowsPerColumn * 2))
    }
    function scheduleRepack() { repackTimer.restart() }
    function repack() {
      if (section === null) return
      if (!tasksView.wideMode) { section.widePageRows = []; return }
      var heights = []
      for (var i = 0; i < measureRepeater.count; i++) {
        var item = measureRepeater.itemAt(i)
        heights.push(item ? item.height : 0)
      }
      var budget = tasksView.wideAvailableHeight - tasksView.wideHeaderHeight + Style.space(4)
      var result = TaskModel.packWideColumns(sectionTasks, heights, budget, Style.space(4),
                                             section.maxWidePages, measureLimit < sectionTasks.length)
      if (result.status === 'pending') return // not laid out yet; repacks on height
      if (result.status === 'grow') {
        measureLimit = Math.min(sectionTasks.length, measureLimit * 2)
        return
      }
      section.widePageRows = result.pages
    }
    onPackKeyChanged: {
      measureLimit = initialLimit()
      scheduleRepack()
    }
    Component.onCompleted: {
      measureLimit = initialLimit()
      scheduleRepack()
    }
    Timer {
      id: repackTimer
      interval: 0
      onTriggered: widePages.repack()
    }
    Row {
      id: pageRow
      spacing: Style.space(12)
      Column {
        visible: widePages.section !== null && widePages.sectionTasks.length === 0
        width: tasksView.wideColumnWidth
        spacing: Style.space(4)
        WideHeader { label: widePages.section ? widePages.section.title : "" }
        Text {
          width: parent.width
          text: widePages.section ? widePages.section.emptyText : ""
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
        }
      }
      Repeater {
        id: pageRepeater
        model: widePages.section !== null && widePages.sectionTasks.length > 0 ? widePages.section.pageCount : 0
        Column {
          id: pageColumn
          required property int index
          width: tasksView.wideColumnWidth
          spacing: Style.space(4)
          WideHeader { label: widePages.section.title + " " + (pageColumn.index + 1) + "/" + widePages.section.pageCount }
          Repeater {
            model: widePages.section.widePageRows[pageColumn.index] || []
            TaskItem {
              required property var modelData
              required property int index
              cursor: widePages.section.cursorOn(pageColumn.index + 1, index)
              width: tasksView.wideColumnWidth
              task: modelData
              showOverdue: widePages.section.showOverdue
              dateLabel: widePages.section.dateLabel
            }
          }
        }
      }
    }
    // Off-screen copy used only to read real row heights (wrapped titles
    // included). Zero-sized and clipped, so it takes no room in the layout.
    Item {
      width: 0
      height: 0
      clip: true
      visible: tasksView.wideMode
      Column {
        width: tasksView.wideColumnWidth
        Repeater {
          id: measureRepeater
          model: tasksView.wideMode && widePages.section !== null ? widePages.sectionTasks.slice(0, widePages.measureLimit) : []
          WideRowMeasure {
            required property var modelData
            task: modelData
            dateLabel: widePages.section.dateLabel
            onHeightChanged: widePages.scheduleRepack()
          }
        }
      }
    }
  }
  component TaskItem: Rectangle {
    id: taskItem
    property var task: null
    property bool showOverdue: false
    property string dateLabel: "due"
    // Per-delegate expansion state: clicking anywhere on the row (except the
    // status circle) reveals the detail block below the collapsed content.
    // Model rebuilds recreate delegates and reset this — acceptable.
    property bool expanded: false
    // Two-step delete confirmation: armed by the footer button's first click,
    // fired by the second, disarmed by timeout, collapse, or model rebuild.
    property bool deleteArmed: false
    // Page-slot filler row: rendered from the section's stand-in object so
    // its geometry matches real rows exactly, with all content blanked and
    // every interaction disabled (no hover fill, no click targets, no
    // cursor change).
    property bool inert: false
    // Keyboard cursor is on this row.
    property bool cursor: false
    // Details were opened by arming a delete, not by the user.
    property bool openedForDelete: false

    onCursorChanged: {
      if (!taskItem.cursor) {
        // Moving away abandons a half-confirmed delete, and closes details
        // that only the delete prompt opened.
        taskItem.deleteArmed = false
        deleteArmTimer.stop()
        if (taskItem.openedForDelete) taskItem.expanded = false
      }
    }

    function toggleExpanded() {
      if (!taskItem.task || taskItem.inert) return
      taskItem.openedForDelete = false
      taskItem.expanded = !taskItem.expanded
      tasksView.debugLog("action: " + (taskItem.expanded ? "expand" : "collapse") + " task " + taskItem.task.uid)
      tasksView.scheduleReveal()
    }

    // Completes a pending task or reopens a completed one.
    function toggleComplete() {
      if (!taskItem.task || taskItem.inert || !tasksView.taskService) return
      if (taskItem.completed) {
        tasksView.debugLog("action: reopen task " + taskItem.task.uid)
        tasksView.taskService.updateTask(taskItem.task, "NEEDS-ACTION", 0)
        return
      }
      tasksView.debugLog("action: complete task " + taskItem.task.uid)
      tasksView.taskService.completeTask(taskItem.task)
    }

    function requestEdit() {
      if (!taskItem.task || taskItem.inert || !tasksView.taskService) return
      addTaskView.beginEdit(taskItem.task)
    }

    // Two-step delete: the first call arms and opens the details so the
    // "Confirm delete?" button is visible, the second call deletes.
    function requestDelete() {
      if (!taskItem.task || taskItem.inert || !tasksView.taskService || tasksView.taskService.pendingDeleteUid) return
      if (!taskItem.deleteArmed) {
        taskItem.openedForDelete = !taskItem.expanded
        taskItem.expanded = true
        taskItem.deleteArmed = true
        deleteArmTimer.restart()
        tasksView.debugLog("action: arm delete task " + taskItem.task.uid)
        tasksView.scheduleReveal()
        return
      }
      taskItem.deleteArmed = false
      deleteArmTimer.stop()
      tasksView.debugLog("action: delete task " + taskItem.task.uid)
      tasksView.taskService.deleteTask(taskItem.task)
    }

    // Case-insensitive completed check: the Done tab filters with
    // TaskModel.isCompleted, so icon/strikethrough must use the same
    // predicate or non-uppercase statuses render as pending circles.
    readonly property bool completed: taskItem.task && TaskModel.isCompleted(taskItem.task)

    readonly property color taskCalendarColor: taskItem.task && taskItem.task.calendarColor ? taskItem.task.calendarColor : Color.muted
    readonly property bool overdue: taskItem.showOverdue && taskItem.task && TaskModel.isOverdue(taskItem.task, tasksView.now)
    readonly property bool hasCalendarName: taskItem.task && taskItem.task.calendarName
    // Guarded here so bindings never index into a null/undefined task. The
    // delegate's task can be cleared while bindings still reference it.
    readonly property bool hasCategories: !!(taskItem.task && Array.isArray(taskItem.task.categories) && taskItem.task.categories.length > 0)
    readonly property string primaryCategory: hasCategories ? String(taskItem.task.categories[0]) : ""
    readonly property real calendarNameAvailableWidth: {
      if (!hasCalendarName) return 0
      var s = metaRow.spacing
      var available = metaRow.width
      available -= calendarIconMetrics.width + s
      if (tagText.visible) {
        available -= separatorMetrics.width + s
        available -= tagIconMetrics.width + s
        available -= tagText.width + s
      }
      // Done tab uses "completed" dates and its delegates are created while the
      // tab container is becoming visible, so the metadata row can still report
      // visible:false during layout. Compute width from the row geometry anyway
      // so the calendar name does not collapse to zero.
      if (dateLabel === "completed") {
        return Math.max(Style.space(8), available + s)
      }
      if (!metaRow.visible) return 0
      return Math.max(0, available + s)
    }
    // Measure the calendar name independently of the delegate's layout state:
    // delegates can be instantiated while their container is hidden — the Done
    // tab hit this first, and since the add form's optimistic create rebuilds
    // the Pending list while it is hidden, every elided Text there latches
    // implicitWidth at 0 too. TextMetrics measures pure text, so it never
    // defers and never latches.
    TextMetrics {
      id: calendarNameMetrics
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      text: taskItem.task ? TaskModel.plainDisplay(taskItem.task.calendarName, 80) : ""
    }
    TextMetrics {
      id: tagTextMetrics
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      text: taskItem.hasCategories ? TaskModel.plainDisplay(taskItem.primaryCategory, 40) : ""
    }
    // Icons and separator are measured too so the whole metadata-row width
    // chain is pure: no width binding reads a Text's implicitWidth, which
    // defers through text-layout polish and can latch at 0 (and drag the
    // row's width bindings into re-entrancy loops) for delegates built
    // while the tab container was hidden.
    TextMetrics {
      id: calendarIconMetrics
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      text: "\uf073"
    }
    TextMetrics {
      id: tagIconMetrics
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      text: "\uf02b"
    }
    TextMetrics {
      id: separatorMetrics
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      text: "\u00B7"
    }

    // "Mon d" this year, "Mon d, YYYY" otherwise — shared by the collapsed
    // date column (backlog tab) and the expanded detail's Created field.
    readonly property string createdText: {
      if (!taskItem.task) return ""
      var d = TaskModel.parseDateTime(taskItem.task.created)
      if (!d) return ""
      var month = TaskModel.SHORT_MONTH_NAMES[d.getMonth()]
      var day = d.getDate()
      var year = d.getFullYear()
      if (year === new Date().getFullYear()) return month + " " + day
      return month + " " + day + ", " + year
    }

    readonly property string dateText: {
      if (!taskItem.task) return ""
      if (taskItem.dateLabel === "completed") return TaskModel.formatCompletedDate(taskItem.task)
      if (taskItem.dateLabel === "created") return taskItem.createdText
      return TaskModel.formatDueDate(taskItem.task)
    }

    // Expanded detail values. All user-sourced strings are re-sanitized at
    // display time (categories bypass plainDisplay during normalization);
    // empty values hide their detail fields.
    readonly property string detailDescriptionText: taskItem.task ? TaskModel.plainDisplay(taskItem.task.description, 2000) : ""
    readonly property string detailCategoriesText: taskItem.task && taskItem.task.categories && taskItem.task.categories.length > 0
      ? TaskModel.plainDisplay(taskItem.task.categories.join(", "), 400) : ""
    readonly property string detailStatusText: taskItem.task ? statusLabel(taskItem.task.status) : ""
    readonly property string detailPriorityText: taskItem.task ? priorityLabel(taskItem.task.priority) : ""
    readonly property string detailDueText: taskItem.task ? TaskModel.formatDueDate(taskItem.task) : ""
    readonly property string detailStartText: taskItem.task ? TaskModel.formatStartDate(taskItem.task) : ""
    readonly property string detailCompletedText: taskItem.task ? TaskModel.formatCompletedDate(taskItem.task) : ""

    // Collapsed rows keep the original one-line height (row + 6 = 3 top /
    // 3 bottom padding). Expanded rows append the detail block: gap above the
    // divider + detail content + extra bottom padding, so the open card is
    // roomier at the bottom than the collapsed row. detailColumn.implicitHeight
    // comes only from wrapped texts laid out with pure parent.width chains —
    // it never depends on this Rectangle's height, so reading it here cannot
    // form a binding loop with the width math.
    height: taskItem.expanded
      ? taskRow.implicitHeight + Style.space(6) + Style.space(4) + detailColumn.implicitHeight + Style.space(3)
      : taskRow.implicitHeight + Style.space(6)
    radius: Style.cornerRadius
    // The detail block hangs below the collapsed content; while the height
    // animates it is revealed inside this clip instead of overflowing onto
    // the next row.
    clip: true
    // statusCompleteMouse sits on top of taskItemMouse over the circle, so it
    // owns the hover grab there; OR it in to keep the row highlighted while
    // the cursor is on the glyph. Expanded rows hold the fill so the open
    // card reads as active even without the cursor over it.
    color: !taskItem.inert && (taskItem.cursor || taskItem.expanded || taskItemMouse.containsMouse || statusCompleteMouse.containsMouse)
      ? Style.hoverFillFor(Color.foreground, Color.accent)
      : "transparent"
    // Keyboard cursor outline.
    border.width: taskItem.cursor ? 1 : 0
    border.color: Color.accent

    // Curtain-reveal for the detail: animating the height opens/closes over
    // the clipped content. Pure retarget of the binding above — the inputs
    // (row implicit height, detail implicit height) never depend on height.
    Behavior on height {
      NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Row {
      id: taskRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      // Top-anchored instead of vertically centered: the expanded detail
      // block anchors below this row. Collapsed appearance is unchanged —
      // height = row + 6 with this space(3) top margin splits into the same
      // 3 top / 3 bottom padding the vertical centering produced.
      anchors.top: parent.top
      anchors.topMargin: Style.space(3)
      spacing: Style.space(6)
      // Filler rows blank their content; geometry — and therefore the row
      // height the page slot relies on — stays identical to real rows.
      opacity: taskItem.inert ? 0 : 1

      Text {
        id: statusIcon
        anchors.verticalCenter: parent.verticalCenter
        visible: !taskItem.inert
        text: taskItem.completed ? "\u2713" : "\u25CB"
        // Completed rows keep the static muted check; pending rows light up
        // accent while the cursor is on the click target to hint "click me".
        color: taskItem.completed ? Color.muted
          : statusCompleteMouse.containsMouse ? Color.accent : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
      }

      Column {
        width: parent.width - statusIcon.width - dateColumn.width - parent.spacing * 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: taskItem.task ? TaskModel.plainDisplay(taskItem.task.title, 200) : ""
          color: taskItem.overdue ? Color.urgent : Color.foreground
          // Wide view wraps long titles; the normal list keeps them on one line.
          wrapMode: tasksView.wideMode ? Text.WordWrap : Text.NoWrap
          elide: tasksView.wideMode ? Text.ElideNone : Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: taskItem.overdue
          font.strikeout: taskItem.completed
          textFormat: Text.PlainText
        }

        Row {
          id: metaRow
          width: parent.width
          spacing: Style.space(1)

          Text {
            id: calendarIcon
            visible: taskItem.hasCalendarName
            width: visible ? calendarIconMetrics.width : 0
            text: "\uf073"
            color: taskItem.taskCalendarColor
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }

          Text {
            id: calendarNameText
            visible: taskItem.hasCalendarName
            // Content-sized first block: take only the width the calendar name
            // needs, but elide when the tag block leaves less room than that.
            // Measured via TextMetrics for both tabs: implicitWidth latches at
            // 0 for delegates created while the tab container is hidden.
            width: {
              if (!visible) return 0
              return Math.max(0, Math.min(calendarNameMetrics.width, taskItem.calendarNameAvailableWidth))
            }
            text: taskItem.task ? TaskModel.plainDisplay(taskItem.task.calendarName, 80) : ""
            color: taskItem.taskCalendarColor
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }

          Text {
            id: separatorDot
            visible: calendarNameText.visible && tagText.visible
            width: visible ? separatorMetrics.width : 0
            anchors.verticalCenter: parent.verticalCenter
            text: "\u00B7"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }

          Text {
            id: tagIcon
            visible: tagText.visible
            width: visible ? tagIconMetrics.width : 0
            text: "\uf02b"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }

          Text {
            id: tagText
            visible: taskItem.hasCategories
            // Same TextMetrics reasoning as the calendar name: implicitWidth
            // latches at 0 for delegates built while the tab was hidden.
            width: visible ? Math.max(0, Math.min(tagTextMetrics.width, parent.width * 0.45 - tagIcon.width - parent.spacing)) : 0
            text: visible ? TaskModel.plainDisplay(taskItem.primaryCategory, 40) : ""
            color: Color.muted
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
        }
      }

      Column {
        id: dateColumn
        anchors.verticalCenter: parent.verticalCenter

        Text {
          visible: taskItem.dateText !== ""
          text: taskItem.dateText
          color: taskItem.overdue ? Color.urgent : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: taskItem.overdue
          textFormat: Text.PlainText
        }
      }
    }

    // Row toggle: expands/collapses the detail block. Declared BEFORE
    // detailColumn so the interactive delete footer inside it stacks on top;
    // the detail's plain texts accept no clicks or hover, so clicks over them
    // fall through to here and still collapse the row. The status circle's
    // MouseArea is declared after everything else, so completing from the
    // glyph still wins there and a circle click never toggles expansion.
    MouseArea {
      id: taskItemMouse
      anchors.fill: parent
      hoverEnabled: true
      // Filler rows are dead space: no expansion, no hover, no cursor.
      enabled: !taskItem.inert
      cursorShape: Qt.PointingHandCursor
      onClicked: taskItem.toggleExpanded()
    }

    // Expanded task detail, hanging below the collapsed row and indented to
    // the title column (past the status glyph — the same statusIcon.width the
    // collapsed width chain already reads). The column stays laid out at all
    // times and is revealed by opacity; collapsed rows clip it away, and the
    // footer button is disabled while collapsed because opacity does not
    // block hit-testing. All widths are parent.width + wrapMode — no binding
    // reads an implicitWidth of a Text that could have been built while its
    // tab container was hidden, so no width chain can latch at 0.
    Column {
      id: detailColumn
      anchors.left: taskRow.left
      anchors.right: taskRow.right
      anchors.top: taskRow.bottom
      anchors.topMargin: Style.space(4)
      anchors.leftMargin: statusIcon.width + taskRow.spacing
      spacing: Style.space(4)
      opacity: taskItem.expanded ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Util.alpha(Color.foreground, 0.15)
      }

      TaskDetailField {
        width: parent.width
        label: "Description"
        value: taskItem.detailDescriptionText
        prominent: true
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        TaskDetailField {
          width: (parent.width - parent.spacing) / 2
          label: "Status"
          value: taskItem.detailStatusText
        }

        TaskDetailField {
          width: (parent.width - parent.spacing) / 2
          label: "Priority"
          value: taskItem.detailPriorityText
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        TaskDetailField {
          width: (parent.width - parent.spacing) / 2
          label: "Calendar"
          value: taskItem.task ? TaskModel.plainDisplay(taskItem.task.calendarName, 120) : ""
          valueColor: taskItem.taskCalendarColor
        }

        TaskDetailField {
          width: (parent.width - parent.spacing) / 2
          label: "Due"
          value: taskItem.detailDueText
        }
      }

      Row {
        visible: taskItem.detailStartText !== ""
        width: parent.width
        spacing: Style.space(6)

        TaskDetailField {
          width: (parent.width - parent.spacing) / 2
          label: "Starts by"
          value: taskItem.detailStartText
        }
      }

      TaskDetailField {
        width: parent.width
        label: "Categories"
        value: taskItem.detailCategoriesText
      }

      Row {
        // Hide the whole row when neither timestamp exists so the detail
        // column skips it (and its spacing) instead of leaving an empty gap.
        visible: taskItem.createdText !== "" || taskItem.detailCompletedText !== ""
        width: parent.width
        spacing: Style.space(6)

        TaskDetailField {
          width: (parent.width - parent.spacing) / 2
          label: "Created"
          value: taskItem.createdText
        }

        TaskDetailField {
          width: (parent.width - parent.spacing) / 2
          label: "Completed"
          value: taskItem.detailCompletedText
        }
      }

      // Footer actions. The completion toggle (left, accent) is reversible —
      // single click, same one-click contract as the status circle, plus the
      // only way back for completed rows whose circle is disabled. The
      // destructive delete (right, urgent) keeps its two-step confirm. Each
      // button anchors to its outer edge, so a label swap never shifts the
      // click target away from the cursor. Both are disabled while the row
      // is collapsed: the detail is revealed by opacity, and opacity does
      // not block hit-testing, so hidden controls must never take input.
      Item {
        width: parent.width
        height: Math.max(completionButton.height, deleteTaskButton.height) + Style.space(2)

        // Label/icon are driven by the case-insensitive completed check, not
        // the tab, so the same affordance generalizes across Pending and Done.
        Button {
          id: completionButton
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: taskItem.completed ? "Not Completed" : "Completed"
          iconText: taskItem.completed ? "\uf0e2" : "\uf00c"
          tooltipText: taskItem.completed ? "Mark as not completed" : "Mark as completed"
          foreground: Color.accent
          bordered: true
          enabled: taskItem.expanded && tasksView.taskService
          onClicked: taskItem.toggleComplete()
        }

        Button {
          id: editTaskButton
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          text: "Edit"
          iconText: "\uf040"
          tooltipText: "Edit this task"
          foreground: Color.accent
          bordered: true
          enabled: taskItem.expanded && tasksView.taskService
          onClicked: taskItem.requestEdit()
        }

        // Destructive delete: the first click arms (the label swaps to an
        // explicit confirm), a second click fires the delete. Arming expires
        // via deleteArmTimer, and collapse or a model rebuild disarms. Kept
        // compact and right-aligned so the irreversible target stays small
        // and out of the reading flow.
        Button {
          id: deleteTaskButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: taskItem.deleteArmed ? "Confirm delete?" : "Delete"
          iconText: "\uf1f8"
          tooltipText: taskItem.deleteArmed ? "Click again to delete this task" : "Delete this task"
          foreground: Color.urgent
          bordered: true
          // Like the calendar-toggle guard: one in-flight delete at a time
          // service-wide. The expanded gate also keeps the opacity-hidden
          // detail from catching clicks aimed at the next row while this row
          // is collapsed (opacity does not block hit-testing).
          enabled: taskItem.expanded && tasksView.taskService && !tasksView.taskService.pendingDeleteUid
          onClicked: taskItem.requestDelete()
        }
      }
    }

    // Circle click target: completes a pending task. The glyph itself is the
    // first child of taskRow (x = 0 within the row), so anchoring the target
    // to taskRow's left edge pins it over the glyph. Fixed 18x18 size gives a
    // comfortable hit target without changing the row height or the width
    // math that reads statusIcon.width. Declared after taskItemMouse so it is
    // on top and receives clicks/hover over the circle.
    MouseArea {
      id: statusCompleteMouse
      anchors.left: taskRow.left
      anchors.verticalCenter: taskRow.verticalCenter
      width: Style.space(18)
      height: Style.space(18)
      hoverEnabled: true
      enabled: taskItem.task && !taskItem.completed && !taskItem.inert
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (!tasksView.taskService || !taskItem.task) return
        tasksView.debugLog("action: complete task " + taskItem.task.uid)
        tasksView.taskService.completeTask(taskItem.task)
      }
    }

    // Collapse always disarms the delete confirm (and stops its timer); a
    // model rebuild replaces the delegate and drops the state for free.
    onExpandedChanged: {
      if (taskItem.expanded) return
      taskItem.deleteArmed = false
      deleteArmTimer.stop()
    }

    Timer {
      id: deleteArmTimer
      interval: 4000
      onTriggered: taskItem.deleteArmed = false
    }
  }

  // One label/value pair inside the expanded task detail: small muted
  // caption label above the value — the same pattern AddFormField uses. The
  // field hides itself when its value is empty, and every width is
  // parent.width + wrapMode so nothing here can feed an implicitWidth latch
  // for delegates built while their tab container was hidden.
  component TaskDetailField: Column {
    id: taskDetailField
    property string label: ""
    property string value: ""
    property bool prominent: false
    property color valueColor: Color.foreground

    visible: taskDetailField.value !== ""
    width: parent.width
    spacing: Style.space(1)

    Text {
      width: parent.width
      text: taskDetailField.label
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      textFormat: Text.PlainText
    }

    Text {
      width: parent.width
      text: taskDetailField.value
      color: taskDetailField.valueColor
      wrapMode: Text.Wrap
      font.family: Style.font.family
      font.pixelSize: taskDetailField.prominent ? Style.font.bodySmall : Style.font.caption
      textFormat: Text.PlainText
    }
  }

  component SettingsCalendarRow: Row {
    id: settingsCalendarRow
    property var calendar: ({})
    property int calendarIndex: 0
    // Keyboard cursor is on this row.
    property bool cursor: false
    // Swatch highlighted while the palette is open (keyboard or mouse).
    property int paletteIndex: 0

    width: parent ? parent.width : 0
    spacing: Style.space(8)
    height: Style.spacing.controlHeight

    readonly property string calendarId: calendar && calendar.id ? calendar.id : ""
    readonly property string sourceLabel: TaskModel.providerLabel(calendar ? calendar.provider : "", calendar ? calendar.host : "") + (calendar && calendar.readonly ? " · read-only" : "")
    readonly property string currentName: TaskModel.calendarDisplayName(calendar, {})
    readonly property bool toggleable: TaskModel.canToggleCalendar(calendar)
    // Absent/undefined enabled counts as enabled; only an explicit false
    // dims the row and flips the button to "Enable".
    readonly property bool calendarDisabled: calendar && calendar.enabled === false
    // Resolved dot color: color override -> provider color -> stable palette slot.
    readonly property string currentColor: TaskModel.calendarDisplayColor(calendar, {}, calendarIndex)
    // A color write is in flight for this row / anywhere in the service.
    readonly property bool colorPending: calendarService && calendarService.pendingColorId === calendarId
    readonly property bool colorBusy: calendarService && calendarService.pendingColorId !== ""
    // Non-toggleable calendars stay display-only dots; also serialized like
    // the toggle button: no pick starts while any color write is in flight.
    readonly property bool pickable: toggleable && !colorBusy

    function toggleEnabled() {
      if (!toggleable || !calendarService || calendarService.pendingToggleId) return
      debugLog("action: " + (calendarDisabled ? "enable" : "disable") + " calendar " + calendarId)
      calendarService.setCalendarEnabled(calendarId, calendarDisabled)
    }

    function openPalette() {
      if (!pickable) return
      colorPopup.open()
    }

    function closePalette() { colorPopup.close() }

    function movePalette(delta) {
      var count = TaskModel.DEFAULT_CALENDAR_COLORS.length
      paletteIndex = (paletteIndex + delta + count) % count
    }

    function pickPalette() {
      if (colorBusy) return
      if (calendarService) calendarService.setCalendarColor(calendarId, TaskModel.DEFAULT_CALENDAR_COLORS[paletteIndex])
      colorPopup.close()
    }

    Rectangle {
      width: Style.space(22)
      height: Style.space(22)
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: settingsCalendarRow.currentColor || Color.accent
      border.width: 1
      // Hover brightens the ring so the dot reads as a clickable control.
      border.color: swatchMouse.enabled && swatchMouse.hovered ? Color.foreground : Util.alpha(Color.foreground, 0.35)
      // Quiet busy cue while this row's color write is in flight.
      opacity: settingsCalendarRow.colorPending ? 0.55 : 1.0

      MouseArea {
        id: swatchMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: settingsCalendarRow.pickable
        onClicked: colorPopup.open()
      }

      Popup {
        id: colorPopup
        padding: Style.space(6)
        modal: false
        dim: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        // Keys keep flowing through the panel's dispatcher (palette context)
        // instead of the popup, so tell the view which row owns them.
        onOpened: {
          var current = -1
          for (var i = 0; i < TaskModel.DEFAULT_CALENDAR_COLORS.length; i++) {
            if (TaskModel.colorsMatch(TaskModel.DEFAULT_CALENDAR_COLORS[i], settingsCalendarRow.currentColor)) { current = i; break }
          }
          settingsCalendarRow.paletteIndex = Math.max(0, current)
          tasksView.activePalette = settingsCalendarRow
        }
        onClosed: {
          if (tasksView.activePalette === settingsCalendarRow) tasksView.activePalette = null
          tasksView.focusPanel()
        }

        // Below the swatch by default; flip above when the row sits near the
        // bottom of the panel so the palette never opens off-surface.
        onAboutToShow: {
          var gap = Style.space(4)
          var need = implicitHeight + gap
          var sceneY = settingsCalendarRow.mapToItem(null, 0, 0).y
          var winHeight = tasksView.Window.window ? tasksView.Window.window.height : 0
          y = winHeight - sceneY < need + parent.height + Style.space(12) ? -need : parent.height + gap
        }

        background: Rectangle {
          color: Color.popups.background
          border.color: Color.accent
          border.width: 1
          radius: Style.cornerRadius
        }

        contentItem: Flow {
          spacing: Style.space(6)

          Repeater {
            model: TaskModel.DEFAULT_CALENDAR_COLORS

            Rectangle {
              required property var modelData
              required property int index
              readonly property bool keyboardCurrent: tasksView.activePalette === settingsCalendarRow && settingsCalendarRow.paletteIndex === index
              width: Style.space(16)
              height: Style.space(16)
              radius: width / 2
              color: modelData
              border.width: keyboardCurrent || TaskModel.colorsMatch(modelData, settingsCalendarRow.currentColor) ? 2 : 1
              border.color: keyboardCurrent ? Color.accent
                : TaskModel.colorsMatch(modelData, settingsCalendarRow.currentColor) ? Color.foreground
                : Util.alpha(Color.foreground, 0.35)

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                // Serialized: ignore picks while any color write is in flight.
                enabled: !settingsCalendarRow.colorBusy
                onClicked: {
                  if (calendarService) calendarService.setCalendarColor(settingsCalendarRow.calendarId, parent.modelData)
                  colorPopup.close()
                }
              }
            }
          }
        }
      }

      // Panel hide must not leave the palette logically open, or the next
      // open would surface a stale popup over the config tab.
      Connections {
        target: tasksView
        function onOpenedChanged() {
          if (!tasksView.opened && colorPopup.opened) colorPopup.close()
        }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: settingsCalendarRow.currentName
      color: settingsCalendarRow.cursor ? Color.accent : settingsCalendarRow.calendarDisabled ? Color.muted : Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: settingsCalendarRow.cursor
      textFormat: Text.PlainText
    }

    Text {
      id: sourceText
      anchors.verticalCenter: parent.verticalCenter
      text: settingsCalendarRow.sourceLabel
      textFormat: Text.PlainText
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Item {
      width: Math.max(Style.space(8), parent.width - Style.space(222) - sourceText.implicitWidth - (settingsCalendarRow.toggleable ? toggleCalendarButton.implicitWidth : 0) - parent.spacing * (settingsCalendarRow.toggleable ? 4 : 3))
      height: 1
    }

    Button {
      id: toggleCalendarButton
      visible: settingsCalendarRow.toggleable
      // Serialized service-wide: no row's button acts while any toggle is
      // in flight; the pending row reads "Updating..." while it waits.
      enabled: calendarService && !calendarService.pendingToggleId
      anchors.verticalCenter: parent.verticalCenter
      text: calendarService && calendarService.pendingToggleId === settingsCalendarRow.calendarId ? "Updating..." : settingsCalendarRow.calendarDisabled ? "Enable" : "Disable"
      bordered: true
      hasCursor: settingsCalendarRow.cursor
      onClicked: settingsCalendarRow.toggleEnabled()
    }
  }

  // Labeled form row for the add-task view: small muted caption above, then
  // whatever control(s) the caller injects (field, helper text, picker...).
  component AddFormField: Column {
    id: addFormField
    default property alias contentData: addFormFieldContent.data
    property string label: ""

    width: parent ? parent.width : 0
    spacing: Style.space(4)

    Text {
      width: parent.width
      text: addFormField.label
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      textFormat: Text.PlainText
    }

    Column {
      id: addFormFieldContent
      width: parent.width
      spacing: Style.space(4)
    }
  }

  // Typed date field with a picker button beside it. The text is the
  // editable view of `keyValue` (a day key). The text is committed on Enter,
  // on focus loss, and before submit. The picker button and Ctrl+D / Ctrl+T
  // open the shared month grid for this field.
  component AddDateInput: Row {
    id: dateInput
    property string target: "due"
    property string keyValue: ""
    property string errorText: ""
    readonly property alias field: dateField
    readonly property alias pickerButton: pickButton
    readonly property bool pickerOpen: addTaskView.duePickerOpen && addTaskView.pickerTarget === target

    width: parent ? parent.width : 0
    spacing: Style.space(4)

    // Rewrite the text from the key. Skipped while the user is typing unless forced.
    function syncText(force) {
      if (!force && dateField.activeFocus) return
      if (force) errorText = ""
      dateField.text = TaskModel.formatDateInput(keyValue, addTaskView.datePattern)
    }

    onKeyValueChanged: syncText(false)

    TextField {
      id: dateField
      Keys.forwardTo: tasksView.keyForward
      Keys.onTabPressed: function(event) { addTaskView.formStep(1); event.accepted = true }
      Keys.onBacktabPressed: function(event) { addTaskView.formStep(-1); event.accepted = true }
      Keys.onEscapePressed: function(event) {
        addTaskView.escapeAdd()
        event.accepted = true
      }
      width: dateInput.width - pickButton.width - dateInput.spacing
        - (clearButton.visible ? clearButton.width + dateInput.spacing : 0)
      placeholderText: TaskModel.dateInputHint(addTaskView.datePattern)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      onAccepted: addTaskView.commitDateInput(dateInput.target)
      onActiveFocusChanged: {
        if (activeFocus) {
          // Typing takes over from the grid.
          if (addTaskView.duePickerOpen) addTaskView.duePickerOpen = false
        } else {
          addTaskView.commitDateInput(dateInput.target)
        }
      }
    }

    Button {
      id: pickButton
      Keys.forwardTo: tasksView.keyForward
      focusable: true
      bordered: true
      iconText: "\uf073"
      foreground: dateInput.keyValue !== "" ? Color.accent : Color.foreground
      tooltipText: dateInput.pickerOpen ? "Hide date picker" : "Pick a date"
      onClicked: addTaskView.toggleDuePicker(dateInput.target)
    }

    Button {
      id: clearButton
      visible: dateField.text !== "" || dateInput.keyValue !== ""
      text: "\u2715"
      tooltipText: "Remove date"
      fontSize: Style.font.caption
      onClicked: addTaskView.clearDate(dateInput.target)
    }
  }

  // One day cell of the due-date mini calendar. `cell` is fed from the
  // Repeater's modelData at the use site; only instantiated under the
  // AddDuePicker, so the `dueGrid` scope reference is always resolvable.
  component AddDueCell: Rectangle {
    id: dueCell
    property var cell: null

    readonly property bool picked: dueCell.cell ? dueCell.cell.selected : false
    readonly property bool dimmed: dueCell.cell ? !dueCell.cell.inMonth : true

    width: dueGrid.cellSize
    height: dueGrid.cellSize
    radius: Style.cornerRadius
    color: cellMouse.pressed ? Style.pressedFillFor(Color.foreground, Color.accent)
      : picked ? Style.selectedFillFor(Color.foreground, Color.accent)
      : cellMouse.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent)
      : "transparent"
    readonly property bool cursor: dueCell.cell ? dueCell.cell.cursor === true && tasksView.keyContext === "picker" : false
    border.width: dueCell.cursor ? 2 : dueCell.cell && dueCell.cell.today && !picked ? 1 : 0
    border.color: Color.accent

    Text {
      anchors.centerIn: parent
      text: dueCell.cell ? dueCell.cell.day : ""
      color: dueCell.picked ? Style.selectedStateColor(Color.foreground, Color.accent)
        : dueCell.dimmed ? Util.alpha(Color.foreground, 0.35)
        : Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: dueCell.picked || (dueCell.cell && dueCell.cell.today)
      textFormat: Text.PlainText
    }

    MouseArea {
      id: cellMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: dueCell.cell ? dueCell.cell.inMonth : false
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (!dueCell.cell) return
        dueGrid.pickCell(dueCell.cell)
      }
    }
  }

  // Compact month grid for the due-date field: Monday-first, today ringed,
  // selected day filled, prev/next month plus a Today jump. Stays narrow
  // enough for the panel card on small screens.
  component AddDuePicker: Column {
    id: dueGrid
    property int viewYear: 0
    property int viewMonth: 0
    property bool popupOpen: visible
    // Day the keyboard cursor is on (due key), shown with an accent outline.
    property string cursorKey: ""

    readonly property real cellGap: Style.space(2)
    readonly property real cellSize: Math.max(Style.space(12), Math.floor((width - cellGap * 6) / 7))
    readonly property int leadingDays: viewYear > 0 ? (new Date(viewYear, viewMonth, 1).getDay() + 6) % 7 : 0
    readonly property int daysInMonth: viewYear > 0 ? new Date(viewYear, viewMonth + 1, 0).getDate() : 0
    readonly property int rowCount: Math.ceil((leadingDays + daysInMonth) / 7)
    readonly property string monthLabel: viewYear > 0 ? TaskModel.MONTH_NAMES[viewMonth] + " " + viewYear : ""
    readonly property var weekdayLabels: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    readonly property var cells: {
      var out = []
      if (viewYear <= 0) return out
      var leading = (new Date(viewYear, viewMonth, 1).getDay() + 6) % 7
      var cursor = new Date(viewYear, viewMonth, 1 - leading)
      var today = addTaskView.dueKeyForDate(tasksView.now)
      for (var i = 0; i < rowCount * 7; i++) {
        var cellYear = cursor.getFullYear()
        var cellMonth = cursor.getMonth()
        var cellDay = cursor.getDate()
        var key = addTaskView.dueKeyFor(cellYear, cellMonth, cellDay)
        out.push({
          key: key,
          day: cellDay,
          inMonth: cellMonth === viewMonth && cellYear === viewYear,
          today: key === today,
          selected: key === addTaskView.activeKey(),
          cursor: key === cursorKey
        })
        cursor.setDate(cursor.getDate() + 1)
      }
      return out
    }
    readonly property var cellRows: {
      var rows = []
      var all = cells
      for (var r = 0; r < rowCount; r++) rows.push(all.slice(r * 7, r * 7 + 7))
      return rows
    }

    function stepMonth(delta) {
      var target = new Date(viewYear, viewMonth + delta, 1)
      viewYear = target.getFullYear()
      viewMonth = target.getMonth()
    }

    function showToday() {
      viewYear = tasksView.now.getFullYear()
      viewMonth = tasksView.now.getMonth()
    }

    // --- Keyboard cursor ---
    function followCursor(date) {
      cursorKey = addTaskView.dueKeyForDate(date)
      viewYear = date.getFullYear()
      viewMonth = date.getMonth()
    }

    function cursorDate() {
      return addTaskView.parseDueKey(cursorKey) || new Date(tasksView.now)
    }

    function moveDays(delta) {
      var date = cursorDate()
      date.setDate(date.getDate() + delta)
      followCursor(date)
    }

    // Month steps keep the day number where the month is long enough, else
    // land on its last day (Jan 31 + 1 month = Feb 28/29).
    function moveMonths(delta) {
      var date = cursorDate()
      var day = date.getDate()
      date.setDate(1)
      date.setMonth(date.getMonth() + delta)
      var last = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate()
      date.setDate(Math.min(day, last))
      followCursor(date)
    }

    function cursorToday() {
      followCursor(new Date(tasksView.now))
    }

    function pickCursor() {
      pickCell({ key: cursorKey })
    }

    // Handles a day-cell click on behalf of the cell (the cell's inline
    // component scope cannot see the add view's ids directly).
    function pickCell(cell) {
      if (!cell) return
      debugLog("action: pick " + addTaskView.pickerTarget + " date " + cell.key)
      addTaskView.setActiveKey(cell.key)
      addTaskView.closeDuePicker()
    }

    width: parent ? parent.width : 0
    spacing: Style.space(2)
    focus: visible

    onVisibleChanged: {
      if (visible) syncToActive()
    }

    // Re-anchor on the active field's date (also used when the picker stays
    // open and switches from one field to the other).
    function syncToActive() {
      var anchor = addTaskView.parseDueKey(addTaskView.activeKey())
      if (!anchor) anchor = new Date(tasksView.now)
      viewYear = anchor.getFullYear()
      viewMonth = anchor.getMonth()
      cursorKey = addTaskView.dueKeyForDate(anchor)
      forceActiveFocus()
    }

    Keys.onEscapePressed: function(event) {
      addTaskView.closeDuePicker()
      event.accepted = true
    }

    Item {
      width: parent.width
      height: Style.spacing.controlHeight

      Row {
        anchors.centerIn: parent
        spacing: Style.space(2)

        Button {
          text: "\uf104"
          tooltipText: "Previous month"
          fontSize: Style.font.caption
          onClicked: dueGrid.stepMonth(-1)
        }

        Text {
          width: Style.space(110)
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignHCenter
          text: dueGrid.monthLabel
          color: Color.foreground
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          textFormat: Text.PlainText
        }

        Button {
          text: "\uf105"
          tooltipText: "Next month"
          fontSize: Style.font.caption
          onClicked: dueGrid.stepMonth(1)
        }
      }

      Button {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Today"
        tooltipText: "Jump to current month"
        fontSize: Style.font.caption
        onClicked: dueGrid.showToday()
      }
    }

    Row {
      spacing: dueGrid.cellGap

      Repeater {
        model: dueGrid.weekdayLabels

        Text {
          required property var modelData
          width: dueGrid.cellSize
          horizontalAlignment: Text.AlignHCenter
          text: modelData
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          textFormat: Text.PlainText
        }
      }
    }

    Repeater {
      model: dueGrid.cellRows

      Row {
        required property var modelData
        spacing: dueGrid.cellGap

        Repeater {
          model: modelData

          AddDueCell {
            required property var modelData
            cell: modelData
          }
        }
      }
    }
  }

  // --- Content ---

  // Error message
  Text {
    visible: taskService && taskService.tasksStatus === "error"
    width: parent.width
    text: taskService ? taskService.tasksErrorMessage : ""
    textFormat: Text.PlainText
    color: Color.urgent
    wrapMode: Text.WordWrap
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  Text {
    visible: tasksView.editError !== "" && tasksView.activeTab !== "add"
    width: parent.width
    text: tasksView.editError
    color: Color.urgent
    wrapMode: Text.WordWrap
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
  }

  // Loading indicator
  Text {
    visible: taskService && taskService.tasksStatus === "loading"
    width: parent.width
    text: "Loading tasks..."
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
  }

  // Filter bar ("/"): narrows both list tabs. Enter keeps the filter and
  // returns to the list; Esc once leaves the field, Esc again clears it.
  TextField {
    id: filterField
    Keys.forwardTo: tasksView.keyForward
    visible: (tasksView.filterOpen || tasksView.filterActive)
      && (tasksView.activeTab === "pending" || tasksView.activeTab === "done")
    width: parent.width
    placeholderText: "Filter tasks (Enter to keep, Esc to clear)"
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    onAccepted: {
      filterField.focus = false
      tasksView.focusPanel()
    }
  }

  // Invisible measurement of the wide column header (its height is read).
  Text {
    id: wideHeaderProbe
    visible: false
    text: "Upcoming 1/1"
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.bold: true
  }
  // Invisible measurements for the wide row estimate: one line of body text
  // (its height is the line height) and the status glyph (its width).
  Text {
    id: wideLineProbe
    visible: false
    text: "A\nA"
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
  }
  Text {
    id: wideStatusProbe
    visible: false
    text: "\u2713\u25CB"
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
  }
  readonly property real wideLineHeight: wideLineProbe.contentHeight / 2
  // Both glyphs side by side: an upper bound, so the title never gets too wide.
  readonly property real wideStatusWidth: wideStatusProbe.implicitWidth
  // Invisible measurement of one collapsed row (its height gives the row pitch).
  TaskItem {
    id: wideRowProbe
    visible: false
    width: tasksView.wideColumnWidth
    task: ({ id: "", title: "Row", calendarName: "Calendar", status: "NEEDS-ACTION" })
    dateLabel: "due"
  }
  // Pending tab content
  Column {
    id: pendingColumn
    visible: tasksView.activeTab === "pending" && !tasksView.wideMode
    width: parent.width
    spacing: Style.space(12)

    TaskSection {
      id: upcomingSection
      title: "Upcoming"
      count: tasksView.filterActive ? tasks.length : TaskModel.upcomingTaskCount(tasksView.allTasks)
      tasks: TaskModel.filterTasks(TaskModel.allUpcomingTasks(tasksView.allTasks), tasksView.filterText)
      emptyText: tasksView.filterActive ? "No matching tasks" : "No upcoming tasks"
      dateLabel: "due"
      showOverdue: true
    }

    TaskSection {
      id: backlogSection
      title: "Backlog"
      count: tasksView.filterActive ? tasks.length : TaskModel.backlogTaskCount(tasksView.allTasks)
      tasks: TaskModel.filterTasks(TaskModel.backlogTasks(tasksView.allTasks), tasksView.filterText)
      emptyText: tasksView.filterActive ? "No matching tasks" : "No backlog tasks"
      dateLabel: "created"
      showOverdue: false
    }
  }

  // Wide view: every page of Upcoming and Backlog as columns, scrolled
  // horizontally so the cursor's column stays in view.
  Item {
    id: wideBlock
    width: parent.width
    height: tasksView.wideAvailableHeight
    visible: tasksView.activeTab === "pending" && tasksView.wideMode
    Flickable {
      id: wideStrip
      anchors.fill: parent
      clip: true
      contentWidth: wideRow.width
      contentHeight: height
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.HorizontalFlick
      ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
      Row {
        id: wideRow
        height: wideStrip.height
        spacing: Style.space(12)
        WidePages {
          id: wideUpcoming
          section: upcomingSection
        }
        Rectangle {
          width: 1
          height: wideRow.height
          color: Color.muted
        }
        WidePages {
          id: wideBacklog
          section: backlogSection
        }
        Rectangle {
          width: 1
          height: wideRow.height
          color: Color.muted
          visible: tasksView.wideDoneFit > 0
        }
        WidePages {
          id: wideDone
          section: doneSection
          visible: tasksView.wideDoneFit > 0
        }
      }
    }
  }
  // Done tab content
  Column {
    visible: tasksView.activeTab === "done"
    width: parent.width
    spacing: Style.space(12)

    TaskSection {
      id: doneSection
      title: "Completed"
      count: tasksView.filterActive ? tasks.length : TaskModel.doneTaskCount(tasksView.allTasks)
      tasks: TaskModel.filterTasks(TaskModel.allDoneTasks(tasksView.allTasks), tasksView.filterText)
      // Roomier page: the done tab stacks one section, so 10 rows (~430px)
      // still fits the fixed panel height where two 5-row sections do.
      pageSize: 10
      maxWidePages: tasksView.wideDoneFit
      emptyText: tasksView.filterActive ? "No matching tasks" : "No completed tasks"
      dateLabel: "completed"
      showOverdue: false
    }
  }

  // Config tab content
  Column {
    visible: tasksView.activeTab === "config"
    width: parent.width
    spacing: Style.space(8)

    Column {
      width: parent.width
      spacing: Style.space(4)

      Text {
        width: parent.width
        text: "Calendars"
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Color.accent
      }
    }

    Repeater {
      id: calendarRows
      model: calendarService ? calendarService.calendars : []

      SettingsCalendarRow {
        required property var modelData
        required property int index
        width: parent ? parent.width : 0
        calendar: modelData
        calendarIndex: index
        cursor: tasksView.configCursorKind === "calendar" && tasksView.configIndex === index
      }
    }

    Text {
      visible: !calendarService || !calendarService.calendars || calendarService.calendars.length === 0
      width: parent.width
      text: "No calendars configured"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
    }

    // Enable/disable failure feedback, mirroring the connect form's error
    // line; the service clears it on the next successful toggle.
    Text {
      readonly property string message: calendarService && calendarService.toggleError ? calendarService.toggleError : ""
      visible: message !== ""
      width: parent.width
      text: message
      color: Color.urgent
      wrapMode: Text.WordWrap
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
    }

    // Color-pick failure feedback, same line style as the toggle error; the
    // service clears it on the next pick attempt.
    Text {
      readonly property string message: calendarService && calendarService.colorError ? calendarService.colorError : ""
      visible: message !== ""
      width: parent.width
      text: message
      color: Color.urgent
      wrapMode: Text.WordWrap
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
    }

    // Connected servers summary: one display-only row per distinct
    // plugin-managed CalDAV host, hidden until a server exists.
    Column {
      visible: tasksView.serverConnections.length > 0
      width: parent.width
      spacing: Style.space(4)

      Text {
        width: parent.width
        text: "Servers"
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        textFormat: Text.PlainText
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Color.accent
      }

      Repeater {
        model: tasksView.serverConnections

        Row {
          id: serverRow
          required property var modelData

          width: parent ? parent.width : 0
          spacing: Style.space(8)
          height: Style.spacing.controlHeight

          // Brand label for the host ("Fastmail"); falls back to the raw
          // host if the provider map ever yields nothing.
          readonly property string hostLabel: {
            var label = TaskModel.providerLabel("caldav", serverRow.modelData ? serverRow.modelData.host : "")
            return label !== "" ? label : String(serverRow.modelData && serverRow.modelData.host ? serverRow.modelData.host : "")
          }
          // The actual server address, always shown next to the brand label
          // even when the brand was derived from the same host.
          readonly property string hostAddress: serverRow.modelData && serverRow.modelData.host ? String(serverRow.modelData.host) : ""
          readonly property string calendarsLabel: serverRow.modelData
            ? String(serverRow.modelData.count) + (serverRow.modelData.count === 1 ? " calendar" : " calendars")
            : ""

          // The host column flexes to whatever width the brand and count
          // labels leave and elides long addresses, so the row can never
          // overflow the panel. Both neighbors are measured with TextMetrics
          // so the width chain never reads a Text implicitWidth, which can
          // defer or latch at 0 for delegates built while the config
          // container is hidden (same reasoning as TaskItem).
          TextMetrics {
            id: serverBrandMetrics
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            text: serverRow.hostLabel
          }

          TextMetrics {
            id: serverCountMetrics
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            text: serverRow.calendarsLabel
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: serverRow.hostLabel
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }

          Text {
            width: Math.max(0, serverRow.width - serverBrandMetrics.width - serverCountMetrics.width - serverRow.spacing * 2)
            anchors.verticalCenter: parent.verticalCenter
            text: serverRow.hostAddress
            color: Color.muted
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: serverRow.calendarsLabel
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
        }
      }
    }

    Button {
      id: connectServerButton
      visible: !caldavForm.visible
      text: "Connect Server"
      bordered: true
      hasCursor: tasksView.configCursorKind === "connect"
      onClicked: tasksView.openCaldavForm()
    }

    Column {
      id: caldavForm
      visible: false
      width: parent.width
      spacing: Style.space(8)

      Text {
        width: parent.width
        text: "CalDAV Server"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      TextField {
        id: caldavUrlField
        Keys.forwardTo: tasksView.keyForward
        width: parent.width
        placeholderText: "https://caldav.example.com/dav/"
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        onAccepted: caldavUsernameField.forceActiveFocus()
      }

      TextField {
        id: caldavUsernameField
        Keys.forwardTo: tasksView.keyForward
        width: parent.width
        placeholderText: "Username"
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        onAccepted: caldavPasswordField.forceActiveFocus()
      }

      TextField {
        id: caldavPasswordField
        Keys.forwardTo: tasksView.keyForward
        width: parent.width
        placeholderText: "Password"
        password: true
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        onAccepted: tasksView.submitCaldav()
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Button {
          text: calendarService && calendarService.caldavSetupStatus === "connecting" ? "Connecting..." : "Connect"
          bordered: true
          enabled: calendarService && calendarService.caldavSetupStatus !== "connecting"
          onClicked: tasksView.submitCaldav()
        }

        Button {
          text: "Cancel"
          enabled: !calendarService || calendarService.caldavSetupStatus !== "connecting"
          onClicked: {
            debugLog("action: caldav form cancel")
            tasksView.closeCaldavForm()
          }
        }
      }

      Text {
        visible: calendarService && calendarService.caldavSetupStatus === "connecting"
        width: parent.width
        text: "Connecting to CalDAV server..."
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
      }

      Text {
        visible: calendarService && calendarService.caldavSetupStatus === "error"
        width: parent.width
        text: calendarService ? calendarService.caldavSetupMessage : ""
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
      }

      Text {
        visible: calendarService && calendarService.caldavSetupStatus === "success"
        width: parent.width
        text: "Connected successfully"
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
      }

      // Let the success confirmation register briefly, then dismiss the form
      // so the refreshed calendar list is visible again.
      Timer {
        id: caldavSuccessCloseTimer
        interval: 1200
        onTriggered: tasksView.closeCaldavForm()
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(4)

      Text {
        width: parent.width
        text: "Misc"
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Color.accent
      }
    }

    Toggle {
      id: debugToggle
      width: parent.width
      label: "Debug mode"
      description: "Log plugin actions to the shell console"
      checked: calendarService ? calendarService.debugMode : false
      hasCursor: tasksView.configCursorKind === "debug"
      onClicked: tasksView.toggleDebugMode()
    }

    Button {
      id: clearLogsButton
      visible: calendarService ? calendarService.debugMode : false
      text: "Clear logs"
      bordered: true
      hasCursor: tasksView.configCursorKind === "clearLogs"
      onClicked: if (calendarService) calendarService.clearDebugLog()
    }

    Rectangle {
      width: parent.width
      height: 220
      radius: Style.cornerRadius
      color: Color.popups.background
      border.color: Color.popups.border
      border.width: 1
      visible: calendarService ? calendarService.debugMode : false

      ScrollView {
        id: debugLogScroll
        anchors.fill: parent
        anchors.margins: Style.space(2)
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        TextArea {
          id: debugLogArea
          readOnly: true
          wrapMode: TextArea.Wrap
          textFormat: Text.PlainText
          persistentSelection: false
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          text: calendarService ? calendarService.debugLogText : ""
          background: null
          onTextChanged: cursorPosition = text.length
        }
      }
    }
  }

  // Add tab content
  Column {
    id: addTaskView
    visible: tasksView.activeTab === "add"
    width: Math.min(parent.width, Style.space(420))
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(12)

    // --- Add-task state ---------------------------------------------------

    property string calendarId: ""
    property string dueKey: ""
    property string startKey: ""
    // Which date field the shared picker writes to: "due" or "start".
    property string pickerTarget: "due"
    property bool duePickerOpen: false
    property string createError: ""
    // The user's short date order, from the shell locale (e.g. dd.MM.yy, M/d/yy).
    readonly property string datePattern: Qt.locale(I18n.formatLocale).dateFormat(Locale.ShortFormat) || TaskModel.DATE_INPUT_PATTERN
    // Drafts of creates that were submitted and not yet confirmed, oldest
    // first. The service confirms creates in the same order.
    property var inFlightCreates: []
    // Edit mode reuses this form: the task being edited (null when adding)
    // and the new-task draft stashed while editing.
    property var editingTask: null
    property var stashedDraft: null
    readonly property bool editing: editingTask !== null

    readonly property var writableCalendars: {
      var all = calendarService && calendarService.calendars ? calendarService.calendars : []
      var out = []
      for (var i = 0; i < all.length; i++) {
        var calendar = all[i]
        if (calendar && calendar.id && !calendar.readonly) out.push(calendar)
      }
      return out
    }

    readonly property var calendarOptions: {
      var out = []
      for (var i = 0; i < writableCalendars.length; i++) {
        var calendar = writableCalendars[i]
        out.push({ value: String(calendar.id), label: TaskModel.calendarChoiceLabel(calendar, {}) })
      }
      return out
    }

    // While editing, a task can only move within its own provider (the helper
    // copies it between calendars of the same backend).
    readonly property var editCalendarOptions: {
      var out = []
      var all = calendarService && calendarService.calendars ? calendarService.calendars : []
      var taskCalendarId = editingTask ? String(editingTask.calendarId || "") : ""
      var provider = ""
      for (var i = 0; i < all.length; i++) if (all[i] && String(all[i].id) === taskCalendarId) provider = String(all[i].provider || "")
      for (var j = 0; j < writableCalendars.length; j++) {
        var calendar = writableCalendars[j]
        if (String(calendar.provider || "") === provider) out.push({ value: String(calendar.id), label: TaskModel.calendarChoiceLabel(calendar, {}) })
      }
      return out
    }

    readonly property bool canSubmit: (editing || calendarId !== "")
      && calendarService !== null
      && trimText(addSummaryField.text).length > 0

    // --- Add-task behavior ------------------------------------------------

    function trimText(value) {
      return String(value == null ? "" : value).replace(/^\s+|\s+$/g, "")
    }

    function pad2(value) {
      var s = String(value)
      return s.length < 2 ? "0" + s : s
    }

    // All-day due strings stay local to this view: build and format only,
    // never resolve calendar math beyond what the mini grid needs.
    function dueKeyFor(year, month, day) {
      if (!isFinite(year) || !isFinite(month) || !isFinite(day)) return ""
      return [year, pad2(month + 1), pad2(day)].join("-")
    }

    function dueKeyForDate(date) {
      if (!date || isNaN(date.getTime())) return ""
      return dueKeyFor(date.getFullYear(), date.getMonth(), date.getDate())
    }

    function parseDueKey(key) {
      var parts = String(key || "").split("-")
      if (parts.length !== 3) return null
      var year = parseInt(parts[0], 10)
      var month = parseInt(parts[1], 10)
      var day = parseInt(parts[2], 10)
      if (!isFinite(year) || !isFinite(month) || !isFinite(day)) return null
      if (month < 1 || month > 12 || day < 1 || day > 31) return null
      return new Date(year, month - 1, day)
    }

    function hasCalendar(id) {
      var all = writableCalendars
      for (var i = 0; i < all.length; i++) {
        if (String(all[i].id) === String(id)) return true
      }
      return false
    }

    // Prefer the service default when it is writable, else the first
    // writable calendar, else "" (submit stays disabled with a hint).
    function defaultWritableCalendarId() {
      var preferred = calendarService && typeof calendarService.defaultCalendarId === "function"
        ? String(calendarService.defaultCalendarId() || "")
        : ""
      if (preferred !== "" && hasCalendar(preferred)) return preferred
      var all = writableCalendars
      return all.length > 0 ? String(all[0].id) : ""
    }

    function resetCalendar() {
      calendarId = defaultWritableCalendarId()
      // Dropdown reassigns its own value on selection, which breaks an
      // outer binding — mirror every external change into it instead.
      if (addCalendarDropdown) addCalendarDropdown.value = calendarId
    }

    function activeKey() {
      return pickerTarget === "start" ? startKey : dueKey
    }

    function dateInputFor(target) {
      return target === "start" ? addStartInput : addDueInput
    }

    function setDateKey(target, key) {
      if (target === "start") startKey = key
      else dueKey = key
    }

    function setActiveKey(key) {
      setDateKey(pickerTarget, key)
      dateInputFor(pickerTarget).syncText(true)
    }

    // Typed text is checked when its field loses focus, on Enter, and before
    // a submit. Returns false (and shows the hint) when the text is no date.
    function commitDateInput(target) {
      var input = dateInputFor(target)
      var text = trimText(input.field.text)
      var key = ""
      if (text !== "") {
        key = TaskModel.parseDateInput(text, datePattern, tasksView.now)
        if (key === "") {
          input.errorText = "Enter a date as " + TaskModel.dateInputHint(datePattern) + "."
          return false
        }
      }
      setDateKey(target, key)
      input.syncText(true)
      return true
    }

    function commitDateInputs() {
      var dueOk = commitDateInput("due")
      var startOk = commitDateInput("start")
      return dueOk && startOk
    }

    function syncDateInputs(force) {
      addDueInput.syncText(force)
      addStartInput.syncText(force)
    }

    // The shared Dropdown keeps its focusable trigger private; it is the
    // first tab stop inside it.
    function firstTabStop(item) {
      if (!item) return null
      if (item.activeFocusOnTab === true) return item
      for (var i = 0; i < item.children.length; i++) {
        var found = firstTabStop(item.children[i])
        if (found) return found
      }
      return null
    }

    function calendarTrigger() {
      return firstTabStop(addCalendarDropdown)
    }

    // One picker serves both date fields: the button that opened it names
    // the target. Pressing the same button again closes it.
    function toggleDuePicker(target) {
      var next = target === "start" ? "start" : "due"
      if (duePickerOpen && pickerTarget === next) { closeDuePicker(); return }
      pickerTarget = next
      if (duePickerOpen) addDueGrid.syncToActive()
      else duePickerOpen = true
    }

    // Closing the picker returns the keyboard to the field that opened it
    // (not the list cursor), so Tab/Shift+Tab continue from where the user was.
    function closeDuePicker() {
      if (!duePickerOpen) return
      duePickerOpen = false
      var trigger = dateInputFor(pickerTarget).pickerButton
      Qt.callLater(function() { trigger.forceActiveFocus() })
    }

    // Ctrl+J / Ctrl+K: cycle the target calendar without opening the list.
    function stepCalendar(delta) {
      var all = writableCalendars
      if (all.length === 0) return
      var index = -1
      for (var i = 0; i < all.length; i++) if (String(all[i].id) === calendarId) { index = i; break }
      var next = all[((index < 0 ? 0 : index) + delta + all.length) % all.length]
      calendarId = String(next.id)
      addCalendarDropdown.value = calendarId
      debugLog("action: add task calendar -> " + calendarId)
    }

    // Tab / Shift+Tab walk the form in reading order.
    function focusOrder() {
      var out = [calendarTrigger()]
      out = out.concat([addSummaryField, addDescriptionField,
        addStartInput.field, addStartInput.pickerButton,
        addDueInput.field, addDueInput.pickerButton,
        addCategoryField, addCreateButton, addCancelButton])
      return out.filter(function(item) { return item !== null && item !== undefined })
    }

    function formStep(direction) {
      if (duePickerOpen) { closeDuePicker(); return }
      var order = focusOrder()
      if (order.length === 0) return
      var current = -1
      for (var i = 0; i < order.length; i++) if (order[i].activeFocus) { current = i; break }
      var next = current < 0 ? (direction > 0 ? 0 : order.length - 1)
        : (current + direction + order.length) % order.length
      order[next].forceActiveFocus()
      tasksView.reveal(order[next])
    }

    function clearDate(target) {
      debugLog("action: clear " + target + " date")
      setDateKey(target, "")
      dateInputFor(target).syncText(true)
    }

    function clearDueDate() { clearDate("due") }

    function clearStartDate() { clearDate("start") }

    function clearActiveDate() {
      if (pickerTarget === "start") clearStartDate()
      else clearDueDate()
    }

    // Starts by must fall before the due date. Both are day keys, so a string
    // compare orders them. Equal days are refused too: a VTODO needs DUE after
    // DTSTART, which strict CalDAV servers enforce.
    function startConflict() {
      return startKey !== "" && dueKey !== "" && startKey >= dueKey
    }

    function parsedCategories() {
      var raw = addCategoryField.text.split(",")
      var out = []
      for (var i = 0; i < raw.length; i++) {
        var tag = trimText(raw[i])
        if (tag.length > 0) out.push(tag)
      }
      return out
    }

    function clearDraft() {
      addSummaryField.text = ""
      addDescriptionField.text = ""
      addCategoryField.text = ""
      dueKey = ""
      startKey = ""
      syncDateInputs(true)
      duePickerOpen = false
      createError = ""
    }

    // --- Edit mode ---

    function beginEdit(task) {
      if (!task || !task.uid || task._pending) return false
      if (!hasCalendar(String(task.calendarId || ""))) {
        tasksView.editError = "That calendar is read-only, so the task can't be edited."
        return false
      }
      tasksView.editError = ""
      if (!editing) {
        stashedDraft = {
          summary: addSummaryField.text,
          description: addDescriptionField.text,
          category: addCategoryField.text,
          dueKey: dueKey,
          startKey: startKey,
          calendarId: calendarId
        }
      }
      editingTask = task
      calendarId = String(task.calendarId)
      addCalendarDropdown.value = calendarId
      addSummaryField.text = String(task.title || "")
      addDescriptionField.text = String(task.description || "")
      addCategoryField.text = (task.categories || []).join(", ")
      var due = TaskModel.parseDateTime(task.due)
      dueKey = due ? dueKeyForDate(due) : ""
      var start = TaskModel.parseDateTime(task.start)
      startKey = start ? dueKeyForDate(start) : ""
      syncDateInputs(true)
      duePickerOpen = false
      createError = ""
      debugLog("action: begin edit task " + task.uid)
      tasksView.activeTab = "add"
      return true
    }

    // Leave edit mode and bring back the new-task draft it displaced.
    function endEdit() {
      if (!editing) return
      editingTask = null
      var draft = stashedDraft
      stashedDraft = null
      addSummaryField.text = draft ? draft.summary : ""
      addDescriptionField.text = draft ? draft.description : ""
      addCategoryField.text = draft ? draft.category : ""
      dueKey = draft ? draft.dueKey : ""
      startKey = draft ? draft.startKey : ""
      syncDateInputs(true)
      duePickerOpen = false
      createError = ""
      if (draft && hasCalendar(draft.calendarId)) calendarId = draft.calendarId
      else resetCalendar()
      addCalendarDropdown.value = calendarId
    }

    // Send only the fields that differ from the stored task.
    function submitEdit() {
      var task = editingTask
      if (!task || !calendarService) return
      if (!commitDateInputs()) return
      var fields = {}
      var title = trimText(addSummaryField.text)
      if (title !== String(task.title || "")) fields.title = title
      var description = String(addDescriptionField.text == null ? "" : addDescriptionField.text)
      if (description !== String(task.description || "")) fields.description = description
      var categories = parsedCategories()
      if (categories.join("\u0001") !== (task.categories || []).join("\u0001")) fields.categories = categories
      if (String(calendarId) !== String(task.calendarId || "")) fields.calendarId = String(calendarId)
      var original = TaskModel.parseDateTime(task.due)
      var originalKey = original ? dueKeyForDate(original) : ""
      if (dueKey !== originalKey) fields.due = dueKey
      var originalStart = TaskModel.parseDateTime(task.start)
      var originalStartKey = originalStart ? dueKeyForDate(originalStart) : ""
      if (startKey !== originalStartKey) fields.dtstart = startKey
      // Only dates the user touched are checked, so an older conflicting
      // task can still be renamed.
      if ((fields.due !== undefined || fields.dtstart !== undefined) && startConflict()) {
        createError = "Starts by must be before the due date."
        return
      }
      debugLog("action: save edit task " + task.uid + " fields=" + Object.keys(fields).join(","))
      endEdit()
      tasksView.activeTab = "pending"
      if (Object.keys(fields).length > 0) calendarService.editTask(task, fields)
    }

    function trySubmit() {
      if (!canSubmit) return
      if (!commitDateInputs()) return
      if (editing) { submitEdit(); return }
      if (startConflict()) {
        createError = "Starts by must be before the due date."
        return
      }
      var title = trimText(addSummaryField.text)
      var description = String(addDescriptionField.text == null ? "" : addDescriptionField.text)
      var categories = parsedCategories()
      var due = dueKey
      var start = startKey
      var target = calendarId
      debugLog("action: create task calendar=" + target + " due=" + (due !== "" ? due : "(none)") + " start=" + (start !== "" ? start : "(none)") + " title=" + title)
      // The form clears and the list shows the task at once. The service
      // reports the outcome later; a failure restores this draft.
      inFlightCreates = inFlightCreates.concat([{
        title: title,
        summary: addSummaryField.text,
        description: addDescriptionField.text,
        category: addCategoryField.text,
        dueKey: due,
        startKey: start,
        calendarId: target
      }])
      createError = ""
      clearDraft()
      tasksView.activeTab = "pending"
      if (calendarService) {
        // Priority stays at its service default.
        calendarService.createTask(target, title, due, undefined, description, categories, start)
      }
    }

    function handleCreateSuccess() {
      if (inFlightCreates.length === 0) return
      inFlightCreates = inFlightCreates.slice(1)
    }

    // Restore the failed draft into the form when the user is not already
    // typing a new one. Otherwise keep the error visible with the failed
    // title, so nothing is silently dropped.
    function handleCreateFailure(reason) {
      var draft = inFlightCreates.length > 0 ? inFlightCreates[0] : null
      inFlightCreates = inFlightCreates.slice(1)
      var label = draft && draft.title ? " \"" + String(draft.title).slice(0, 60) + "\"" : ""
      var message = "Couldn't create the task" + label + ": " + String(reason || "something went wrong")
      if (!draft) {
        createError = message
        return
      }
      if (tasksView.activeTab !== "add") {
        if (trimText(addSummaryField.text) === "" && !editing) {
          addSummaryField.text = draft.summary
          addDescriptionField.text = draft.description
          addCategoryField.text = draft.category
          dueKey = draft.dueKey
          startKey = draft.startKey
          syncDateInputs(true)
          if (hasCalendar(draft.calendarId)) calendarId = draft.calendarId
          else resetCalendar()
          addCalendarDropdown.value = calendarId
          createError = message
          tasksView.activeTab = "add"
        }
        // Otherwise the pending list keeps the service error on screen.
        return
      }
      createError = message
    }

    function cancelAdd() {
      debugLog("action: add task cancel")
      if (editing) {
        endEdit()
      } else {
        clearDraft()
        resetCalendar()
      }
      tasksView.activeTab = "pending"
    }

    // Esc keeps a half-typed new task for next time, but drops an edit.
    function escapeAdd() {
      debugLog("action: add task escape")
      duePickerOpen = false
      if (editing) endEdit()
      tasksView.activeTab = "pending"
    }

    function beginAdd() {
      if (calendarId === "" || !hasCalendar(calendarId)) resetCalendar()
      Qt.callLater(function() { addSummaryField.forceActiveFocus() })
    }

    function releaseEditing() {
      duePickerOpen = false
      addSummaryField.focus = false
      addDescriptionField.focus = false
      addCategoryField.focus = false
      createError = ""
      restorePanelFocus()
    }

    // Hand the keyboard back to the panel cursor unless a field still
    // holds focus (the shared Dropdown and picker close without doing it).
    function restorePanelFocus() {
      if (!tasksView.opened || tasksView.activeTab !== "add") return
      if (addSummaryField.activeFocus || addDescriptionField.activeFocus || addCategoryField.activeFocus) return
      if (addStartInput.field.activeFocus || addDueInput.field.activeFocus) return
      // Closing the calendar list keeps keyboard focus on its trigger.
      var trigger = calendarTrigger()
      if (trigger) { trigger.forceActiveFocus(); return }
      if (panel && typeof panel.focusKeyCatcher === "function") panel.focusKeyCatcher()
    }

    onWritableCalendarsChanged: if (calendarId === "" || !hasCalendar(calendarId)) resetCalendar()

    // --- Add-task layout --------------------------------------------------

    Column {
      width: parent.width
      spacing: Style.space(4)

      Item {
        width: parent.width
        height: Math.max(addHeaderTitle.implicitHeight, addHeaderClose.implicitHeight)

        Text {
          id: addHeaderTitle
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: addTaskView.editing ? "Edit Task" : "New Task"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          textFormat: Text.PlainText
        }

        Button {
          id: addHeaderClose
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "\u2715"
          tooltipText: "Back to tasks"
          fontSize: Style.font.caption
          onClicked: {
            debugLog("action: add task close")
            tasksView.activeTab = "pending"
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Color.accent
      }
    }

    AddFormField {
      label: "Calendar"

      Dropdown {
        id: addCalendarDropdown
        width: parent.width
        showLabel: false
        options: addTaskView.editing ? addTaskView.editCalendarOptions : addTaskView.calendarOptions
        value: addTaskView.calendarId
        onChanged: function(v) { addTaskView.calendarId = v }
        onPopupOpenChanged: if (!popupOpen) addTaskView.restorePanelFocus()
      }

      Text {
        visible: addTaskView.calendarOptions.length === 0
        width: parent.width
        text: "No writable calendars — add one in Config"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
    }

    AddFormField {
      label: "Summary"

      TextField {
        id: addSummaryField
        Keys.forwardTo: tasksView.keyForward
        Keys.onTabPressed: function(event) { addTaskView.formStep(1); event.accepted = true }
        Keys.onBacktabPressed: function(event) { addTaskView.formStep(-1); event.accepted = true }
        width: parent.width
        placeholderText: "What needs doing?"
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        onAccepted: addTaskView.trySubmit()
        Keys.onEscapePressed: function(event) {
          addTaskView.escapeAdd()
          event.accepted = true
        }
      }
    }

    AddFormField {
      label: "Description"

      BorderSurface {
        id: addDescriptionSurface
        width: parent.width
        height: Style.space(76)
        radius: Style.cornerRadius

        readonly property bool _focused: addDescriptionField.activeFocus
        readonly property bool _hot: addDescriptionField.hovered
        readonly property var _borderSpec: Border.controlSpec(_focused ? "focus" : (_hot ? "hover-cursor" : "normal"), Color.foreground, Color.accent)

        color: Style.controlFill(_focused, _hot, Color.foreground, Color.accent)
        borderSpec: _borderSpec

        TextArea {
          id: addDescriptionField
          Keys.forwardTo: tasksView.keyForward
          // Tab / Shift+Tab walk the form; a multi-line TextArea would otherwise insert tabs.
          Keys.onTabPressed: function(event) { addTaskView.formStep(1); event.accepted = true }
          Keys.onBacktabPressed: function(event) { addTaskView.formStep(-1); event.accepted = true }
          anchors.fill: parent
          anchors.leftMargin: Style.spacing.controlPaddingX + Border.left(parent._borderSpec)
          anchors.rightMargin: Style.spacing.controlPaddingX + Border.right(parent._borderSpec)
          anchors.topMargin: Style.space(6) + Border.top(parent._borderSpec)
          anchors.bottomMargin: Style.space(6) + Border.bottom(parent._borderSpec)
          placeholderText: "Optional details"
          placeholderTextColor: Qt.darker(Color.foreground, 1.6)
          selectionColor: Style.selectionFillFor(Color.foreground, Color.accent)
          selectedTextColor: Color.foreground
          wrapMode: TextArea.Wrap
          textFormat: Text.PlainText
          persistentSelection: false
          clip: true
          background: null
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          Keys.onEscapePressed: function(event) {
            addTaskView.escapeAdd()
            event.accepted = true
          }
        }
      }
    }

    AddFormField {
      label: "Starts by"

      AddDateInput {
        id: addStartInput
        target: "start"
        keyValue: addTaskView.startKey
      }

      Text {
        visible: addStartInput.errorText !== ""
        width: parent.width
        text: addStartInput.errorText
        color: Color.urgent
        wrapMode: Text.WordWrap
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
    }

    AddFormField {
      label: "Due"

      AddDateInput {
        id: addDueInput
        target: "due"
        keyValue: addTaskView.dueKey
      }

      Text {
        visible: addDueInput.errorText !== ""
        width: parent.width
        text: addDueInput.errorText
        color: Color.urgent
        wrapMode: Text.WordWrap
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
    }

    // Shared by both date fields; it sits under the Due field and writes to
    // whichever field opened it.
    AddDuePicker {
      id: addDueGrid
      visible: addTaskView.duePickerOpen
    }

    AddFormField {
      label: "Category"

      TextField {
        id: addCategoryField
        Keys.forwardTo: tasksView.keyForward
        Keys.onTabPressed: function(event) { addTaskView.formStep(1); event.accepted = true }
        Keys.onBacktabPressed: function(event) { addTaskView.formStep(-1); event.accepted = true }
        width: parent.width
        placeholderText: "e.g. errands, home"
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        onAccepted: addTaskView.trySubmit()
        Keys.onEscapePressed: function(event) {
          addTaskView.escapeAdd()
          event.accepted = true
        }
      }

      Text {
        width: parent.width
        text: "Comma-separated"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(6)

      Button {
        id: addCreateButton
        Keys.forwardTo: tasksView.keyForward
        text: addTaskView.editing ? "Save Changes" : "Create Task"
        tooltipText: addTaskView.editing ? "Save changes" : "Create task"
        foreground: Color.accent
        bordered: true
        focusable: true
        enabled: addTaskView.canSubmit
        opacity: enabled ? 1 : 0.4
        onClicked: addTaskView.trySubmit()
      }

      Button {
        id: addCancelButton
        Keys.forwardTo: tasksView.keyForward
        text: "Cancel"
        focusable: true
        onClicked: addTaskView.cancelAdd()
      }
    }

    // Create failure feedback. Sits under the action row so the eye lands
    // on it right after a rejected submit; fields stay editable above.
    Text {
      visible: addTaskView.createError !== ""
      width: parent.width
      text: addTaskView.createError
      color: Color.urgent
      wrapMode: Text.WordWrap
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
    }
  }

  // --- Service signal connections ---

  Connections {
    target: taskService
    enabled: taskService !== null

    function onRefreshed() {
      tasksView.now = new Date()
    }

    function onDebugModeChanged() {
      TaskModel.setDebugEnabled(taskService.debugMode)
    }

    function onTaskCreated(task) {
      tasksView.now = new Date()
      addTaskView.handleCreateSuccess()
    }

    function onTaskCreateFailed(reason) {
      addTaskView.handleCreateFailure(reason)
    }

    function onTaskUpdated(task) {
      tasksView.now = new Date()
    }

    function onTaskDeleted(uid) {
      tasksView.now = new Date()
    }

    function onCaldavSetupStatusChanged() {
      if (taskService && taskService.caldavSetupStatus === "success") {
        caldavSuccessCloseTimer.restart()
      }
    }
  }

  // --- Load tasks when view becomes visible ---

  onVisibleChanged: {
    if (visible && taskService) {
      tasksView.now = new Date()
      taskService.listTasks()
    }
  }

  // --- Load tasks on creation if already visible ---

  onCalendarServiceChanged: syncTaskModelDebug()

  Component.onCompleted: {
    syncTaskModelDebug()
    if (visible && taskService) {
      tasksView.now = new Date()
      taskService.listTasks()
    }
  }

  // --- Tab transitions ---

  onActiveTabChanged: {
    resetCursor()
    if (activeTab === "add") {
      addTaskView.beginAdd()
    } else {
      // Close the shared calendar picker and move focus off its (now hidden)
      // trigger, so keys on the overview are not routed to it.
      if (addCalendarDropdown.popupOpen) addCalendarDropdown.close()
      if (addTaskView.editing) addTaskView.endEdit()
      addTaskView.releaseEditing()
      Qt.callLater(tasksView.focusPanel)
    }
  }

  // --- Periodic refresh timer ---

  Timer {
    id: refreshTimer
    interval: 60000
    repeat: true
    running: tasksView.viewMode === "tasks" && tasksView.opened
    onTriggered: {
      tasksView.now = new Date()
      if (taskService) taskService.listTasks()
    }
  }
}
