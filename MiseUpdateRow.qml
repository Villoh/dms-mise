import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// One pending update / bump, or one ignored entry: name, "current → latest", and the skip / ignore /
// update buttons (undo for ignored ones).
Rectangle {
    id: upd

    required property var row       // an entry of the panel's updRows / ignoredRows
    property bool showScope: false  // append the project name (looking at every scope)
    property real rowH: Theme.fontSizeMedium + Theme.fontSizeSmall + Theme.spacingXL + Theme.spacingXS
    property real iconBtn: Theme.iconSize + Theme.spacingM
    property real actionIcon: Theme.iconSize - Theme.spacingXS

    height: rowH
    radius: Theme.cornerRadius
    color: updHover.containsMouse ? Theme.primaryHoverLight : "transparent"
    MouseArea {
        id: updHover
        anchors.fill: parent
        hoverEnabled: true
    }
    DankIcon {
        id: updIcon
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        name: upd.row.ignoredKey ? "visibility_off" : (upd.row.bump ? "upgrade" : "arrow_circle_up")
        size: Theme.iconSize - 4
        color: upd.row.ignoredKey ? Theme.surfaceVariantText : (upd.row.bump ? Theme.warning : Theme.primary)
    }
    Column {
        anchors.left: updIcon.right
        anchors.leftMargin: Theme.spacingM
        anchors.right: updBtns.left
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        StyledText {
            width: parent.width
            text: upd.row.name
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: upd.row.ignoredKey ? Theme.surfaceVariantText : Theme.surfaceText
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            maximumLineCount: 1
        }
        StyledText {
            width: parent.width
            text: upd.row.ignoredKey ? (upd.row.latest ? "skipping " + upd.row.latest : "ignored · all versions") + (upd.row.scoped ? " · " + MiseProjects.label(upd.row.scope) : "") : (upd.row.current ? upd.row.current + " → " : "not installed → ") + upd.row.latest + (upd.row.bump ? " · bump (requested " + upd.row.requested + ")" : "") + (upd.showScope ? " · " + MiseProjects.label(upd.row.scope) : "")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            maximumLineCount: 1
        }
    }
    Row {
        id: updBtns
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingXS
        anchors.verticalCenter: parent.verticalCenter
        DankActionButton {
            visible: !!upd.row.ignoredKey
            buttonSize: upd.iconBtn
            iconSize: upd.actionIcon
            iconName: "undo"
            iconColor: Theme.primary
            tooltipText: "Stop ignoring"
            onClicked: MiseService.unignore(upd.row.ignoredKey)
        }
        DankActionButton {
            visible: !upd.row.ignoredKey
            buttonSize: upd.iconBtn
            iconSize: upd.actionIcon
            iconName: "skip_next"
            iconColor: Theme.surfaceVariantText
            tooltipText: "Skip " + upd.row.latest + " (shows again with a newer version)"
            onClicked: MiseService.ignore(upd.row.name, upd.row.latest, upd.row.scope)
        }
        DankActionButton {
            visible: !upd.row.ignoredKey
            buttonSize: upd.iconBtn
            iconSize: upd.actionIcon
            iconName: "visibility_off"
            iconColor: Theme.surfaceVariantText
            tooltipText: "Ignore " + upd.row.name + " (all versions, " + MiseProjects.label(upd.row.scope) + " only)"
            onClicked: MiseService.ignore(upd.row.name, "", upd.row.scope)
        }
        DankActionButton {
            visible: !upd.row.ignoredKey
            buttonSize: upd.iconBtn
            iconSize: upd.actionIcon
            iconName: upd.row.bump ? "upgrade" : "download"
            iconColor: upd.row.bump ? Theme.warning : Theme.primary
            tooltipText: upd.row.bump ? "Bump: rewrites \"" + upd.row.requested + "\" in your " + (upd.row.scope ? "project's" : "global") + " mise config" : (upd.row.current ? "Update" : "Install")
            enabled: !MiseJobs.busy
            onClicked: upd.row.bump ? MiseService.bump(upd.row.name, upd.row.scope) : MiseService.upgrade(upd.row.name, upd.row.scope)
        }
    }
}
