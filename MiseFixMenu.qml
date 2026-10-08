import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// What the fix button runs: the scopes that need `mise trust` (paranoid) and the ones that need `mise lock`, in
// two sections, a checkbox each, and one button for the checked ones. The owner positions it and holds the scrim.
// Trust is a decision per project: with several, none starts checked. Lock starts with all of them.
Rectangle {
    id: menu

    property var scopes: []           // config paths ("" = global); MiseService.warnOf says what each needs
    property real controlH: Theme.iconSize + Theme.spacingL
    property var checked: ({})        // scope -> true, set by open()
    readonly property var trustScopes: scopes.filter(s => MiseService.warnOf(s) === "untrusted")
    readonly property var lockScopes: scopes.filter(s => MiseService.warnOf(s) !== "untrusted")
    readonly property var picked: scopes.filter(s => checked[s])
    readonly property int trusts: trustScopes.filter(s => checked[s]).length
    signal run(var scopes)

    // the state is rebuilt only here: the list of scopes is a new array on every refresh, and must not reset it
    function open() {
        checked = scopes.reduce((m, s) => Object.assign(m, {
                [s]: MiseService.warnOf(s) !== "untrusted" || scopes.length === 1
            }), {});
    }

    function toggle(s) {
        checked = Object.assign({}, checked, {
            [s]: !checked[s]
        });
    }

    // check all of a section, or uncheck them when they already are
    function toggleAll(list) {
        const on = list.some(s => !checked[s]);
        checked = Object.assign({}, checked, list.reduce((m, s) => Object.assign(m, {
                [s]: on
            }), {}));
    }

    // a titled list of scopes with its own check-all
    component Section: Column {
        id: sec
        property string title: ""
        property var list: []
        readonly property bool all: list.every(s => menu.checked[s])
        visible: list.length > 0
        width: parent.width

        Item {
            width: parent.width
            height: menu.controlH
            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingS
                anchors.right: allBtn.left
                anchors.verticalCenter: parent.verticalCenter
                text: sec.title
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                maximumLineCount: 1
            }
            DankActionButton {
                id: allBtn
                visible: sec.list.length > 1
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                buttonSize: menu.controlH - Theme.spacingXS
                iconName: sec.all ? "deselect" : "select_all"
                iconColor: Theme.surfaceVariantText
                tooltipText: sec.all ? "Uncheck all" : "Check all"
                onClicked: menu.toggleAll(sec.list)
            }
        }

        Repeater {
            model: sec.list
            delegate: Rectangle {
                required property var modelData
                width: sec.width
                height: menu.controlH
                radius: Theme.cornerRadius
                color: rowHover.containsMouse ? Theme.primaryHoverLight : "transparent"
                MouseArea {
                    id: rowHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: menu.toggle(modelData)
                }
                DankIcon {
                    id: box
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    name: menu.checked[modelData] ? "check_box" : "check_box_outline_blank"
                    size: Theme.iconSize - 4
                    color: menu.checked[modelData] ? Theme.primary : Theme.surfaceVariantText
                }
                Column {
                    anchors.left: box.right
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    StyledText {
                        width: parent.width
                        text: MiseProjects.label(modelData)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        maximumLineCount: 1
                    }
                    // the file you would trust: the same name can be two different projects
                    StyledText {
                        width: parent.width
                        visible: modelData !== ""
                        text: modelData
                        font.pixelSize: Theme.fontSizeSmall - 2
                        font.family: Theme.monoFontFamily
                        color: Theme.surfaceVariantText
                        elide: Text.ElideMiddle
                        wrapMode: Text.NoWrap
                        maximumLineCount: 1
                    }
                }
            }
        }
    }

    height: col.implicitHeight + Theme.spacingXS * 2
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHigh
    border.width: 1
    border.color: Theme.withAlpha(Theme.outline, 0.3)

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacingXS
        spacing: Theme.spacingXXS

        // scrolls beyond ~8 rows
        DankFlickable {
            width: parent.width
            height: Math.min(sections.implicitHeight, menu.controlH * 8)
            contentHeight: sections.implicitHeight
            clip: true

            Column {
                id: sections
                width: parent.width
                Section {
                    title: "Trust · only configs you wrote or reviewed"
                    list: menu.trustScopes
                }
                Rectangle {
                    visible: menu.trustScopes.length > 0 && menu.lockScopes.length > 0
                    width: parent.width
                    height: 1
                    color: Theme.withAlpha(Theme.outline, 0.2)
                }
                Section {
                    title: "Lock · tools missing from the lockfile"
                    list: menu.lockScopes
                }
            }
        }

        DankButton {
            width: parent.width
            text: menu.picked.length === 0 ? "Check what to fix" : [menu.trusts > 0 ? "Trust " + menu.trusts : "", menu.picked.length - menu.trusts > 0 ? "Lock " + (menu.picked.length - menu.trusts) : ""].filter(x => x).join(" \u00b7 ")
            iconName: menu.trusts > 0 ? "gpp_maybe" : "lock"
            buttonHeight: menu.controlH
            enabled: menu.picked.length > 0 && !MiseJobs.busy
            onClicked: menu.run(menu.picked)
        }
    }
}
