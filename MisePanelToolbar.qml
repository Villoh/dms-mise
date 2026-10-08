import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Top row of the panel: Updates / Tools / Settings tabs, the scope picker button (projects on), the fix button when
// the picked scope needs `mise trust` / `mise lock`, and refresh.
Item {
    id: toolbar

    property int count: 0            // pending updates, shown on the Updates tab
    property int tab: 0              // 0 = updates, 1 = tools, 2 = settings (mise settings: no scope, no fix)
    property string scope: ""
    property string scopeName: ""
    property bool menuOpen: false
    property bool fixOpen: false     // the fix list is open
    property string fixKind: ""      // "untrusted" | "unlocked" | "" = nothing to fix in the picked scope
    property int fixCount: 0         // how many scopes need it
    property int elsewhere: 0        // pending in scopes other than the picked one: dot on the button
    property bool checking: false
    property real controlH: Theme.iconSize + Theme.spacingL
    property real iconBtn: Theme.iconSize + Theme.spacingM
    signal tabPicked(int index)
    signal scopeClicked
    signal fixClicked

    height: controlH

    DankButtonGroup {
        id: toolbarTabs
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        buttonHeight: toolbar.iconBtn
        model: ["Updates" + (toolbar.count > 0 ? " (" + toolbar.count + ")" : ""), "Tools", "Settings"]
        currentIndex: toolbar.tab
        onSelectionChanged: (index, selected) => {
            if (selected)
                toolbar.tabPicked(index);
        }
    }

    // scope picker: one compact button instead of a chip row, so it scales to any number of projects
    Rectangle {
        id: scopeBtn
        visible: MiseProjects.mode !== "off" && toolbar.tab !== 2
        anchors.right: refreshBtn.left
        anchors.rightMargin: Theme.spacingXS
        anchors.verticalCenter: parent.verticalCenter
        height: toolbar.iconBtn
        // the label is what shrinks (elided) when the project name is long
        readonly property real maxLabelW: toolbar.width - toolbarTabs.width - refreshBtn.width - (fixBtn.visible ? fixBtn.width + Theme.spacingXS : 0) - Theme.spacingM * 4 - (Theme.iconSize - 6) * 2 - Theme.spacingXS * 2
        width: scopeBtnRow.implicitWidth + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: toolbar.menuOpen || scopeHover.containsMouse ? Theme.primaryHoverLight : Theme.surfaceContainerHigh
        border.width: toolbar.scope !== "*" ? 1 : 0
        border.color: Theme.primary
        // something is pending in a scope you are not looking at
        Rectangle {
            visible: toolbar.elsewhere > 0
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: -Theme.spacingXXS
            anchors.rightMargin: -Theme.spacingXXS
            width: Theme.spacingS + Theme.spacingXXS
            height: width
            radius: width / 2
            color: Theme.primary
            border.width: 1
            border.color: Theme.surface
        }
        MouseArea {
            id: scopeHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: toolbar.scopeClicked()
        }
        Row {
            id: scopeBtnRow
            anchors.centerIn: parent
            spacing: Theme.spacingXS
            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: toolbar.scope === "*" ? "layers" : (toolbar.scope === "" ? "public" : "folder")
                size: Theme.iconSize - 6
                color: toolbar.scope === "*" ? Theme.surfaceVariantText : Theme.primary
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, scopeBtn.maxLabelW)
                text: toolbar.scopeName
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                maximumLineCount: 1
            }
            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: toolbar.menuOpen ? "arrow_drop_up" : "arrow_drop_down"
                size: Theme.iconSize - 6
                color: Theme.surfaceVariantText
            }
        }
    }

    // what the warnings of the picked scope ask for: `mise trust` (paranoid) or `mise lock`. Opens the list of
    // projects to fix (MiseFixMenu).
    DankActionButton {
        id: fixBtn
        readonly property string kind: toolbar.fixKind
        visible: kind !== "" && toolbar.tab !== 2
        anchors.right: scopeBtn.visible ? scopeBtn.left : refreshBtn.left
        anchors.rightMargin: Theme.spacingXS
        anchors.verticalCenter: parent.verticalCenter
        buttonSize: toolbar.iconBtn
        iconName: toolbar.fixOpen ? "close" : (kind === "untrusted" ? "gpp_maybe" : "lock")
        iconColor: Theme.warning
        tooltipText: toolbar.fixCount > 1 ? toolbar.fixCount + " scopes need `mise trust` or `mise lock`: choose what to fix" : kind === "untrusted" ? "Not trusted: choose what to trust" : "Tools missing from the lockfile: choose what to lock"
        enabled: !MiseJobs.busy
        onClicked: toolbar.fixClicked()
    }

    // refresh: hover spins the icon, press shrinks, checking morphs to a circle with a spinner
    DankActionButton {
        id: refreshBtn
        readonly property bool active: toolbar.checking
        property bool hovered: false
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        buttonSize: toolbar.iconBtn
        iconName: ""   // the icon is drawn below so it can rotate
        tooltipText: "Check for updates"
        enabled: !toolbar.checking && !MiseJobs.busy
        opacity: enabled || active ? 1.0 : 0.5
        radius: active ? height / 2 : Theme.cornerRadius
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, hovered ? 0.3 : 0.15)
        scale: pressed ? 0.92 : (hovered && enabled ? 1.05 : 1.0)
        onEntered: hovered = true
        onExited: hovered = false
        onClicked: MiseService.refresh()

        Behavior on scale {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Easing.OutQuad
            }
        }
        // radius already animates via StyledRect's own Behavior
        Behavior on border.color {
            ColorAnimation {
                duration: Theme.popoutAnimationDuration
            }
        }

        DankIcon {
            anchors.centerIn: parent
            name: "refresh"
            size: refreshBtn.iconSize
            color: Theme.primary
            smoothTransform: true
            visible: !refreshBtn.active
            rotation: refreshBtn.hovered && refreshBtn.enabled ? 180 : 0

            Behavior on rotation {
                NumberAnimation {
                    duration: Theme.popoutAnimationDuration
                    easing.type: Easing.OutBack
                }
            }
        }

        DankSpinner {
            anchors.centerIn: parent
            size: Theme.iconSize - 6
            color: Theme.primary
            visible: refreshBtn.active
        }
    }
}
