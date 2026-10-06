import QtQuick
import qs.Common
import qs.Widgets

// Updates / Tools UI shared by the bar popout (MiseBar.qml) and the keybind modal (MiseDaemon.qml).
Item {
    id: pop

    readonly property int count: MiseService.outdated.length
    readonly property int bumpCount: MiseService.bumps.length

    // sizes derived from theme tokens, so they follow the user's font / icon scaling
    readonly property real controlH: Theme.iconSize + Theme.spacingL
    readonly property real rowH: Theme.fontSizeMedium + Theme.fontSizeSmall + Theme.spacingXL + Theme.spacingXS
    readonly property real chipH: Theme.iconSizeLarge - Theme.spacingXXS
    readonly property real iconBtn: Theme.iconSize + Theme.spacingM
    readonly property real actionIcon: Theme.iconSize - Theme.spacingXS

    readonly property string summary: MiseService.error || ((count > 0 ? count + " outdated" : "All up to date") + (bumpCount ? " · " + bumpCount + " bumpable" : "") + " · " + MiseService.installed.length + " installed" + checkedText)

    // on open. "updates" / "tools" are fixed; anything else is auto:
    // Updates if something is pending (updates or bumps), Tools otherwise
    function pickInitialTab(mode) {
        tab = mode === "updates" ? 0 : mode === "tools" ? 1 : (count > 0 || bumpCount > 0) ? 0 : 1;
    }

    function focusSearch() {
        field.forceActiveFocus();
    }

    property int tab: 0            // 0 = updates, 1 = tools (installed + install)
    property string updFilter: ""
    property string query: ""
    property string backend: ""     // backend chip filter ("" = all)
    readonly property string checkedText: {
        if (!MiseService.lastCheck)
            return "";
        const m = Math.round((Date.now() - MiseService.lastCheck) / 60000);
        return " · checked " + (m < 1 ? "just now" : m + "m ago");
    }
    readonly property bool searching: tab === 1 && query.trim() !== ""
    // remote lookup only while the Tools tab is being searched
    onQueryChanged: MiseService.lookup(tab === 1 ? query : "")
    onTabChanged: MiseService.lookup(tab === 1 ? query : "")
    // in-range updates first, then bump-only (pinned / newer major) rows
    readonly property var updRows: MiseService.outdated.map(t => ({
                name: t.name,
                requested: t.requested,
                current: t.current,
                latest: t.latest,
                bump: false
            })).concat(MiseService.bumps.map(t => ({
                    name: t.name,
                    requested: t.requested,
                    current: t.current,
                    latest: t.bump,
                    bump: true
                })))
    // ignored entries as rows: "name" or "name@version"
    readonly property var ignoredRows: MiseService.ignored.map(k => {
        const m = k.match(/^(.*)@([^\/@:]+)$/);
        return {
            name: m ? m[1] : k,
            requested: "",
            current: "",
            latest: m ? m[2] : "",
            bump: false,
            ignoredKey: k
        };
    })
    readonly property bool ignoredView: tab === 0 && backend === "__ignored"
    readonly property var baseNames: tab === 0 ? updRows.map(t => t.name) : MiseService.installed
    readonly property var backends: {
        const c = {};
        baseNames.forEach(n => {
            const b = MiseService.backendOf(n);
            c[b] = (c[b] || 0) + 1;
        });
        return Object.keys(c).sort().map(k => ({
                    key: k,
                    label: k + " " + c[k]
                }));
    }
    readonly property var updList: (ignoredView ? ignoredRows : updRows).filter(t => t.name.toLowerCase().includes(updFilter.trim().toLowerCase()) && (!backend || ignoredView || MiseService.backendOf(t.name) === backend))
    // tools tab: no query -> what you have installed; query -> installed matches, then registry hits
    readonly property var toolList: {
        const q = query.trim().toLowerCase();
        const inst = n => ({
                name: n,
                installed: true,
                direct: false,
                sub: MiseService.versions[n] || ""
            });
        if (!q)
            return MiseService.installed.filter(n => !backend || MiseService.backendOf(n) === backend).slice().sort().map(inst);
        return MiseService.installed.filter(n => n.toLowerCase().includes(q)).slice().sort().map(inst).concat(MiseService.search(query).filter(r => !r.installed).map(r => ({
                        name: r.name,
                        installed: false,
                        direct: r.direct,
                        sub: r.backend
                    })));
    }
    readonly property int shown: tab === 0 ? updList.length : toolList.length


    // ---- toolbar: tabs + refresh ----
    Item {
        id: toolbar
        width: parent.width
        height: pop.controlH

        DankButtonGroup {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            buttonHeight: pop.iconBtn
            model: ["Updates" + (pop.count > 0 ? " (" + pop.count + ")" : ""), "Tools"]
            currentIndex: pop.tab
            onSelectionChanged: (index, selected) => {
                if (selected)
                    pop.tab = index;
            }
        }

        DankActionButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconName: "refresh"
            tooltipText: "Check for updates"
            enabled: !MiseService.checking && !MiseService.busy
            onClicked: MiseService.refresh()
        }
    }

    // ---- job banner: what mise is doing right now ----
    Rectangle {
        id: banner
        anchors.top: toolbar.bottom
        anchors.topMargin: Theme.spacingS
        width: parent.width
        visible: MiseService.busy
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
                    text: MiseService.jobLabel + "…"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            StyledText {
                width: parent.width
                text: MiseService.jobLog.length ? MiseService.jobLog[MiseService.jobLog.length - 1] : ""
                font.pixelSize: Theme.fontSizeSmall
                font.family: Theme.monoFontFamily
                color: Theme.surfaceVariantText
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                maximumLineCount: 1
            }
        }
    }

    // ---- search / filter field ----
    DankTextField {
        id: field
        anchors.top: banner.bottom
        anchors.topMargin: Theme.spacingS
        width: parent.width
        height: pop.controlH
        leftIconName: "search"
        showClearButton: true
        placeholderText: pop.tab === 0 ? "Filter updates…" : "Search installed & registry, or type backend:tool…"
        onTextEdited: {
            if (pop.tab === 0)
                pop.updFilter = text;
            else
                pop.query = text;
        }
        // Enter installs the top not-yet-installed hit
        onAccepted: {
            if (pop.tab !== 1 || MiseService.busy)
                return;
            const r = pop.toolList.find(x => !x.installed);
            if (r)
                MiseService.install(r.name);
        }
    }

    // thin sliding bar under the field while npm / crates.io / GitHub are being asked
    Rectangle {
        id: loadBar
        anchors.left: field.left
        anchors.right: field.right
        anchors.top: field.bottom
        anchors.topMargin: 1
        height: 2
        color: "transparent"
        clip: true
        visible: pop.tab === 1 && MiseService.lookingUp

        Rectangle {
            id: seg
            width: parent.width / 3
            height: parent.height
            radius: 1
            color: Theme.primary
            SequentialAnimation on x {
                running: loadBar.visible
                loops: Animation.Infinite
                NumberAnimation {
                    from: -seg.width
                    to: loadBar.width
                    duration: 900
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }

    DankButton {
        id: updAll
        visible: pop.tab === 0
        anchors.bottom: parent.bottom
        width: bumpAll.visible ? (parent.width - Theme.spacingS) / 2 : parent.width
        text: pop.count > 0 ? "Update all (" + pop.count + ")" : "Update all"
        iconName: "upgrade"
        buttonHeight: pop.controlH + Theme.spacingXS
        enabled: pop.count > 0 && !MiseService.busy
        onClicked: MiseService.upgrade("")
    }

    // rewrites pins in your config: arm first, click again to confirm
    DankButton {
        id: bumpAll
        property bool armed: false
        visible: pop.tab === 0 && MiseService.bumps.length > 0
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: (parent.width - Theme.spacingS) / 2
        text: armed ? "Confirm bump (" + MiseService.bumps.length + ")" : "Bump all (" + MiseService.bumps.length + ")"
        iconName: armed ? "check" : "upgrade"
        buttonHeight: pop.controlH + Theme.spacingXS
        backgroundColor: armed ? Theme.error : Theme.warning
        textColor: Theme.surface
        enabled: !MiseService.busy
        onClicked: {
            if (!armed) {
                armed = true;
                bumpReset.restart();
            } else {
                armed = false;
                MiseService.bumpAll();
            }
        }
        Timer {
            id: bumpReset
            interval: 3000
            onTriggered: bumpAll.armed = false
        }
    }

    Connections {
        target: MiseService
        function onIgnoredChanged() {
            if (MiseService.ignored.length === 0 && pop.backend === "__ignored")
                pop.backend = "";
        }
    }

    // switching tabs: show that tab's own text
    Connections {
        target: pop
        function onTabChanged() {
            pop.backend = "";
            field.text = pop.tab === 0 ? pop.updFilter : pop.query;
        }
    }

    // ---- backend filter chips (updates, or tools when not searching) ----
    Flickable {
        id: chips
        anchors.top: field.bottom
        anchors.topMargin: visible ? Theme.spacingS : 0
        width: parent.width
        visible: !pop.searching && (pop.backends.length > 1 || (pop.tab === 0 && MiseService.ignored.length > 0))
        height: visible ? pop.chipH : 0
        contentWidth: chipRow.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: chipRow
            spacing: Theme.spacingXS
            Repeater {
                model: [{
                        key: "",
                        label: "All"
                    }].concat(pop.backends, pop.tab === 0 && MiseService.ignored.length > 0 ? [{
                        key: "__ignored",
                        label: "ignored " + MiseService.ignored.length
                    }] : [])
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool active: pop.backend === modelData.key
                    height: pop.chipH
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
                        onClicked: pop.backend = modelData.key
                    }
                }
            }
        }
    }

    // ---- lists ----
    Rectangle {
        anchors.top: chips.bottom
        anchors.topMargin: Theme.spacingS
        anchors.bottom: updAll.visible ? updAll.top : parent.bottom
        anchors.bottomMargin: updAll.visible ? Theme.spacingS : 0
        width: parent.width
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceVariant, 0.1)

        StyledText {
            anchors.centerIn: parent
            width: parent.width - Theme.spacingL * 2
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: MiseService.error && pop.tab === 0 ? Theme.error : Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
            visible: pop.shown === 0
            text: {
                if (pop.tab === 0) {
                    if (MiseService.error)
                        return MiseService.error;
                    if (MiseService.checking)
                        return "Checking for updates…";
                    return pop.count > 0 ? "No updates match" : "Everything is up to date";
                }
                if (!pop.searching)
                    return "Nothing installed yet.\nType a name, or any backend:tool\ne.g. pipx:package, npm:package, cargo:crate, github:owner/repo\nOptions: pipx:package[uvx_args=--python 3.14]";
                if (MiseService.lookingUp)
                    return "Searching npm, crates.io…";
                return MiseService.registry.length ? "No matches. Use backend:tool to install anything else." : "Loading registry…";
            }
        }

        // updates
        DankListView {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            visible: pop.tab === 0 && pop.updList.length > 0
            clip: true
            spacing: Theme.spacingXS
            model: pop.updList

            delegate: Rectangle {
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                height: pop.rowH
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
                    name: modelData.ignoredKey ? "visibility_off" : (modelData.bump ? "upgrade" : "arrow_circle_up")
                    size: Theme.iconSize - 4
                    color: modelData.ignoredKey ? Theme.surfaceVariantText : (modelData.bump ? Theme.warning : Theme.primary)
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
                        text: modelData.name
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: modelData.ignoredKey ? Theme.surfaceVariantText : Theme.surfaceText
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        maximumLineCount: 1
                    }
                    StyledText {
                        width: parent.width
                        text: modelData.ignoredKey ? (modelData.latest ? "skipping " + modelData.latest : "ignored · all versions") : modelData.current + " → " + modelData.latest + (modelData.bump ? " · bump (requested " + modelData.requested + ")" : "")
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
                        visible: !!modelData.ignoredKey
                        buttonSize: pop.iconBtn
                        iconSize: pop.actionIcon
                        iconName: "undo"
                        iconColor: Theme.primary
                        tooltipText: "Stop ignoring"
                        onClicked: MiseService.unignore(modelData.ignoredKey)
                    }
                    DankActionButton {
                        visible: !modelData.ignoredKey
                        buttonSize: pop.iconBtn
                        iconSize: pop.actionIcon
                        iconName: "skip_next"
                        iconColor: Theme.surfaceVariantText
                        tooltipText: "Skip " + modelData.latest + " (shows again with a newer version)"
                        onClicked: MiseService.ignore(modelData.name, modelData.latest)
                    }
                    DankActionButton {
                        visible: !modelData.ignoredKey
                        buttonSize: pop.iconBtn
                        iconSize: pop.actionIcon
                        iconName: "visibility_off"
                        iconColor: Theme.surfaceVariantText
                        tooltipText: "Ignore " + modelData.name + " (all versions)"
                        onClicked: MiseService.ignore(modelData.name, "")
                    }
                    DankActionButton {
                        visible: !modelData.ignoredKey
                        buttonSize: pop.iconBtn
                        iconSize: pop.actionIcon
                        iconName: modelData.bump ? "upgrade" : "download"
                        iconColor: modelData.bump ? Theme.warning : Theme.primary
                        tooltipText: modelData.bump ? "Bump: rewrites \"" + modelData.requested + "\" in your mise config" : "Update"
                        enabled: !MiseService.busy
                        onClicked: modelData.bump ? MiseService.bump(modelData.name) : MiseService.upgrade(modelData.name)
                    }
                }
            }
        }

        // tools: installed (version + remove) and installable (download)
        DankListView {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            visible: pop.tab === 1 && pop.toolList.length > 0
            clip: true
            spacing: Theme.spacingXS
            model: pop.toolList

            delegate: Rectangle {
                id: row
                required property var modelData
                property bool confirm: false   // remove is two-step
                width: ListView.view ? ListView.view.width : 0
                height: pop.rowH
                radius: Theme.cornerRadius
                color: rowHover.containsMouse ? Theme.primaryHoverLight : "transparent"
                MouseArea {
                    id: rowHover
                    anchors.fill: parent
                    hoverEnabled: true
                }
                Timer {
                    id: confirmReset
                    interval: 3000
                    onTriggered: row.confirm = false
                }
                DankIcon {
                    id: rowIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    name: modelData.installed ? "check_circle" : (modelData.direct ? "add_circle" : "download")
                    size: Theme.iconSize - 4
                    color: modelData.installed ? Theme.surfaceVariantText : Theme.primary
                }
                Column {
                    anchors.left: rowIcon.right
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: rowBtn.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
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
                        visible: text !== ""
                        text: modelData.sub
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.monoFontFamily
                        color: Theme.surfaceVariantText
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        maximumLineCount: 1
                    }
                }
                DankActionButton {
                    id: rowBtn
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: pop.iconBtn
                    // installed: red bin, first click arms (red check), second removes
                    // not installed: download = install
                    iconName: modelData.installed ? (row.confirm ? "check" : "delete") : "download"
                    iconColor: modelData.installed ? (row.confirm ? Theme.surface : Theme.error) : Theme.primary
                    backgroundColor: row.confirm ? Theme.error : "transparent"
                    tooltipText: modelData.installed ? (row.confirm ? "Click again to remove" : "Remove") : "Install"
                    enabled: !MiseService.busy
                    onClicked: {
                        if (!modelData.installed) {
                            MiseService.install(modelData.name);
                        } else if (!row.confirm) {
                            row.confirm = true;
                            confirmReset.restart();
                        } else {
                            MiseService.uninstall(modelData.name);
                        }
                    }
                }
            }
        }
    }
}
