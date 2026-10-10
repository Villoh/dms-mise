import QtQuick
import qs.Common
import qs.Widgets

// One mise setting: name, description, and a switch (boolean) or a text field (anything else; arrays
// are comma separated). An edited field shows a save button (Enter does the same) in the slot that is
// the reset button for the ones set in the global config.
Rectangle {
    id: cfg

    required property var row       // an entry of MiseConfig.all
    property real rowH: Theme.fontSizeMedium + Theme.fontSizeSmall * 3 + Theme.spacingXL
    property real iconBtn: Theme.iconSize + Theme.spacingM
    property real actionIcon: Theme.iconSize - Theme.spacingXS
    readonly property bool isBool: row.type === "boolean"
    readonly property bool on: row.value === "true"
    readonly property bool dirty: !isBool && field.text !== row.value

    function save() {
        if (dirty)
            MiseConfig.set(row.key, field.text);
    }

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
        spacing: Theme.spacingS
        DankTextField {
            id: field
            visible: !cfg.isBool
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(cfg.width * 0.3)
            height: cfg.iconBtn
            text: cfg.row.value
            onAccepted: cfg.save()
        }
        DankToggle {
            visible: cfg.isBool
            anchors.verticalCenter: parent.verticalCenter
            hideText: true
            checked: cfg.on
            onToggled: MiseConfig.toggle(cfg.row.key)
        }
        // always laid out, so the control does not jump when a setting becomes (un)set or edited
        DankActionButton {
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: cfg.iconBtn
            iconSize: cfg.actionIcon
            iconName: cfg.dirty ? "check" : "undo"
            iconColor: cfg.dirty ? Theme.primary : Theme.surfaceVariantText
            opacity: cfg.dirty || cfg.row.set ? 1 : 0
            tooltipText: cfg.dirty ? "Save (Enter)" : "Reset to mise's default (removes it from your global config)"
            enabled: cfg.dirty || cfg.row.set
            onClicked: cfg.dirty ? cfg.save() : MiseConfig.unset(cfg.row.key)
        }
    }
}
