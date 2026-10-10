import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Expanded tool row: description, backend and installed versions, a prune chip for the versions no
// config uses, and a chip per version to pin.
Column {
    id: details

    required property string tool        // bare name
    property string scope: ""            // config the row belongs to ("" = global)
    property string fallback: ""         // shown when mise has no description yet
    property var info: ({})              // MiseInfo.info entry: meta / metaError / versions / versionsError
    property var chipVersions: []
    property var unused: []              // installed versions no tracked config uses
    property bool trackLatest: false
    property real chipH: Theme.iconSizeLarge - Theme.spacingXXS

    spacing: Theme.spacingXS

    StyledText {
        width: parent.width
        visible: text !== ""
        text: details.info.meta && details.info.meta.description ? details.info.meta.description : details.fallback
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceText
    }
    StyledText {
        width: parent.width
        text: details.info.meta ? "Backend: " + details.info.meta.backend + "\nInstalled: " + ((details.info.meta.installed_versions || []).join(", ") || "none") : (details.info.metaError || "Loading…")
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeSmall
        font.family: Theme.monoFontFamily
        color: Theme.surfaceVariantText
    }
    StyledText {
        width: parent.width
        visible: !details.info.versions
        text: details.info.versionsError || "Loading versions…"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }
    Flow {
        width: parent.width
        spacing: Theme.spacingXS
        visible: details.chipVersions.length > 0 || details.unused.length > 0

        // versions no tracked config uses: same shape as a version chip, with a broom
        Rectangle {
            visible: details.unused.length > 0
            width: Math.min(details.width, pruneRow.implicitWidth + Theme.spacingM * 2)
            height: details.chipH
            radius: Theme.cornerRadius
            color: pruneConfirm.armed ? Theme.error : (pruneArea.containsMouse && !MiseJobs.busy ? Theme.withAlpha(Theme.error, 0.15) : "transparent")
            border.width: 1
            border.color: pruneConfirm.armed ? Theme.error : Theme.withAlpha(Theme.outline, 0.4)
            opacity: MiseJobs.busy ? 0.5 : 1
            Row {
                id: pruneRow
                anchors.centerIn: parent
                spacing: Theme.spacingXXS
                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: pruneConfirm.armed ? "check" : "delete_sweep"
                    size: Theme.fontSizeMedium
                    color: pruneConfirm.armed ? Theme.surface : Theme.error
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pruneConfirm.armed ? "Remove " + details.unused.join(", ") + "?" : "Prune " + details.unused.length + " unused"
                    font.pixelSize: Theme.fontSizeSmall
                    color: pruneConfirm.armed ? Theme.surface : Theme.surfaceText
                }
            }
            MiseConfirm {
                id: pruneConfirm
                onConfirmed: MiseService.prune(details.tool)
            }
            MouseArea {
                id: pruneArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !MiseJobs.busy
                onClicked: pruneConfirm.click()
            }
        }

        Repeater {
            model: details.chipVersions
            MiseVersionChip {
                required property string modelData
                version: modelData
                tool: details.tool
                scope: details.scope
                chipH: details.chipH
                have: ((details.info.meta || {}).installed_versions || []).includes(modelData)
                inUse: ((details.info.meta || {}).active_versions || []).includes(modelData)
                removable: details.unused.includes(modelData)
                active: modelData === "latest" ? details.trackLatest : !details.trackLatest && inUse
            }
        }
    }
}
