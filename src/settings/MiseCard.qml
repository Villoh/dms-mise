import QtQuick
import qs.Common
import qs.Widgets

// Settings card: DMS's SettingsCard header (icon + title + actions) on a plain surfaceContainer with a thin border like KDE Connect's settings
StyledRect {
    id: root

    property string title: ""
    property string iconName: ""

    default property alias content: contentColumn.children
    property alias headerActions: headerActionsRow.children

    width: parent?.width ?? 0
    height: mainColumn.implicitHeight + Theme.spacingL * 2
    radius: Theme.cornerRadius
    color: Theme.surfaceContainer
    border.width: 1
    border.color: Theme.outline

    Column {
        id: mainColumn
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingM

        Item {
            width: parent.width
            height: Math.max(headerIcon.height, headerText.height, headerActionsRow.height)

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingM

                DankIcon {
                    id: headerIcon
                    name: root.iconName
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    id: headerText
                    text: root.title
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                id: headerActionsRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.withAlpha(Theme.outline, 0.2)
        }

        Column {
            id: contentColumn
            width: parent.width
            spacing: Theme.spacingM
        }
    }
}
