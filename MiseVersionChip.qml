import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// One version of a tool in the details: click pins and installs it, the bin (installed, not active)
// removes it after a second click.
Rectangle {
    id: chip

    required property string version   // "latest" or a version
    required property string tool      // bare name, what `mise install tool@version` takes
    property string scope: ""          // config the pin goes to ("" = global)
    property bool have: false          // installed
    property bool inUse: false         // the active one
    property bool active: false        // what the config asks for
    property real chipH: Theme.iconSizeLarge - Theme.spacingXXS
    readonly property bool armed: chipConfirm.armed   // removing a version is two-step
    width: Theme.spacingM + verRow.implicitWidth + (trashBtn.visible ? Theme.spacingS + trashBtn.width + trashBtn.anchors.rightMargin : Theme.spacingM)
    height: chip.chipH
    radius: Theme.cornerRadius
    color: chipArea.containsMouse && !MiseJobs.busy ? Theme.primaryHoverLight : chip.active ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
    border.width: chip.active ? 2 : 1
    border.color: chip.active ? Theme.primary : Theme.withAlpha(Theme.outline, 0.4)
    opacity: MiseJobs.busy ? 0.5 : 1
    MiseConfirm {
        id: chipConfirm
        onConfirmed: MiseService.uninstallVersion(chip.tool, chip.version)
    }
    MouseArea {
        id: chipArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: !MiseJobs.busy
        onClicked: MiseService.install(chip.tool + "@" + chip.version, chip.scope)
    }
    Row {
        id: verRow
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXXS
        DankIcon {
            visible: chip.have
            anchors.verticalCenter: parent.verticalCenter
            name: "check"
            size: Theme.fontSizeSmall
            color: chip.active ? Theme.primary : Theme.surfaceVariantText
        }
        StyledText {
            text: chip.version
            font.pixelSize: Theme.fontSizeSmall
            font.family: Theme.monoFontFamily
            color: chip.have ? Theme.surfaceVariantText : Theme.primary
        }
    }
    // installed, not the active one (that one goes with the tool's own bin)
    Rectangle {
        id: trashBtn
        visible: chip.have && !chip.inUse
        anchors.right: parent.right
        anchors.rightMargin: (parent.height - height) / 2   // same gap on every side
        anchors.verticalCenter: parent.verticalCenter
        width: chip.chipH - Theme.spacingS
        height: width
        radius: Math.max(0, Math.min(parent.radius, parent.height / 2) - anchors.rightMargin)   // concentric with the chip
        color: chip.armed ? Theme.error : (trashArea.containsMouse ? Theme.withAlpha(Theme.error, 0.2) : "transparent")
        DankIcon {
            anchors.centerIn: parent
            name: chip.armed ? "check" : "delete"
            size: Theme.fontSizeMedium
            color: chip.armed ? Theme.surface : Theme.error
        }
        MouseArea {
            id: trashArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !MiseJobs.busy
            onClicked: chipConfirm.click()
        }
    }
}
