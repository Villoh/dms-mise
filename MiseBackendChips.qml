import QtQuick
import qs.Common
import qs.Widgets

// One row of pill chips that scrolls sideways: a filter with a single active key.
Flickable {
    id: chips

    property var options: []      // [{key, label}]
    property string current: ""   // the active key
    property real chipH: Theme.iconSizeLarge - Theme.spacingXXS
    signal picked(string key)

    height: visible ? chipH : 0
    contentWidth: chipRow.width
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Row {
        id: chipRow
        spacing: Theme.spacingXS
        Repeater {
            model: chips.options
            delegate: Rectangle {
                required property var modelData
                readonly property bool active: chips.current === modelData.key
                height: chips.chipH
                width: chipLabel.implicitWidth + Theme.spacingM * 2
                radius: height / 2
                color: active ? Theme.primary : Theme.surfaceContainerHigh
                StyledText {
                    id: chipLabel
                    anchors.centerIn: parent
                    text: modelData.label
                    font.pixelSize: Theme.fontSizeSmall
                    color: parent.active ? Theme.primaryText : Theme.surfaceText
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: chips.picked(modelData.key)
                }
            }
        }
    }
}
