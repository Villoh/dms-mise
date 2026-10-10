import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// One tool of the Tools tab: installed (version, details, remove), installable (download), or the
// `http:` template row that expands into the install form.
Rectangle {
    id: row

    required property var modelData              // an entry of the panel's toolList
    property bool open: false                    // expanded: details, or the http: form for the template row
    property string target: ""                   // scope Install writes to ("" = global)
    property MiseHttpDraft draft                 // the http: form's text, owned by the panel
    property real rowH: Theme.fontSizeMedium + Theme.fontSizeSmall + Theme.spacingXL + Theme.spacingXS
    property real controlH: Theme.iconSize + Theme.spacingL
    property real iconBtn: Theme.iconSize + Theme.spacingM
    property real chipH: Theme.iconSizeLarge - Theme.spacingXXS
    signal toggled                               // expand / collapse asked
    signal installed                             // the http: form installed: collapse
    readonly property bool confirm: removeConfirm.armed   // remove is two-step
    readonly property string key: modelData.name + "|" + modelData.scope
    readonly property var info: MiseInfo.info[MiseInfo.infoKey(modelData.name, modelData.scope)] || ({})
    readonly property var unused: MiseService.prunable[MiseService.bareName(modelData.name)] || []
    // `latest` first, then the latest versions, plus installed ones too old to be among them (so they can be removed)
    readonly property var chipVersions: {
        const v = info.versions || [];
        return (v.length ? ["latest"] : []).concat(v, ((info.meta || {}).installed_versions || []).filter(x => !v.includes(x)));
    }
    // config says `latest`: the `latest` chip is the active one, the version it resolved to is just installed
    readonly property bool trackLatest: ((info.meta || {}).requested_versions || []).includes("latest")
    height: open ? row.rowH + (modelData.template ? tplForm.implicitHeight : details.implicitHeight) + Theme.spacingS : row.rowH
    clip: true
    radius: Theme.cornerRadius
    Behavior on height {
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Easing.OutQuad
        }
    }
    color: open ? Theme.surfaceContainerHigh : rowHover.containsMouse ? Theme.primaryHoverLight : "transparent"
    MouseArea {
        id: rowHover
        anchors.fill: head   // the header only: clicks in the expanded area must not collapse it
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            row.toggled();
            if (row.open && !modelData.template)
                MiseInfo.loadInfo(modelData.name, modelData.scope);
        }
    }
    MiseConfirm {
        id: removeConfirm
        onConfirmed: MiseService.uninstall(row.modelData.name, row.modelData.scope)
    }
    Item {
        id: head
        width: parent.width
        height: row.rowH
    }
    DankIcon {
        id: rowIcon
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingM
        anchors.verticalCenter: head.verticalCenter
        name: modelData.template ? "edit_note" : modelData.installed ? "check_circle" : (modelData.direct ? "add_circle" : "download")
        size: Theme.iconSize - 4
        color: modelData.installed ? Theme.surfaceVariantText : Theme.primary
    }
    Column {
        anchors.left: rowIcon.right
        anchors.leftMargin: Theme.spacingM
        anchors.right: chevron.left
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: head.verticalCenter
        spacing: 1
        StyledText {
            width: parent.width
            text: modelData.name
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            maximumLineCount: 1
        }
        StyledText {
            width: parent.width
            // not installed: the details repeat it in full
            visible: text !== "" && !(row.open && !modelData.installed)
            text: modelData.sub
            font.pixelSize: Theme.fontSizeSmall
            font.family: Theme.monoFontFamily
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            maximumLineCount: 1
        }
    }
    // expand indicator: the whole header toggles, the chevron only shows the state
    DankIcon {
        id: chevron
        anchors.right: rowBtn.left
        anchors.verticalCenter: head.verticalCenter
        name: "expand_more"
        size: Theme.iconSize
        color: Theme.surfaceVariantText
        rotation: row.open ? 180 : 0
        Behavior on rotation {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Easing.OutQuad
            }
        }
    }
    DankActionButton {
        id: rowBtn
        visible: !modelData.template
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: head.verticalCenter
        buttonSize: row.iconBtn
        // installed: red bin, first click arms (red check), second removes
        // not installed: download = install
        iconName: modelData.installed ? (row.confirm ? "check" : "delete") : "download"
        iconColor: modelData.installed ? (row.confirm ? Theme.surface : Theme.error) : Theme.primary
        backgroundColor: row.confirm ? Theme.error : "transparent"
        tooltipText: modelData.installed ? (row.confirm ? "Click again to remove" : "Remove" + MiseService.inLabel(modelData.scope)) : (modelData.missing ? "Install the declared version" + MiseService.inLabel(modelData.scope) : "Install latest" + (row.target ? MiseService.inLabel(row.target) : ""))
        enabled: !MiseJobs.busy
        onClicked: {
            if (modelData.missing) {
                MiseService.upgrade(modelData.name, modelData.scope);
            } else if (!modelData.installed) {
                MiseService.install(modelData.name, row.target);
            } else {
                removeConfirm.click();
            }
        }
    }

    // `http:` row, expanded: the options of an http-backend tool
    MiseHttpForm {
        id: tplForm
        opacity: row.open && modelData.template ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.shortDuration
            }
        }
        anchors.top: head.bottom
        anchors.left: rowIcon.right
        anchors.right: parent.right
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingM
        draft: row.draft
        target: row.target
        controlH: row.controlH
        chipH: row.chipH
        onInstalled: row.installed()
    }

    // expanded: description, backend, installed versions, and the latest versions to pin
    MiseToolDetails {
        id: details
        opacity: row.open && !modelData.template ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.shortDuration
            }
        }
        anchors.top: head.bottom
        anchors.left: rowIcon.right
        anchors.right: parent.right
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingM
        tool: MiseService.bareName(modelData.name)
        scope: modelData.scope
        name: modelData.name
        declared: modelData.installed
        fallback: modelData.installed ? "" : modelData.sub
        info: row.info
        chipVersions: row.chipVersions
        unused: row.unused
        trackLatest: row.trackLatest
        chipH: row.chipH
    }
}
