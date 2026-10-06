import QtQuick
import Quickshell.Io
import qs.Common
import qs.Modals.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

// Keybind panel:  dms ipc call mise toggle   (also: open, close)
// Two surfaces, picked in Settings -> "Keybind panel":
//   modal (default): DMS overlay, centered, closes on click outside; drag the header to move it.
//   window:          a real floating window like DMS's System Monitor. The compositor draws the
//                    border and rounding from your config; it moves and resizes natively.
PluginComponent {
    id: root

    readonly property bool windowMode: root.pluginData?.panelMode === "window"
    readonly property real panelW: Math.round(Theme.fontSizeMedium * 34)
    readonly property real panelH: Math.round(Theme.fontSizeMedium * 46)
    readonly property bool shown: windowMode ? win.visible : modal.shouldBeVisible

    // modal only: where the user dragged it (kept until the shell restarts)
    property bool moved: false
    property point pos: Qt.point(0, 0)

    onWindowModeChanged: close()

    function open() {
        if (windowMode) {
            MiseService.refresh();
            win.visible = true;
            return "opened";
        }
        const screen = CompositorService.getFocusedScreen();
        if (!screen)
            return "No active screen";
        modal.targetScreen = screen;
        MiseService.refresh();
        modal.open();
        return "opened";
    }

    function close() {
        win.visible = false;
        if (modal.shouldBeVisible)
            modal.close();
        return "closed";
    }

    IpcHandler {
        target: "mise"

        function open(): string {
            return root.open();
        }
        function close(): string {
            return root.close();
        }
        function toggle(): string {
            return root.shown ? root.close() : root.open();
        }
    }

    // header (drag area, maximize, close) + the shared Tools panel
    component Body: FocusScope {
        id: body

        property bool canMaximize: false
        property bool maximized: false
        property alias panel: panel

        signal headerPressed(var scene)
        signal headerMoved(var scene)
        signal headerDoubleClicked
        signal maximizeRequested
        signal closeRequested

        focus: true
        Keys.onEscapePressed: body.closeRequested()
        Component.onCompleted: Qt.callLater(panel.focusSearch)

        Item {
            id: header
            x: Theme.spacingL
            y: Theme.spacingL
            width: parent.width - Theme.spacingL * 2
            height: Math.max(titleCol.implicitHeight, buttons.height)

            MouseArea {
                id: grip
                anchors.left: parent.left
                anchors.right: buttons.left
                height: parent.height
                onPressed: m => body.headerPressed(grip.mapToItem(null, m.x, m.y))
                onPositionChanged: m => {
                    if (pressed)
                        body.headerMoved(grip.mapToItem(null, m.x, m.y));
                }
                onDoubleClicked: body.headerDoubleClicked()
            }

            Column {
                id: titleCol
                anchors.left: parent.left
                anchors.right: buttons.left
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXXS
                enabled: false   // clicks fall through to the drag area
                StyledText {
                    text: "mise"
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                }
                StyledText {
                    width: parent.width
                    text: panel.summary
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                }
            }

            Row {
                id: buttons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                DankActionButton {
                    visible: body.canMaximize
                    iconName: body.maximized ? "fullscreen_exit" : "fullscreen"
                    iconSize: Theme.iconSize - Theme.spacingXS
                    iconColor: Theme.surfaceText
                    onClicked: body.maximizeRequested()
                }

                DankActionButton {
                    iconName: "close"
                    iconSize: Theme.iconSize - Theme.spacingXS
                    iconColor: Theme.surfaceText
                    onClicked: body.closeRequested()
                }
            }
        }

        MisePanel {
            id: panel
            toolsOnly: true
            x: Theme.spacingL
            y: header.y + header.height + Theme.spacingM
            width: parent.width - Theme.spacingL * 2
            height: parent.height - y - Theme.spacingL
        }
    }

    // ---- window mode ----
    DankFloatingWindow {
        id: win
        objectName: "miseWindow"
        title: "mise"
        minimumSize: Qt.size(Math.round(Theme.fontSizeMedium * 28), Math.round(Theme.fontSizeMedium * 30))
        implicitWidth: root.panelW
        implicitHeight: root.panelH
        visible: false

        onClosed: win.visible = false
        onVisibleChanged: if (visible)
            Qt.callLater(winBody.panel.focusSearch)

        Body {
            id: winBody
            anchors.fill: parent
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

    // ---- modal mode ----
    DankModal {
        id: modal
        layerNamespace: "dms:plugins:mise"
        modalWidth: root.panelW
        modalHeight: root.panelH
        positioning: root.moved ? "custom" : "center"
        customPosition: root.pos
        showBackground: true
        useOverlayLayer: true
        enableShadow: true
        cornerRadius: Theme.cornerRadiusLarge
        shouldBeVisible: false
        content: modalContent
        onBackgroundClicked: modal.close()
    }

    Component {
        id: modalContent

        Body {
            width: modal.modalWidth
            height: modal.modalHeight

            property var grab: Qt.point(0, 0)
            property var start: Qt.point(0, 0)

            onHeaderPressed: s => {
                grab = s;
                start = Qt.point(modal.alignedX, modal.alignedY);
            }
            onHeaderMoved: s => {
                const x = Math.max(0, Math.min(modal.screenWidth - modal.alignedWidth, start.x + s.x - grab.x));
                const y = Math.max(0, Math.min(modal.screenHeight - modal.alignedHeight, start.y + s.y - grab.y));
                root.pos = Qt.point(x, y);
                root.moved = true;
            }
            onHeaderDoubleClicked: root.moved = false
            onCloseRequested: modal.close()
        }
    }
}
