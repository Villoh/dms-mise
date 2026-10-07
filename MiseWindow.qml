import QtQuick
import qs.Common
import qs.Widgets

// Window mode of the keybind panel. Lives in its own file because DankFloatingWindow
// only exists in DMS 1.6.0+: on older versions this file fails to compile, and
// MiseDaemon / MiseSettings read that as "window mode not supported".
DankFloatingWindow {
    id: win

    property string startTab: "auto"
    property real panelW: 0
    property real panelH: 0

    objectName: "miseWindow"
    title: "mise"
    minimumSize: Qt.size(Math.round(Theme.fontSizeMedium * 28), Math.round(Theme.fontSizeMedium * 30))
    implicitWidth: panelW
    implicitHeight: panelH
    visible: false

    onClosed: win.visible = false
    onVisibleChanged: if (visible) {
        body.panel.pickInitialTab(body.startTab);
        Qt.callLater(body.panel.focusSearch);
    }

    MiseBody {
        id: body
        anchors.fill: parent
        startTab: win.startTab
        canMaximize: wc.canMaximize
        maximized: win.maximized
        onHeaderPressed: wc.tryStartMove()
        onHeaderDoubleClicked: wc.tryToggleMaximize()
        onMaximizeRequested: wc.tryToggleMaximize()
        onCloseRequested: win.visible = false
    }

    FloatingWindowControls {
        id: wc
        targetWindow: win
    }
}
