import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Keybindings.js" as Keybindings

// Searchable keyboard cheat sheet (the "?" overlay) that doubles as the
// rebinding UI: pick a row, press the record key, press the new chord.
// Everything is keyboard driven; the search field keeps focus throughout.
//
//   type          filter actions (all words must match name, section or keys)
//   Up / Down     move (also Ctrl+J/K and Ctrl+N/P)
//   Enter         run the highlighted action (only when it exists on the
//                 current screen)
//   Ctrl+E        rebind: the next chord becomes the action's only key
//   Ctrl+R        restore the default keys   Ctrl+U  unbind
//   Ctrl+Shift+R  restore every default (press twice)
//   Esc           cancel recording / close
Popup {
  id: root
  objectName: "shortcutHelp"

  property string contextName: "list"
  // Saved rebindings (action id -> [keys]); edits are reported through
  // overridesEdited so the owner decides where they are stored.
  property var overrides: ({})
  property string fontFamily: Style.font.family

  signal triggered(string actionId)
  signal overridesEdited(var overrides)

  property bool recording: false
  property bool resetArmed: false
  property string statusText: ""
  property bool statusError: false

  readonly property var rows: Keybindings.actionsForQuery(search.text, overrides, contextName)
  readonly property var currentRow: list.currentIndex >= 0 && list.currentIndex < rows.length ? rows[list.currentIndex] : null

  modal: true
  focus: true
  padding: Style.space(14)
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  width: Math.min(Style.space(540), Math.max(Style.space(300), (parent ? parent.width : Style.space(540)) - Style.space(24)))
  height: Math.min(Style.space(600), Math.max(Style.space(280), (parent ? parent.height : Style.space(600)) - Style.space(32)))
  x: parent ? Math.round((parent.width - width) / 2) : 0
  y: parent ? Math.round((parent.height - height) / 2) : 0

  background: Rectangle {
    radius: Style.cornerRadius
    color: Color.popups.background
    border.width: 1
    border.color: Color.accent
  }

  onOpened: {
    search.text = ""
    status("", false)
    list.currentIndex = 0
    Qt.callLater(function() { search.forceActiveFocus() })
  }
  onClosed: {
    recording = false
    resetArmed = false
  }
  onRowsChanged: if (list.currentIndex >= rows.length) list.currentIndex = rows.length - 1

  function status(text, isError) {
    root.statusText = text
    root.statusError = isError === true
  }

  function runCurrent() {
    var row = root.currentRow
    if (!row) return
    if (!row.available) {
      status("\"" + row.label + "\" isn't available on this screen.", true)
      return
    }
    root.close()
    root.triggered(row.id)
  }

  function commit(result, okText) {
    if (!result.ok) { status(result.error, true); return }
    root.overridesEdited(result.overrides)
    status(okText + (result.stolenFrom && result.stolenFrom.length ? " (taken from " + result.stolenFrom.join(", ") + ")" : ""), false)
  }

  function recordShortcut(event) {
    var row = root.currentRow
    if (!row) { root.recording = false; return }
    var chord = Keybindings.eventShortcut({
      key: event.key,
      text: event.text,
      ctrl: (event.modifiers & Qt.ControlModifier) !== 0,
      alt: (event.modifiers & Qt.AltModifier) !== 0,
      meta: (event.modifiers & Qt.MetaModifier) !== 0,
      shift: (event.modifiers & Qt.ShiftModifier) !== 0
    })
    if (chord === "") return   // modifier alone: keep waiting
    root.recording = false
    commit(Keybindings.rebind(root.overrides, row.id, chord), "\"" + row.label + "\" is now " + Keybindings.displayShortcut(chord))
  }

  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    if (root.recording) {
      if (event.key === Qt.Key_Escape) { root.recording = false; status("Rebinding cancelled.", false) }
      else recordShortcut(event)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true; return }
    if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N))) {
      list.currentIndex = Math.min(root.rows.length - 1, list.currentIndex + 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P))) {
      list.currentIndex = Math.max(0, list.currentIndex - 1)
      event.accepted = true
    } else if (event.key === Qt.Key_PageDown) {
      list.currentIndex = Math.min(root.rows.length - 1, list.currentIndex + 8)
      event.accepted = true
    } else if (event.key === Qt.Key_PageUp) {
      list.currentIndex = Math.max(0, list.currentIndex - 8)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.runCurrent()
      event.accepted = true
    } else if (ctrl && shift && event.key === Qt.Key_R) {
      if (!root.resetArmed) {
        root.resetArmed = true
        status("Press Ctrl+Shift+R again to restore every default shortcut.", true)
      } else {
        root.resetArmed = false
        commit({ ok: true, overrides: ({}) }, "All shortcuts restored to defaults")
      }
      event.accepted = true
      return
    } else if (ctrl && event.key === Qt.Key_E) {
      if (root.currentRow) {
        root.recording = true
        status("Press the new key for \"" + root.currentRow.label + "\" (Esc cancels).", false)
      }
      event.accepted = true
    } else if (ctrl && event.key === Qt.Key_R) {
      if (root.currentRow) commit(Keybindings.resetShortcut(root.overrides, root.currentRow.id), "\"" + root.currentRow.label + "\" restored to default")
      event.accepted = true
    } else if (ctrl && event.key === Qt.Key_U) {
      if (root.currentRow) commit(Keybindings.unbind(root.overrides, root.currentRow.id), "\"" + root.currentRow.label + "\" is now unbound")
      event.accepted = true
    }
    if (event.accepted) root.resetArmed = false
  }

  contentItem: ColumnLayout {
    spacing: Style.space(8)

    RowLayout {
      Layout.fillWidth: true
      Text {
        Layout.fillWidth: true
        text: "Keyboard shortcuts"
        color: Color.popups.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        textFormat: Text.PlainText
      }
      Text {
        text: "Esc to close"
        color: Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
    }

    TextField {
      id: search
      Layout.fillWidth: true
      placeholderText: "Search shortcuts…"
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      onTextChanged: list.currentIndex = 0
      Keys.onPressed: function(event) { root.handleKey(event) }
    }

    ListView {
      id: list
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: root.rows
      currentIndex: 0
      highlightMoveDuration: 0
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      section.property: "group"
      section.criteria: ViewSection.FullString
      section.delegate: Text {
        required property string section
        width: list.width
        topPadding: Style.space(6)
        bottomPadding: Style.space(2)
        text: section
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        textFormat: Text.PlainText
      }

      delegate: Rectangle {
        id: row
        required property var modelData
        required property int index
        readonly property bool current: ListView.isCurrentItem
        readonly property bool editing: root.recording && current
        width: list.width
        height: Style.space(30)
        radius: Style.cornerRadius
        color: current ? Util.alpha(Color.accent, 0.22) : "transparent"
        opacity: modelData.available ? 1 : 0.55

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            text: row.modelData.label
            color: Color.popups.text
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
          }
          Text {
            text: row.modelData.category
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
          Text {
            Layout.maximumWidth: list.width * 0.45
            text: row.editing ? "press a key…" : (row.modelData.customized ? "● " : "") + row.modelData.shortcut
            color: row.editing ? Color.urgent : Color.accent
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            textFormat: Text.PlainText
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: list.currentIndex = row.index
          onDoubleClicked: { list.currentIndex = row.index; root.runCurrent() }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: root.rows.length === 0
      horizontalAlignment: Text.AlignHCenter
      text: "No shortcuts match your search."
      color: Color.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
    }

    Text {
      Layout.fillWidth: true
      visible: root.statusText !== ""
      wrapMode: Text.WordWrap
      text: root.statusText
      color: root.statusError ? Color.urgent : Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }

    Text {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      text: "Enter run  ·  Ctrl+E rebind  ·  Ctrl+R default  ·  Ctrl+U unbind  ·  Ctrl+Shift+R reset all  ·  ● = customized"
      color: Color.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }
  }
}
