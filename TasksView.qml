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

  // True while the add-task view owns keyboard input (text fields focused,
  // calendar dropdown popup open, due-date picker open). Panel.qml binds the
  // key catcher's `blocked` to this so typing reaches the form.
  readonly property bool formEditing: activeTab === "add" && (
    addSummaryField.activeFocus
    || addDescriptionField.activeFocus
    || addCategoryField.activeFocus
    || addCalendarDropdown.popupOpen
    || addDueGrid.popupOpen)

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

  function syncTaskModelDebug() {
    TaskModel.setDebugEnabled(calendarService && calendarService.debugMode === true)
  }

  // --- Inline sub-components ---

  component TaskSection: Column {
    id: taskSection
    property string title: ""
    property var tasks: []
    property string emptyText: "No tasks"
    property string dateLabel: "due"
    property bool showOverdue: false
    width: parent.width
    spacing: Style.space(4)

    Text {
      width: parent.width
      text: taskSection.title
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

    Repeater {
      model: taskSection.tasks

      TaskItem {
        required property var modelData
        required property int index
        width: taskSection.width
        task: modelData
        showOverdue: taskSection.showOverdue
        dateLabel: taskSection.dateLabel
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

  component TaskItem: Rectangle {
    id: taskItem
    property var task: null
    property bool showOverdue: false
    property string dateLabel: "due"

    readonly property color taskCalendarColor: taskItem.task && taskItem.task.calendarColor ? taskItem.task.calendarColor : Color.muted
    readonly property bool overdue: taskItem.showOverdue && taskItem.task && TaskModel.isOverdue(taskItem.task, tasksView.now)
    readonly property bool hasCalendarName: taskItem.task && taskItem.task.calendarName
    readonly property real calendarNameAvailableWidth: {
      if (!hasCalendarName) return 0
      var s = metaRow.spacing
      var available = metaRow.width
      available -= calendarIcon.implicitWidth + s
      if (tagText.visible) {
        available -= separatorDot.implicitWidth + s
        available -= tagIcon.implicitWidth + s
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
    // Done tab delegates can be instantiated while their container is hidden,
    // which latches calendarNameText.implicitWidth at 0.
    TextMetrics {
      id: calendarNameMetrics
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      text: taskItem.task ? TaskModel.plainDisplay(taskItem.task.calendarName, 80) : ""
    }

    readonly property string dateText: {
      if (!taskItem.task) return ""
      if (taskItem.dateLabel === "completed") return TaskModel.formatCompletedDate(taskItem.task)
      if (taskItem.dateLabel === "created") {
        var d = TaskModel.parseDateTime(taskItem.task.created)
        if (!d) return ""
        var month = TaskModel.SHORT_MONTH_NAMES[d.getMonth()]
        var day = d.getDate()
        var year = d.getFullYear()
        if (year === new Date().getFullYear()) return month + " " + day
        return month + " " + day + ", " + year
      }
      return TaskModel.formatDueDate(taskItem.task)
    }

    height: taskRow.implicitHeight + Style.space(6)
    radius: Style.cornerRadius
    color: taskItemMouse.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent"

    Row {
      id: taskRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Text {
        id: statusIcon
        anchors.verticalCenter: parent.verticalCenter
        text: taskItem.task && taskItem.task.status === "COMPLETED" ? "\u2713" : "\u25CB"
        color: taskItem.task && taskItem.task.status === "COMPLETED" ? Color.muted : Color.foreground
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
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: taskItem.overdue
          textFormat: Text.PlainText
        }

        Row {
          id: metaRow
          width: parent.width
          spacing: Style.space(1)

          Text {
            id: calendarIcon
            visible: taskItem.hasCalendarName
            width: visible ? implicitWidth : 0
            text: "\uf073"
            color: taskItem.taskCalendarColor
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }

          Text {
            id: calendarNameText
            visible: taskItem.hasCalendarName
            // Content-sized first block: take only the width the calendar name needs,
            // but elide when the tag block leaves less room than that.
            width: {
              if (!visible) return 0
              // Done tab: implicitWidth can be latched at 0 while the hidden tab
              // instantiates its delegates, so measure the text with TextMetrics
              // instead and clamp it to the room left by the tag block.
              if (taskItem.dateLabel === "completed") {
                return Math.max(0, Math.min(calendarNameMetrics.width, taskItem.calendarNameAvailableWidth))
              }
              return Math.min(implicitWidth, taskItem.calendarNameAvailableWidth)
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
            width: visible ? implicitWidth : 0
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
            width: visible ? implicitWidth : 0
            text: "\uf02b"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }

          Text {
            id: tagText
            visible: taskItem.task && taskItem.task.categories && taskItem.task.categories.length > 0
            width: visible ? Math.max(0, Math.min(implicitWidth, parent.width * 0.45 - tagIcon.width - parent.spacing)) : 0
            text: visible ? TaskModel.plainDisplay(taskItem.task.categories[0], 40) : ""
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

    MouseArea {
      id: taskItemMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
    }
  }

  component SettingsCalendarRow: Row {
    id: settingsCalendarRow
    property var calendar: ({})
    property int calendarIndex: 0

    width: parent ? parent.width : 0
    spacing: Style.space(8)
    height: Style.spacing.controlHeight

    readonly property string calendarId: calendar && calendar.id ? calendar.id : ""
    readonly property string sourceLabel: TaskModel.providerLabel(calendar ? calendar.provider : "", calendar ? calendar.host : "") + (calendar && calendar.readonly ? " · read-only" : "")
    readonly property string currentName: TaskModel.calendarDisplayName(calendar, {})
    readonly property bool removable: TaskModel.canRemoveCalendar(calendar)

    Rectangle {
      width: Style.space(22)
      height: Style.space(22)
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: calendar && calendar.color ? calendar.color : Color.accent
      border.width: 1
      border.color: Util.alpha(Color.foreground, 0.35)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: settingsCalendarRow.currentName
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
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
      width: Math.max(Style.space(8), parent.width - Style.space(222) - sourceText.implicitWidth - (settingsCalendarRow.removable ? removeCalendarButton.implicitWidth : 0) - parent.spacing * (settingsCalendarRow.removable ? 4 : 3))
      height: 1
    }

    Button {
      id: removeCalendarButton
      visible: settingsCalendarRow.removable
      enabled: calendarService && !calendarService.pendingRemoveId
      anchors.verticalCenter: parent.verticalCenter
      text: calendarService && calendarService.pendingRemoveId === settingsCalendarRow.calendarId ? "Removing" : "Remove"
      bordered: true
      onClicked: {
        debugLog("action: remove calendar " + settingsCalendarRow.calendarId)
        if (calendarService) calendarService.removeCalendar(settingsCalendarRow.calendarId)
      }
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
    border.width: dueCell.cell && dueCell.cell.today && !picked ? 1 : 0
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
          selected: key === addTaskView.dueKey
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

    // Handles a day-cell click on behalf of the cell (the cell's inline
    // component scope cannot see the add view's ids directly).
    function pickCell(cell) {
      if (!cell) return
      debugLog("action: pick due date " + cell.key)
      addTaskView.dueKey = cell.key
      addTaskView.closeDuePicker()
    }

    width: parent ? parent.width : 0
    spacing: Style.space(2)
    focus: visible

    onVisibleChanged: {
      if (!visible) return
      var anchor = addTaskView.parseDueKey(addTaskView.dueKey)
      if (!anchor) anchor = new Date(tasksView.now)
      viewYear = anchor.getFullYear()
      viewMonth = anchor.getMonth()
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

  // Pending tab content
  Column {
    visible: tasksView.activeTab === "pending"
    width: parent.width
    spacing: Style.space(12)

    TaskSection {
      title: "Upcoming"
      tasks: TaskModel.upcomingTasks(tasksView.allTasks, 5)
      emptyText: "No upcoming tasks"
      dateLabel: "due"
      showOverdue: true
    }

    TaskSection {
      title: "Backlog"
      tasks: TaskModel.backlogTasks(tasksView.allTasks)
      emptyText: "No backlog tasks"
      dateLabel: "created"
      showOverdue: false
    }
  }

  // Done tab content
  Column {
    visible: tasksView.activeTab === "done"
    width: parent.width
    spacing: Style.space(12)

    TaskSection {
      title: "Completed"
      tasks: TaskModel.doneTasks(tasksView.allTasks, 10)
      emptyText: "No completed tasks"
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
      model: calendarService ? calendarService.calendars : []

      SettingsCalendarRow {
        required property var modelData
        required property int index
        width: parent ? parent.width : 0
        calendar: modelData
        calendarIndex: index
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

    Button {
      id: connectServerButton
      visible: !caldavForm.visible
      text: "Connect Server"
      bordered: true
      onClicked: {
        debugLog("action: open caldav form")
        caldavForm.visible = true
      }
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
        width: parent.width
        placeholderText: "https://caldav.example.com/dav/"
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      TextField {
        id: caldavUsernameField
        width: parent.width
        placeholderText: "Username"
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      TextField {
        id: caldavPasswordField
        width: parent.width
        placeholderText: "Password"
        password: true
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Button {
          text: calendarService && calendarService.caldavSetupStatus === "connecting" ? "Connecting..." : "Connect"
          bordered: true
          enabled: calendarService && calendarService.caldavSetupStatus !== "connecting"
          onClicked: {
            debugLog("action: caldav connect " + sanitizeUrl(caldavUrlField.text))
            if (calendarService) {
              calendarService.setupCaldav("", caldavUrlField.text, caldavUsernameField.text, caldavPasswordField.text)
            }
          }
        }

        Button {
          text: "Cancel"
          enabled: !calendarService || calendarService.caldavSetupStatus !== "connecting"
          onClicked: {
            debugLog("action: caldav form cancel")
            caldavUrlField.text = ""
            caldavUsernameField.text = ""
            caldavPasswordField.text = ""
            caldavForm.visible = false
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
      width: parent.width
      label: "Debug mode"
      description: "Log plugin actions to the shell console"
      checked: calendarService ? calendarService.debugMode : false
      onClicked: {
        var next = !(calendarService && calendarService.debugMode)
        if (calendarService) calendarService.debugMode = next
        if (panel) panel.persistSettings({ debug: next })
        debugLog("action: toggle debug mode -> " + next)
      }
    }

    Button {
      id: clearLogsButton
      visible: calendarService ? calendarService.debugMode : false
      text: "Clear logs"
      bordered: true
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
    property bool duePickerOpen: false
    property bool submitBusy: false
    property string createError: ""

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

    readonly property bool canSubmit: !submitBusy
      && calendarId !== ""
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

    // "Mon d" this year, "Mon d, YYYY" otherwise — TaskModel.formatDueDate style.
    function formatDueChoice(key) {
      var date = parseDueKey(key)
      if (!date) return ""
      var month = TaskModel.SHORT_MONTH_NAMES[date.getMonth()]
      var day = date.getDate()
      var year = date.getFullYear()
      if (year === tasksView.now.getFullYear()) return month + " " + day
      return month + " " + day + ", " + year
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

    function toggleDuePicker() {
      duePickerOpen = !duePickerOpen
      if (!duePickerOpen) restorePanelFocus()
    }

    function closeDuePicker() {
      if (!duePickerOpen) return
      duePickerOpen = false
      restorePanelFocus()
    }

    function clearDueDate() {
      debugLog("action: clear due date")
      dueKey = ""
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
      duePickerOpen = false
      createError = ""
    }

    function trySubmit() {
      if (!canSubmit) return
      var title = trimText(addSummaryField.text)
      var description = String(addDescriptionField.text == null ? "" : addDescriptionField.text)
      var categories = parsedCategories()
      createError = ""
      submitBusy = true
      addSubmitSafety.restart()
      debugLog("action: create task calendar=" + calendarId + " due=" + (dueKey !== "" ? dueKey : "(none)") + " title=" + title)
      // Stay on the form until the service confirms the create: switching
      // to Pending early threw the draft away whenever the helper rejected
      // it (bad auth, wrong provider...), leaving only a flash of red.
      // Priority stays at its service default.
      if (calendarService) {
        calendarService.createTask(calendarId, title, dueKey, undefined, description, categories)
      }
    }

    function handleCreateSuccess() {
      if (!submitBusy) return
      addSubmitSafety.stop()
      submitBusy = false
      clearDraft()
      tasksView.activeTab = "pending"
    }

    function handleCreateFailure(reason) {
      if (!submitBusy) return
      addSubmitSafety.stop()
      submitBusy = false
      // Draft (summary, description, due, categories, calendar) is kept so
      // the user can fix the cause and resubmit without retyping.
      createError = "Couldn't create the task: " + String(reason || "something went wrong")
    }

    function handleCreateTimeout() {
      if (!submitBusy) return
      submitBusy = false
      createError = "Create timed out — try again."
    }

    function cancelAdd() {
      debugLog("action: add task cancel")
      clearDraft()
      resetCalendar()
      tasksView.activeTab = "pending"
    }

    function escapeAdd() {
      debugLog("action: add task escape")
      duePickerOpen = false
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
      if (!tasksView.opened) return
      if (addSummaryField.activeFocus || addDescriptionField.activeFocus || addCategoryField.activeFocus) return
      if (panel && typeof panel.focusKeyCatcher === "function") panel.focusKeyCatcher()
    }

    onWritableCalendarsChanged: if (calendarId === "" || !hasCalendar(calendarId)) resetCalendar()

    // In-flight guard rather than a click debounce: submitBusy releases only
    // when the service reports success or failure. If neither ever arrives
    // (hung helper), this re-enables the form so it cannot dead-end.
    Timer {
      id: addSubmitSafety
      interval: 15000
      onTriggered: addTaskView.handleCreateTimeout()
    }

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
          text: "New Task"
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
        options: addTaskView.calendarOptions
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
      label: "Due"

      Row {
        width: parent.width
        spacing: Style.space(4)

        Button {
          id: addDueTrigger
          width: parent.width - (addDueClear.visible ? addDueClear.width + parent.spacing : 0)
          leftAlign: true
          bordered: true
          iconText: "\uf073"
          text: addTaskView.dueKey !== "" ? addTaskView.formatDueChoice(addTaskView.dueKey) : "No due date"
          foreground: addTaskView.dueKey !== "" ? Color.accent : Color.foreground
          tooltipText: addTaskView.duePickerOpen ? "Hide date picker" : "Pick a due date"
          onClicked: addTaskView.toggleDuePicker()
        }

        Button {
          id: addDueClear
          visible: addTaskView.dueKey !== ""
          text: "\u2715"
          tooltipText: "Remove due date"
          fontSize: Style.font.caption
          onClicked: addTaskView.clearDueDate()
        }
      }

      AddDuePicker {
        id: addDueGrid
        visible: addTaskView.duePickerOpen
      }
    }

    AddFormField {
      label: "Category"

      TextField {
        id: addCategoryField
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
        text: "Create Task"
        tooltipText: "Create task"
        foreground: Color.accent
        bordered: true
        enabled: addTaskView.canSubmit
        opacity: enabled ? 1 : 0.4
        onClicked: addTaskView.trySubmit()
      }

      Button {
        text: "Cancel"
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
    if (activeTab === "add") {
      addTaskView.beginAdd()
    } else {
      addTaskView.releaseEditing()
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
