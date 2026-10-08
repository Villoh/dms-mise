import QtQuick
import qs.Common
import qs.Widgets

// One mise setting: name, description, and a switch (boolean) or a text field (anything else, Enter
// applies; arrays are comma separated). Reset shows for the ones set in the global config.
Rectangle {
    id: cfg

    required property var row       // an entry of MiseConfig.all
    property real rowH: Theme.fontSizeMedium + Theme.fontSizeSmall * 3 + Theme.spacingXL
    property real iconBtn: Theme.iconSize + Theme.spacingM
    property real actionIcon: Theme.iconSize - Theme.spacingXS
    readonly property bool isBool: row.type === "boolean"
    readonly property bool on: row.value === "true"

    height: rowH
    radius: Theme.cornerRadius
    color: cfgHover.containsMouse ? Theme.primaryHoverLight : "transparent"
    MouseArea {
        id: cfgHover
        anchors.fill: parent
        hoverEnabled: true
    }
    Column {
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingM
        anchors.right: cfgCtl.left
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        StyledText {
            width: parent.width
            text: cfg.row.key
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: cfg.row.set ? Theme.primary : Theme.surfaceText
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            maximumLineCount: 1
        }
        StyledText {
            width: parent.width
            text: cfg.row.desc
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
            wrapMode: Text.WordWrap
            maximumLineCount: 2
        }
    }
    Row {
        id: cfgCtl
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingXS
        anchors.verticalCenter: parent.verticalCenter
        DankTextField {
            visible: !cfg.isBool
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(cfg.width * 0.3)
            height: cfg.iconBtn
            text: cfg.row.value
            onAccepted: {
                if (text !== cfg.row.value)
                    MiseConfig.set(cfg.row.key, text);
            }
        }
        DankToggle {
            visible: cfg.isBool
            anchors.verticalCenter: parent.verticalCenter
            hideText: true
            checked: cfg.on
            onToggled: MiseConfig.toggle(cfg.row.key)
        }
        // always laid out, so the control does not jump when a setting becomes (un)set
        DankActionButton {
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: cfg.iconBtn
            iconSize: cfg.actionIcon
            iconName: "undo"
            iconColor: Theme.surfaceVariantText
            opacity: cfg.row.set ? 1 : 0
            tooltipText: "Reset to mise's default (removes it from your global config)"
            enabled: cfg.row.set
            onClicked: MiseConfig.unset(cfg.row.key)
        }
    }
}
