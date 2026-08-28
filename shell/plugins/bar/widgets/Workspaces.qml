import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // 1-5 are always offered; any other workspace appears once Hyprland has
  // created it, however high its id. Special workspaces carry negative ids
  // and stay out.
  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  readonly property int highestWorkspaceId: {
    var ids = root.workspaceIds()
    return ids[ids.length - 1]
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // Names come from this widget's shell.json entry, keyed by workspace id:
  //   { "id": "omarchy.workspaces", "names": { "1": "term", "2": "web" } }
  // omarchy-hyprland-workspace-name writes them; the bar patches settings in
  // place, so a rename lands without a restart. A hand-edited name longer
  // than the command allows is cut rather than left to widen the bar.
  readonly property int maxNameLength: 16
  readonly property var names: root.setting("names", {})

  function nameFor(id) {
    var value = names && typeof names === "object" ? names[String(id)] : undefined
    if (typeof value !== "string") return ""
    return value.length > maxNameLength ? value.slice(0, maxNameLength - 1) + "\u2026" : value
  }

  // The widget id is the layout entry the names sit on, so a cloned widget
  // edits its own entry rather than the built-in one.
  function runNameCommand(args) {
    if (!root.bar) return
    root.bar.run("omarchy-hyprland-workspace-name " + args + " --widget " + Util.shellQuote(root.moduleName))
  }

  // Drops the name and lets the workspace disappear once empty. Windows on it
  // stay where they are.
  function forgetWorkspace(id) {
    if (!root.bar) return
    root.bar.run("omarchy-hyprland-workspace-forget " + id + " --widget " + Util.shellQuote(root.moduleName))
  }

  // An optional trailing "+" that adds the next workspace, kept alive until
  // its windows arrive. Off by default: the stock bar stays as it is.
  //   { "id": "omarchy.workspaces", "addButton": true }
  readonly property bool addButton: root.setting("addButton", false) === true

  function addWorkspace(withName) {
    if (!root.bar) return
    root.bar.run("omarchy-hyprland-workspace-add" + (withName ? " --name" : "") + " --widget " + Util.shellQuote(root.moduleName))
  }

  // A config reload replays the saved rules, which can create or drop several
  // workspaces at once. Re-read the list rather than trust that every event
  // of that burst arrived; a missed one leaves a kept workspace without a
  // tile until the shell restarts.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") Hyprland.refreshWorkspaces()
    }
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length + (root.addButton ? 1 : 0)
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        // 10 is written as "0" after its SUPER+0 key, but only while it ends
        // the row: between 9 and 11 a literal "10" reads as the number it is.
        readonly property string numeral: (modelData === 10 && root.highestWorkspaceId <= 10) ? "0" : String(modelData)
        // The focus dot stands in for a numeral the keyboard already knows;
        // past 10 there is no key, so the number is the only identification.
        readonly property bool keyed: modelData <= 10
        // A vertical bar is too narrow for words, so it keeps the numbers.
        readonly property string wsName: root.vertical ? "" : root.nameFor(modelData)

        bar: root.bar
        // A name is never hidden behind the focus dot.
        text: wsName !== "" ? wsName : (focused && keyed ? "\uDB85\uDCFB" : numeral)
        // A tile that keeps its text under focus marks the focus by colour.
        active: focused && (wsName !== "" || !keyed)
        // The number a name stands for, and the key that reaches it.
        tooltipText: wsName !== "" ? numeral : ""
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : (wsName !== "" ? -1 : Style.space(20))
        fixedHeight: root.barSize
        onPressed: function(button) {
          if (button === Qt.RightButton) root.runNameCommand("--prompt " + modelData)
          else if (button === Qt.MiddleButton) root.forgetWorkspace(modelData)
          else root.focusWorkspace(modelData)
        }
      }
    }

    // Faint until hovered, so it reads as an action rather than a workspace.
    // Right-click adds and asks for the name in one go.
    WidgetButton {
      visible: root.addButton
      bar: root.bar
      text: "+"
      tooltipText: "Add a workspace"
      opacity: tooltipHovered ? 1 : 0.3
      horizontalMargin: 6
      verticalPadding: 6
      fixedWidth: root.vertical ? root.barSize : Style.space(20)
      fixedHeight: root.barSize
      onPressed: function(button) { root.addWorkspace(button === Qt.RightButton) }
    }
  }
}
