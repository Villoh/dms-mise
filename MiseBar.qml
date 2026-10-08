import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "mise"
    popoutWidth: 540
    popoutHeight: 600

    // what the badge counts: global only (default) or every followed project too (Settings > Project tools)
    readonly property int count: MiseService.badgeOutdated.length
    readonly property bool working: MiseJobs.busy || MiseService.checking
    readonly property int bumpCount: MiseService.badgeBumps.length
    // primary = updates, warning (orange) = only bumps pending
    readonly property color pillColor: MiseService.error ? Theme.error : (count > 0 ? Theme.primary : (bumpCount > 0 ? Theme.warning : Theme.surfaceVariantText))

    // chef hat from the Material Symbols font DMS ships, so it renders like the other bar icons.
    // Inline: a new type in qmldir is not picked up by `plugins reload`.
    component MiseIcon: Item {
        id: ic

        property int size: Theme.iconSize
        property color color: "white"
        property bool pulse: false

        implicitWidth: size
        implicitHeight: size

        DankIcon {
            anchors.centerIn: parent
            name: "chef_hat"
            size: ic.size
            color: ic.color
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
            // the hat glyph has air inside its box, the digit has none: without this the whole thing
            // sits to the right of the pill's centre
            rightPadding: root.count > 0 || root.bumpCount > 0 ? Math.round(root.iconSize * 0.15) : 0
            MiseIcon {
                size: root.iconSize
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
                // a digit has no descender: the centre of its line box sits ~1px above the glyph
                anchors.verticalCenterOffset: 1
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
                    anchors.verticalCenterOffset: 1
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            MiseIcon {
                size: root.iconSize
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
