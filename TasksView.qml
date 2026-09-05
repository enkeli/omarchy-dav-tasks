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

  // Direct binding to taskService.allTasks - this should update when the property changes
  readonly property var allTasks: taskService ? taskService.allTasks : []

  // Debug: log when allTasks changes
  onAllTasksChanged: {
    debugLog("allTasks property changed: " + (allTasks ? allTasks.length : 0))
  }

  function debugLog(message) {
    if (!calendarService || !calendarService.debugMode) return
    console.log("[TasksView]", message)
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
