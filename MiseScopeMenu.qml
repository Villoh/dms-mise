import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Scope picker: Global / All / each followed project, with its pending count and a Stop-following button,
// then "Add project…" (folder browser, or a typed path in place). The owner positions it and holds the scrim.
Rectangle {
    id: menu

    property var options: []          // [{key, label}]: "*" = everything, "" = global, else a config path
    property string scope: ""
    property var pendingIn: key => 0
    // updates waiting in a scope, shown next to its name
    property real controlH: Theme.iconSize + Theme.spacingL
    property real iconBtn: Theme.iconSize + Theme.spacingM
    property real actionIcon: Theme.iconSize - Theme.spacingXS
    property bool adding: false       // the "type a path" field has replaced the Add row
    signal picked(string key)
    signal browse
    signal addTyped(string path)

    function reset() {
        adding = false;
        addField.text = "";
        addErr.text = "";
    }

    // MiseProjects.addFailed: shown under the field while it is open
    function showError(message) {
        if (adding)
            addErr.text = message;
    }

    height: menuCol.implicitHeight + Theme.spacingXS * 2
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHigh
    border.width: 1
    border.color: Theme.withAlpha(Theme.outline, 0.3)

    Column {
        id: menuCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacingXS
        spacing: Theme.spacingXXS

        // at most ~6 rows tall, scrolls beyond that
        DankFlickable {
            id: optFlick
            width: parent.width
            height: Math.min(optCol.implicitHeight, menu.controlH * 6)
            contentHeight: optCol.implicitHeight
            clip: true

            Column {
                id: optCol
                // leave a gutter for the scrollbar so it doesn't touch the row buttons
                width: optFlick.width - (optFlick.contentHeight > optFlick.height ? Theme.spacingS : 0)
                Repeater {
                    model: menu.options
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: menu.scope === modelData.key
                        readonly property bool isProject: modelData.key !== "*" && modelData.key !== ""
                        width: optCol.width
                        height: menu.controlH
                        radius: Theme.cornerRadius
                        color: optHover.containsMouse ? Theme.primaryHoverLight : "transparent"
                        MouseArea {
                            id: optHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: menu.picked(modelData.key)
                        }
                        DankIcon {
                            id: optIcon
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            name: parent.active ? "check" : (modelData.key === "*" ? "layers" : (modelData.key === "" ? "public" : "folder"))
                            size: Theme.iconSize - 6
                            color: parent.active ? Theme.primary : Theme.surfaceVariantText
                        }
                        StyledText {
                            anchors.left: optIcon.right
                            anchors.leftMargin: Theme.spacingS
                            anchors.right: optCount.visible ? optCount.left : (optRemove.visible ? optRemove.left : parent.right)
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: parent.active ? Font.Medium : Font.Normal
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                        }
                        // how many updates are waiting in this scope
                        StyledText {
                            id: optCount
                            visible: menu.pendingIn(modelData.key) > 0
                            anchors.right: optRemove.visible ? optRemove.left : parent.right
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            text: menu.pendingIn(modelData.key)
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.monoFontFamily
                            color: Theme.primary
                        }
                        // stop following: only edits the plugin's list, the config file is never touched
                        DankActionButton {
                            id: optRemove
                            visible: parent.isProject
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingXXS
                            anchors.verticalCenter: parent.verticalCenter
                            buttonSize: menu.iconBtn - Theme.spacingXS
                            iconSize: menu.actionIcon - Theme.spacingXS
                            iconName: "close"
                            iconColor: Theme.surfaceVariantText
                            tooltipText: "Stop following (the config file is not touched)"
                            onClicked: MiseProjects.remove(modelData.key)
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.withAlpha(Theme.outline, 0.2)
        }

        // "Add project…" row, which turns into the input in place
        Rectangle {
            visible: !menu.adding
            width: parent.width
            height: menu.controlH
            radius: Theme.cornerRadius
            color: addHover.containsMouse ? Theme.primaryHoverLight : "transparent"
            MouseArea {
                id: addHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: menu.browse()
            }
            // the row opens the folder browser; this is the way to paste a path or a config file
            DankActionButton {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingXXS
                anchors.verticalCenter: parent.verticalCenter
                buttonSize: menu.iconBtn - Theme.spacingXS
                iconSize: menu.actionIcon - Theme.spacingXS
                iconName: "keyboard"
                iconColor: Theme.surfaceVariantText
                tooltipText: "Type a path instead"
                onClicked: {
                    menu.adding = true;
                    addField.forceActiveFocus();
                }
            }
            DankIcon {
                id: addIcon
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                name: "add"
                size: Theme.iconSize - 6
                color: Theme.primary
            }
            StyledText {
                anchors.left: addIcon.right
                anchors.leftMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: "Add project…"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.primary
            }
        }

        Column {
            visible: menu.adding
            width: parent.width
            spacing: Theme.spacingXXS
            DankTextField {
                id: addField
                width: parent.width
                height: menu.controlH
                leftIconName: "folder"
                placeholderText: "Folder or mise config path, Enter"
                onTextEdited: addErr.text = ""
                onAccepted: menu.addTyped(text)
            }
            StyledText {
                id: addErr
                width: parent.width
                visible: text !== ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
                wrapMode: Text.WordWrap
            }
        }
    }
}
