import QtQuick
import qs.Common
import qs.Widgets

// header (drag area, maximize, close) + the shared Updates / Tools panel
FocusScope {
    id: body

    property string startTab: "auto"
    property bool canMaximize: false
    property bool maximized: false
    property alias panel: panel

    signal headerPressed(var scene)
    signal headerMoved(var scene)
    signal headerDoubleClicked
    signal maximizeRequested
    signal closeRequested

    focus: true
    Keys.onEscapePressed: body.closeRequested()
    Component.onCompleted: {
        panel.pickInitialTab(body.startTab);
        Qt.callLater(panel.focusSearch);
    }

    Item {
        id: header
        x: Theme.spacingL
        y: Theme.spacingL
        width: parent.width - Theme.spacingL * 2
        height: Math.max(titleCol.implicitHeight, buttons.height)

        MouseArea {
            id: grip
            anchors.left: parent.left
            anchors.right: buttons.left
            height: parent.height
            cursorShape: Qt.SizeAllCursor
            onPressed: m => body.headerPressed(grip.mapToItem(null, m.x, m.y))
            onPositionChanged: m => {
                if (pressed)
                    body.headerMoved(grip.mapToItem(null, m.x, m.y));
            }
            onDoubleClicked: body.headerDoubleClicked()
        }

        Column {
            id: titleCol
            anchors.left: parent.left
            anchors.right: buttons.left
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXXS
            enabled: false   // clicks fall through to the drag area
            StyledText {
                text: "mise"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }
            StyledText {
                width: parent.width
                text: panel.summary
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                maximumLineCount: 1
            }
        }

        Row {
            id: buttons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            DankActionButton {
                visible: body.canMaximize
                iconName: body.maximized ? "fullscreen_exit" : "fullscreen"
                iconSize: Theme.iconSize - Theme.spacingXS
                iconColor: Theme.surfaceText
                onClicked: body.maximizeRequested()
            }

            DankActionButton {
                iconName: "close"
                iconSize: Theme.iconSize - Theme.spacingXS
                iconColor: Theme.surfaceText
                onClicked: body.closeRequested()
            }
        }
    }

    MisePanel {
        id: panel
        x: Theme.spacingL
        y: header.y + header.height + Theme.spacingM
        width: parent.width - Theme.spacingL * 2
        height: parent.height - y - Theme.spacingL
    }
}
