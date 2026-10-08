import QtQuick
import qs.Common
import qs.Widgets

// What mise is doing right now: the job label and its last output line. Collapses when idle.
Rectangle {
    id: banner

    visible: MiseJobs.busy
    height: visible ? bannerCol.implicitHeight + Theme.spacingM * 2 : 0
    radius: Theme.cornerRadius
    color: Theme.withAlpha(Theme.primary, 0.10)
    border.width: 1
    border.color: Theme.withAlpha(Theme.primary, 0.30)

    Column {
        id: bannerCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Theme.spacingM
        spacing: 2
        Row {
            spacing: Theme.spacingS
            DankIcon {
                name: "sync"
                size: Theme.iconSize - 6
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: MiseJobs.label + "…"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        StyledText {
            width: parent.width
            text: MiseJobs.log.length ? MiseJobs.log[MiseJobs.log.length - 1] : ""
            font.pixelSize: Theme.fontSizeSmall
            font.family: Theme.monoFontFamily
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            maximumLineCount: 1
        }
    }
}
