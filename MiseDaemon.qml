import QtQuick
import Quickshell.Io
import qs.Common
import qs.Modals.Common
import qs.Modules.Plugins
import qs.Services

// Keybind panel:  dms ipc call mise toggle   (also: open, close)
// Two surfaces, picked in Settings -> "Keybind panel":
//   modal (default): DMS overlay, centered, closes on click outside; drag the header to move it.
//   window:          a real floating window like DMS's System Monitor. The compositor draws the
//                    border and rounding from your config; it moves and resizes natively.
//                    Needs DMS 1.6.0+ (DankFloatingWindow); on older versions the overlay is used.
PluginComponent {
    id: root

    // MiseWindow.qml only compiles on DMS 1.6.0+, where DankFloatingWindow exists
    readonly property bool windowSupported: winLoader.status === Loader.Ready
    readonly property bool windowMode: windowSupported && root.pluginData?.panelMode === "window"
    readonly property string startTab: root.pluginData?.panelTab ?? "auto"
    readonly property real panelW: Math.round(Theme.fontSizeMedium * 34)
    readonly property real panelH: Math.round(Theme.fontSizeMedium * 46)
    readonly property bool shown: windowMode ? winLoader.item.visible : modal.shouldBeVisible

    // modal only: where the user dragged it (kept until the shell restarts)
    property bool moved: false
    property point pos: Qt.point(0, 0)

    onWindowModeChanged: close()

    function open() {
        if (windowMode) {
            MiseService.refresh();
            winLoader.item.visible = true;
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
        if (winLoader.item)
            winLoader.item.visible = false;
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

    // ---- window mode ----
    Loader {
        id: winLoader
        source: Qt.resolvedUrl("MiseWindow.qml")
        onLoaded: {
            item.startTab = Qt.binding(() => root.startTab);
            item.panelW = Qt.binding(() => root.panelW);
            item.panelH = Qt.binding(() => root.panelH);
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

        MiseBody {
            width: modal.modalWidth
            height: modal.modalHeight
            startTab: root.startTab

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
