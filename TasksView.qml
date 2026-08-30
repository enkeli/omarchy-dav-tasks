import QtQuick
import QtQuick.Controls
import "TaskModel.js" as TaskModel

Column {
  id: tasksView
  spacing: Style.space(4)

  readonly property var taskService: root.calendarService
  property string activeTab: "pending"
  property date now: new Date()

  // --- Inline sub-components ---

  component TabButton: Rectangle {
    id: tabBtn
    property string text: ""
    property bool selected: false
    signal clicked()

    implicitWidth: tabLabel.implicitWidth + Style.spacing.controlPaddingX * 2 + Style.space(2)
    implicitHeight: tabLabel.implicitHeight + Style.spacing.controlPaddingY * 2 + Style.space(2)
    radius: Style.cornerRadius
    color: tabMouse.pressed ? Style.pressedFillFor(Color.foreground, Color.accent)
      : tabMouse.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent)
      : selected ? Style.selectedFillFor(Color.foreground, Color.accent)
      : "transparent"

    Text {
      id: tabLabel
      anchors.centerIn: parent
      text: tabBtn.text
      color: tabBtn.selected ? Style.selectedStateColor(Color.foreground, Color.accent) : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.bold: tabBtn.selected
    }

    MouseArea {
      id: tabMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tabBtn.clicked()
    }
  }

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
      color: Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
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
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
    }
  }

  component TaskItem: Rectangle {
    id: taskItem
    property var task: null
    property bool showOverdue: false
    property string dateLabel: "due"

    readonly property bool overdue: taskItem.showOverdue && taskItem.task && TaskModel.isOverdue(taskItem.task, tasksView.now)
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
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
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
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: taskItem.overdue
          textFormat: Text.PlainText
        }

        Text {
          visible: taskItem.task && taskItem.task.calendarName
          width: parent.width
          text: taskItem.task ? TaskModel.plainDisplay(taskItem.task.calendarName, 80) : ""
          color: Color.muted
          elide: Text.ElideRight
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }
      }

      Column {
        id: dateColumn
        anchors.verticalCenter: parent.verticalCenter

        Text {
          visible: taskItem.dateText !== ""
          text: taskItem.dateText
          color: taskItem.overdue ? Color.urgent : Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
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

  // --- Content ---

  // Tab bar
  Row {
    width: parent.width
    spacing: Style.space(4)

    TabButton {
      text: "Pending"
      selected: tasksView.activeTab === "pending"
      onClicked: tasksView.activeTab = "pending"
    }
    TabButton {
      text: "Done"
      selected: tasksView.activeTab === "done"
      onClicked: tasksView.activeTab = "done"
    }
  }

  // Error message
  Text {
    visible: taskService && taskService.tasksStatus === "error"
    width: parent.width
    text: taskService ? taskService.tasksErrorMessage : ""
    textFormat: Text.PlainText
    color: Color.urgent
    wrapMode: Text.WordWrap
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  // Loading indicator
  Text {
    visible: taskService && taskService.tasksStatus === "loading"
    width: parent.width
    text: "Loading tasks..."
    color: Color.muted
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
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
      tasks: taskService ? TaskModel.upcomingTasks(taskService.allTasks, 5) : []
      emptyText: "No upcoming tasks"
      dateLabel: "due"
      showOverdue: true
    }

    TaskSection {
      title: "Backlog"
      tasks: taskService ? TaskModel.backlogTasks(taskService.allTasks) : []
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
      tasks: taskService ? TaskModel.doneTasks(taskService.allTasks, 10) : []
      emptyText: "No completed tasks"
      dateLabel: "completed"
      showOverdue: false
    }
  }

  // --- Service signal connections ---

  Connections {
    target: taskService
    enabled: taskService !== null

    function onRefreshed() {
      tasksView.now = new Date()
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

  // --- Periodic refresh timer ---

  Timer {
    id: refreshTimer
    interval: 60000
    repeat: true
    running: root.viewMode === "tasks" && root.opened
    onTriggered: {
      tasksView.now = new Date()
      if (taskService) taskService.listTasks()
    }
  }
}
