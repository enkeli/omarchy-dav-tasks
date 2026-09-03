import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "TaskModel.js" as TaskModel

Panel {
  id: root
  moduleName: "dev.enkeli.nextcloud.tasks"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property var calendarService: null

  onBarChanged: {
    var svc = bar && bar.shell ? bar.shell.serviceFor(root.moduleName) : null
    if (svc) calendarService = svc
  }

  // Status is managed by refresh() + timer (signal connection unreliable in current architecture)
  // On explicit Sync the timer will clear to completed (or error if tasksErrorMessage is set)

  function pad2(value) {
    return String(value).padStart(2, '0')
  }

  function dateKey(year, month, day) {
    if (!isFinite(year) || !isFinite(month) || !isFinite(day)) return ''
    return [year, pad2(month + 1), pad2(day)].join('-')
  }

  function keyForDate(date) {
    if (!date || isNaN(date.getTime())) return ''
    return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
  }

  property date today: new Date()
  readonly property string todayKey: keyForDate(today)
  property string viewMode: "tasks"
  property string selectedKey: todayKey

  property date now: new Date()
  property string syncStatus: ""

  Timer {
    id: statusClearTimer2
    interval: 2000
    onTriggered: root.syncStatus = ""
  }

  Timer {
    id: statusClearTimer
    interval: 2000
    onTriggered: {
      if (calendarService && calendarService.tasksErrorMessage) {
        root.syncStatus = "Sync failed, try again"
      } else {
        root.syncStatus = "Sync completed"
      }
      statusClearTimer2.restart()
    }
  }

  function open() {
    root.now = new Date()
    // Do not auto-refresh with status on open; only explicit Sync button sets status
    if (!root.selectedKey) root.selectedKey = root.todayKey
    if (calendarService) calendarService.listTasks()
    root.controller.show()
    Qt.callLater(function() { if (root.opened) setCenterHoverRevealSuppressed(true) })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() { root.opened ? root.close() : root.open() }

  function closeForPopoutSwitch() {
    root.popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function refresh() {
    root.today = new Date()
    if (!root.selectedKey) root.selectedKey = root.todayKey
    root.syncStatus = "Syncing..."
    if (calendarService) {
      calendarService.listTasks()
    }
    // Fallback: always clear status after 2s (checks error at that moment)
    statusClearTimer.restart()
  }

  function ensureRightAnchor() {
    console.log("[tasks-widget] Panel.ensureRightAnchor service=", calendarService ? "ok" : "null")
    if (calendarService && typeof calendarService.ensureRightAnchor === "function")
      calendarService.ensureRightAnchor()
  }

  Timer {
    interval: 10000
    running: root.opened
    repeat: true
    onTriggered: root.now = new Date()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(860))
    contentHeight: panel.fittedContentHeight(contentWrap.height)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentWrap.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Item {
          id: contentWrap
          width: calendarScroll.width
          height: calendarColumn.implicitHeight

          Column {
            id: calendarColumn
            width: Math.min(parent.width, Style.space(820))
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(12)

            Item {
              width: parent.width
              height: Math.max(tabControls.implicitHeight, actionControls.implicitHeight)

              Row {
                id: tabControls
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                ViewButton {
                  text: "Pending"
                  selected: tasksViewRoot.activeTab === "pending"
                  onClicked: tasksViewRoot.activeTab = "pending"
                }
                ViewButton {
                  text: "Done"
                  selected: tasksViewRoot.activeTab === "done"
                  onClicked: tasksViewRoot.activeTab = "done"
                }
              }

              Text {
                anchors.centerIn: parent
                text: root.syncStatus
                visible: root.syncStatus !== ""
                color: root.syncStatus.includes("failed") ? "#ff6b6b" : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.small
              }

              Row {
                id: actionControls
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)
                Button { id: syncButton; text: "\uf021"; tooltipText: "Sync now"; fontFamily: root.bar ? root.bar.fontFamily : Style.font.family; onClicked: root.refresh() }
                ViewButton {
                  text: "󰒓"
                  selected: tasksViewRoot.activeTab === "config"
                  onClicked: tasksViewRoot.activeTab = tasksViewRoot.activeTab === "config" ? "pending" : "config"
                }
              }
            }

            TasksView {
              id: tasksViewRoot
              width: parent.width
              calendarService: root.calendarService
              viewMode: root.viewMode
              opened: root.opened
            }
          }
        }
      }
    }
  }

  component ViewButton: Rectangle {
    id: viewButton
    property string text: ""
    property bool selected: false

    signal clicked()
    signal doubleClicked()

    implicitWidth: label.implicitWidth + Style.spacing.controlPaddingX * 2 + Style.space(2)
    implicitHeight: label.implicitHeight + Style.spacing.controlPaddingY * 2 + Style.space(2)
    radius: Style.cornerRadius
    color: mouse.pressed ? Style.pressedFillFor(Color.foreground, Color.accent)
      : mouse.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent)
      : selected ? Style.selectedFillFor(Color.foreground, Color.accent)
      : "transparent"

    Text {
      id: label
      anchors.centerIn: parent
      text: viewButton.text
      color: viewButton.selected ? Style.selectedStateColor(Color.foreground, Color.accent) : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.bold: viewButton.selected
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: viewButton.clicked()
      onDoubleClicked: viewButton.doubleClicked()
    }
  }
}
