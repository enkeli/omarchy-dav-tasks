import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "dev.enkeli.nextcloud.tasks"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function logState(reason) {
    console.log("[tasks-widget] BarWidget", reason,
      "moduleName=", root.moduleName,
      "visible=", root.visible,
      "implicitW=", root.implicitWidth,
      "implicitH=", root.implicitHeight,
      "button.text=", button.text,
      "button.visible=", button.visible,
      "button.labelVisible=", button.labelVisible,
      "button.hasVisualContent=", button.hasVisualContent,
      "button.w=", button.width,
      "button.h=", button.height,
      "button.labelWidth=", button.labelWidth,
      "bar=", root.bar ? "set" : "null",
      "panelLoaded=", !!panelLoader.item,
      "loaderStatus=", panelLoader.status)
  }

  function injectPanel() {
    var target = panelLoader.item
    console.log("[tasks-widget] injectPanel target=", target ? "ok" : "null")
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: logState("onCompleted")
  onVisibleChanged: logState("onVisibleChanged")
  onImplicitWidthChanged: logState("onImplicitWidthChanged")

  onBarChanged: {
    logState("onBarChanged")
    injectPanel()
    if (panelLoader.item && panelLoader.item.ensureRightAnchor)
      panelLoader.item.ensureRightAnchor()
  }
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onStatusChanged: console.log("[tasks-widget] panelLoader status=", status, "error=", source)
    onLoaded: {
      console.log("[tasks-widget] panelLoader onLoaded")
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf00c"
    labelVisible: true
    hasVisualContent: true
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: "Nextcloud Tasks"

    onClicked: root.togglePanel()
  }
}
