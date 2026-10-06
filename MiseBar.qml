import QtQuick
import qs.Common
import qs.Widgets
import QtQuick.Effects
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "mise"
    popoutWidth: 460
    popoutHeight: 600

    // what the badge counts: global only (default) or every followed project too (Settings > Project tools)
    readonly property int count: MiseService.badgeOutdated.length
    readonly property bool working: MiseService.busy || MiseService.checking
    readonly property int bumpCount: MiseService.badgeBumps.length
    // primary = updates, warning (orange) = only bumps pending
    readonly property color pillColor: MiseService.error ? Theme.error : (count > 0 ? Theme.primary : (bumpCount > 0 ? Theme.warning : Theme.surfaceVariantText))

    // mise logo (assets/mise.svg, black line art) recoloured to a theme colour.
    // Inline: a new type in qmldir is not picked up by `plugins reload`.
    component MiseIcon: Item {
        id: ic

        property int size: Theme.iconSize
        property color color: "white"
        property bool pulse: false

        implicitWidth: size
        implicitHeight: size

        // Qt5Compat is not installed with DMS: tint via a colour rect masked by the logo.
        Image {
            id: logo
            anchors.fill: parent
            source: Qt.resolvedUrl("assets/mise.svg")
            sourceSize.width: ic.size * 2
            sourceSize.height: ic.size * 2
            fillMode: Image.PreserveAspectFit
            smooth: true
            visible: false
            layer.enabled: true
        }

        Rectangle {
            anchors.fill: parent
            color: ic.color
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: logo
            }
        }

        SequentialAnimation on opacity {
            running: ic.pulse
            loops: Animation.Infinite
            onRunningChanged: if (!running)
                ic.opacity = 1
            NumberAnimation {
                to: 0.35
                duration: 600
            }
            NumberAnimation {
                to: 1
                duration: 600
            }
        }
    }

    // touching the singleton instantiates it (lazy) and starts polling
    Component.onCompleted: MiseService.refresh()

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            MiseIcon {
                size: root.iconSize + 2
                color: root.pillColor
                pulse: root.working
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                visible: root.count > 0
                text: root.count
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            Row {
                visible: root.bumpCount > 0
                spacing: 1
                anchors.verticalCenter: parent.verticalCenter
                DankIcon {
                    name: "arrow_upward"
                    size: root.iconSize - 4
                    color: Theme.warning
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: root.bumpCount
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.warning
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            MiseIcon {
                size: root.iconSize + 2
                color: root.pillColor
                pulse: root.working
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                visible: root.count > 0
                text: root.count
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.primary
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Row {
                visible: root.bumpCount > 0
                spacing: 1
                anchors.horizontalCenter: parent.horizontalCenter
                DankIcon {
                    name: "arrow_upward"
                    size: root.iconSize - 6
                    color: Theme.warning
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: root.bumpCount
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.warning
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: pop
            headerText: "mise"
            detailsText: panel.summary
            showCloseButton: true

            MisePanel {
                id: panel
                width: parent.width
                implicitHeight: root.popoutHeight - pop.headerHeight - pop.detailsHeight - Theme.spacingXL
            }
        }
    }
}
