import QtQuick
import qs.Common
import qs.Widgets
import qs.Services
import qs.Modals.FileBrowser

// Updates / Tools UI shared by the bar popout (MiseBar.qml) and the keybind modal (MiseDaemon.qml).
Item {
    id: pop

    // header, tab and first-tab choice follow the picked scope (the bar badge has its own setting)
    readonly property int count: scopedCount
    readonly property int bumpCount: scopedBumps

    // sizes derived from theme tokens, so they follow the user's font / icon scaling
    readonly property real controlH: Theme.iconSize + Theme.spacingL
    readonly property real rowH: Theme.fontSizeMedium + Theme.fontSizeSmall + Theme.spacingXL + Theme.spacingXS
    readonly property real chipH: Theme.iconSizeLarge - Theme.spacingXXS
    readonly property real iconBtn: Theme.iconSize + Theme.spacingM
    readonly property real actionIcon: Theme.iconSize - Theme.spacingXS

    // `mise outdated` often ends in a few ms: hold the "checking" look long enough to be seen
    readonly property int minCheckMs: Math.min(Theme.popoutAnimationDuration * 4, 800)
    property bool checkingShown: MiseService.checking
    property double checkStart: 0
    Connections {
        target: MiseService
        function onCheckingChanged() {
            if (MiseService.checking) {
                checkHold.stop();
                pop.checkStart = Date.now();
                pop.checkingShown = true;
                return;
            }
            const left = pop.minCheckMs - (Date.now() - pop.checkStart);
            if (left <= 0) {
                pop.checkingShown = false;
            } else {
                checkHold.interval = left;
                checkHold.restart();
            }
        }
    }
    Timer {
        id: checkHold
        onTriggered: pop.checkingShown = false
    }

    readonly property string summary: MiseService.error || ((count > 0 ? count + " outdated" : (MiseService.scopes.length ? scopeName + " is up to date" : "All up to date")) + (bumpCount ? " · " + bumpCount + " bumpable" : "") + " · " + installedRows.length + " installed" + checkedText)

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
    property string openRow: ""    // tools tab: the one expanded row (name|scope)
    // scope picker (Settings > Project tools): "" = global (default), "*" = everything, else a project's config path
    property string scope: ""
    property bool menuOpen: false   // scope menu (toolbar button)
    property bool adding: false     // "type a path" field shown inside that menu
    property bool addPending: false // an add (typed or picked) is in flight: select the project when it lands
    function closeMenu() {
        menuOpen = false;
        adding = false;
        addErr.text = "";
    }
    // where Install writes: the picked scope, global when looking at everything
    readonly property string target: scope === "*" ? "" : scope
    readonly property bool showScope: scope === "*" && MiseService.scopes.length > 0
    readonly property var scopeOptions: [
        {
            key: "",
            label: "Global"
        },
        {
            key: "*",
            label: "All"
        }
    ].concat(MiseService.scopes.map(s => ({
                key: s,
                label: MiseService.scopeLabel(s)
            })))
    readonly property string scopeName: scope === "*" ? "All" : scope === "" ? "Global" : MiseService.scopeLabel(scope)
    function inScope(r) {
        return scope === "*" || r.scope === scope;
    }
    // pending updates / bumps of one scope ("*" = all of them), for the menu and the hints below
    function pendingIn(key) {
        return updRows.filter(r => key === "*" || r.scope === key).length;
    }
    // pending in scopes other than the one being looked at
    readonly property int elsewhere: scope === "*" ? 0 : updRows.length - pendingIn(scope)
    readonly property int elsewhereBumps: scope === "*" ? 0 : updRows.filter(r => r.bump && !inScope(r)).length
    // "1 update", "2 bumps" or "1 update · 1 bump": a bump is not an update (it rewrites the config)
    readonly property string elsewhereText: [elsewhere - elsewhereBumps > 0 ? (elsewhere - elsewhereBumps) + (elsewhere - elsewhereBumps === 1 ? " update" : " updates") : "", elsewhereBumps > 0 ? elsewhereBumps + (elsewhereBumps === 1 ? " bump" : " bumps") : ""].filter(x => x).join(" · ") + (scope === "" ? " in projects" : " in other scopes")
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
                scope: t.scope,
                bump: false
            })).concat(MiseService.bumps.map(t => ({
                name: t.name,
                requested: t.requested,
                current: t.current,
                latest: t.bump,
                scope: t.scope,
                bump: true
            })))
    // what the Update all / Bump all buttons act on: the picked scope
    readonly property int scopedCount: updRows.filter(r => !r.bump && inScope(r)).length
    readonly property int scopedBumps: updRows.filter(r => r.bump && inScope(r)).length
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
    // tools tab: every tool of the picked scope(s), one row per tool and scope
    readonly property var installedRows: {
        const out = [];
        (scope === "*" ? [""].concat(MiseService.scopes) : [scope]).forEach(s => {
            const v = MiseService.toolsIn(s);
            MiseService.installedIn(s).forEach(n => out.push({
                    name: n,
                    scope: s,
                    installed: true,
                    direct: false,
                    sub: (v[n] || "") + (showScope ? (v[n] ? " · " : "") + MiseService.scopeLabel(s) : "")
                }));
        });
        return out.sort((a, b) => a.name.localeCompare(b.name) || a.scope.localeCompare(b.scope));
    }
    readonly property var baseNames: tab === 0 ? updRows.filter(inScope).map(t => t.name) : installedRows.map(t => t.name)
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
    readonly property var updList: (ignoredView ? ignoredRows : updRows).filter(t => t.name.toLowerCase().includes(updFilter.trim().toLowerCase()) && (!backend || ignoredView || MiseService.backendOf(t.name) === backend) && (ignoredView || inScope(t)))
    // tools tab: no query -> what you have installed; query -> installed matches, then registry hits
    readonly property var toolList: {
        const q = MiseService.alias(query).trim().toLowerCase();
        if (!q)
            return installedRows.filter(r => !backend || MiseService.backendOf(r.name) === backend);
        // `npm:google` matches `npm:@ai-sdk/google` too: the same backend:term split the search uses
        const c = q.indexOf(":");
        const term = c > 0 ? q.substring(c + 1) : q;
        const hit = r => r.name.toLowerCase().includes(q) || (c > 0 && MiseService.backendOf(r.name) === q.substring(0, c) && r.name.toLowerCase().includes(term));
        return installedRows.filter(hit).concat(MiseService.search(query, target).filter(r => !r.installed).map(r => ({
                        name: r.name,
                        scope: target,
                        installed: false,
                        direct: r.direct,
                        sub: r.backend + (scope === "*" && MiseService.scopes.length ? " · installs globally" : "")
                    })));
    }
    readonly property int shown: tab === 0 ? updList.length : toolList.length

    // ---- toolbar: tabs + refresh ----
    Item {
        id: toolbar
        width: parent.width
        height: pop.controlH

        DankButtonGroup {
            id: toolbarTabs
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

        // scope picker: one compact button instead of a chip row, so it scales to any number of projects
        Rectangle {
            id: scopeBtn
            visible: MiseService.projectsMode !== "off"
            anchors.right: refreshBtn.left
            anchors.rightMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            height: pop.iconBtn
            // the label is what shrinks (elided) when the project name is long
            readonly property real maxLabelW: pop.width - toolbarTabs.width - refreshBtn.width - Theme.spacingM * 4 - (Theme.iconSize - 6) * 2 - Theme.spacingXS * 2
            width: scopeBtnRow.implicitWidth + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: pop.menuOpen || scopeHover.containsMouse ? Theme.primaryHoverLight : Theme.surfaceContainerHigh
            border.width: pop.scope !== "*" ? 1 : 0
            border.color: Theme.primary
            // something is pending in a scope you are not looking at
            Rectangle {
                visible: pop.elsewhere > 0
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: -Theme.spacingXXS
                anchors.rightMargin: -Theme.spacingXXS
                width: Theme.spacingS + Theme.spacingXXS
                height: width
                radius: width / 2
                color: Theme.primary
                border.width: 1
                border.color: Theme.surface
            }
            MouseArea {
                id: scopeHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: pop.menuOpen ? pop.closeMenu() : (pop.menuOpen = true)
            }
            Row {
                id: scopeBtnRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS
                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: pop.scope === "*" ? "layers" : (pop.scope === "" ? "public" : "folder")
                    size: Theme.iconSize - 6
                    color: pop.scope === "*" ? Theme.surfaceVariantText : Theme.primary
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, scopeBtn.maxLabelW)
                    text: pop.scopeName
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                }
                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: pop.menuOpen ? "arrow_drop_up" : "arrow_drop_down"
                    size: Theme.iconSize - 6
                    color: Theme.surfaceVariantText
                }
            }
        }

        // refresh: hover spins the icon, press shrinks, checking morphs to a circle with a spinner
        DankActionButton {
            id: refreshBtn
            readonly property bool active: pop.checkingShown
            property bool hovered: false
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: pop.iconBtn
            iconName: ""   // the icon is drawn below so it can rotate
            tooltipText: "Check for updates"
            enabled: !pop.checkingShown && !MiseService.busy
            opacity: enabled || active ? 1.0 : 0.5
            radius: active ? height / 2 : Theme.cornerRadius
            border.width: 1
            border.color: Theme.withAlpha(Theme.primary, hovered ? 0.3 : 0.15)
            scale: pressed ? 0.92 : (hovered && enabled ? 1.05 : 1.0)
            onEntered: hovered = true
            onExited: hovered = false
            onClicked: MiseService.refresh()

            Behavior on scale {
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Easing.OutQuad
                }
            }
            // radius already animates via StyledRect's own Behavior
            Behavior on border.color {
                ColorAnimation {
                    duration: Theme.popoutAnimationDuration
                }
            }

            DankIcon {
                anchors.centerIn: parent
                name: "refresh"
                size: refreshBtn.iconSize
                color: Theme.primary
                smoothTransform: true
                visible: !refreshBtn.active
                rotation: refreshBtn.hovered && refreshBtn.enabled ? 180 : 0

                Behavior on rotation {
                    NumberAnimation {
                        duration: Theme.popoutAnimationDuration
                        easing.type: Easing.OutBack
                    }
                }
            }

            DankSpinner {
                anchors.centerIn: parent
                size: Theme.iconSize - 6
                color: Theme.primary
                visible: refreshBtn.active
            }
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

    Connections {
        target: MiseService
        function onScopesChanged() {
            if (pop.scope !== "*" && pop.scope !== "" && !MiseService.scopes.includes(pop.scope))
                pop.scope = "";
        }
        function onProjectsModeChanged() {
            if (MiseService.projectsMode === "off") {
                pop.scope = "";
                pop.closeMenu();
            }
        }
        function onProjectAdded(path) {
            if (!pop.addPending)
                return;
            pop.addPending = false;
            pop.scope = path;
            addField.text = "";
            pop.closeMenu();
        }
        function onProjectAddFailed(message) {
            if (!pop.addPending)
                return;
            pop.addPending = false;
            // typed: the error shows under the field. Picked: the menu is already closed, so a toast
            if (pop.adding)
                addErr.text = message;
            else
                ToastService.showError("mise", message);
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
                MiseService.install(r.name, pop.target);
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
        text: pop.scopedCount > 0 ? "Update all (" + pop.scopedCount + ")" : "Update all"
        iconName: "upgrade"
        buttonHeight: pop.controlH + Theme.spacingXS
        enabled: pop.scopedCount > 0 && !MiseService.busy
        onClicked: MiseService.upgrade("", pop.scope)
    }

    // rewrites pins in your config: arm first, click again to confirm
    DankButton {
        id: bumpAll
        property bool armed: false
        visible: pop.tab === 0 && pop.scopedBumps > 0
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: (parent.width - Theme.spacingS) / 2
        text: armed ? "Confirm bump (" + pop.scopedBumps + ")" : "Bump all (" + pop.scopedBumps + ")"
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
                MiseService.bumpAll(pop.scope);
            }
        }
        Timer {
            id: bumpReset
            interval: 3000
            onTriggered: bumpAll.armed = false
        }
    }

    // versions no config uses: arm first, click again to confirm
    DankButton {
        id: pruneAll
        property bool armed: false
        visible: pop.tab === 1 && MiseService.prunableCount > 0
        anchors.bottom: parent.bottom
        width: parent.width
        text: armed ? "Confirm prune (" + MiseService.prunableCount + ")" : "Prune unused versions (" + MiseService.prunableCount + ")"
        iconName: armed ? "check" : "delete_sweep"
        buttonHeight: pop.controlH + Theme.spacingXS
        backgroundColor: armed ? Theme.error : Theme.surfaceContainerHigh
        textColor: armed ? Theme.surface : Theme.surfaceText
        enabled: !MiseService.busy
        onClicked: {
            if (!armed) {
                armed = true;
                pruneAllReset.restart();
            } else {
                armed = false;
                MiseService.prune("");
            }
        }
        Timer {
            id: pruneAllReset
            interval: 3000
            onTriggered: pruneAll.armed = false
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
                model: [
                    {
                        key: "",
                        label: "All"
                    }
                ].concat(pop.backends, pop.tab === 0 && MiseService.ignored.length > 0 ? [
                    {
                        key: "__ignored",
                        label: "ignored " + MiseService.ignored.length
                    }
                ] : [])
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
        anchors.bottom: updAll.visible ? updAll.top : pruneAll.visible ? pruneAll.top : parent.bottom
        anchors.bottomMargin: updAll.visible || pruneAll.visible ? Theme.spacingS : 0
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
                    if (pop.checkingShown)
                        return "Checking for updates…";
                    if (pop.updFilter.trim() !== "" || pop.backend !== "")
                        return "No updates match";
                    // up to date here, but other scopes have something pending: say so
                    if (pop.elsewhere > 0)
                        return pop.scopeName + " is up to date · " + pop.elsewhereText;
                    return "Everything is up to date";
                }
                if (!pop.searching)
                    return "Nothing installed yet.\nType a name, or any backend:tool\ne.g. pipx:package, npm:package, cargo:crate, github:owner/repo\nOptions: pipx:package[uvx_args=--python 3.14]";
                if (MiseService.lookingUp)
                    return "Searching…";
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
                        text: modelData.ignoredKey ? (modelData.latest ? "skipping " + modelData.latest : "ignored · all versions") : modelData.current + " → " + modelData.latest + (modelData.bump ? " · bump (requested " + modelData.requested + ")" : "") + (pop.showScope ? " · " + MiseService.scopeLabel(modelData.scope) : "")
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
                        tooltipText: modelData.bump ? "Bump: rewrites \"" + modelData.requested + "\" in your " + (modelData.scope ? "project's" : "global") + " mise config" : "Update"
                        enabled: !MiseService.busy
                        onClicked: modelData.bump ? MiseService.bump(modelData.name, modelData.scope) : MiseService.upgrade(modelData.name, modelData.scope)
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
                readonly property string key: modelData.name + "|" + modelData.scope
                readonly property bool open: pop.openRow === key
                readonly property var info: MiseService.info[MiseService.bareName(modelData.name)] || ({})
                readonly property var unused: MiseService.prunable[MiseService.bareName(modelData.name)] || []
                // the latest versions, plus installed ones too old to be among them (so they can be removed)
                readonly property var chipVersions: {
                    const v = info.versions || [];
                    return v.concat(((info.meta || {}).installed_versions || []).filter(x => !v.includes(x)));
                }
                property bool pruneArmed: false   // prune is two-step, like remove
                width: ListView.view ? ListView.view.width : 0
                height: open ? pop.rowH + details.implicitHeight + Theme.spacingS : pop.rowH
                clip: true
                radius: Theme.cornerRadius
                color: open ? Theme.surfaceContainerHigh : rowHover.containsMouse ? Theme.primaryHoverLight : "transparent"
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
                Item {
                    id: head
                    width: parent.width
                    height: pop.rowH
                }
                DankIcon {
                    id: rowIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: head.verticalCenter
                    name: modelData.installed ? "check_circle" : (modelData.direct ? "add_circle" : "download")
                    size: Theme.iconSize - 4
                    color: modelData.installed ? Theme.surfaceVariantText : Theme.primary
                }
                Column {
                    anchors.left: rowIcon.right
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: infoBtn.left
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
                DankActionButton {
                    id: infoBtn
                    anchors.right: rowBtn.left
                    anchors.verticalCenter: head.verticalCenter
                    buttonSize: pop.iconBtn
                    iconName: row.open ? "expand_less" : "info"
                    iconColor: Theme.surfaceVariantText
                    tooltipText: "Details & versions"
                    onClicked: {
                        pop.openRow = row.open ? "" : row.key;
                        if (row.open)
                            MiseService.loadInfo(modelData.name);
                    }
                }
                DankActionButton {
                    id: rowBtn
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: head.verticalCenter
                    buttonSize: pop.iconBtn
                    // installed: red bin, first click arms (red check), second removes
                    // not installed: download = install
                    iconName: modelData.installed ? (row.confirm ? "check" : "delete") : "download"
                    iconColor: modelData.installed ? (row.confirm ? Theme.surface : Theme.error) : Theme.primary
                    backgroundColor: row.confirm ? Theme.error : "transparent"
                    tooltipText: modelData.installed ? (row.confirm ? "Click again to remove" : "Remove" + MiseService.inLabel(modelData.scope)) : "Install" + (pop.target ? MiseService.inLabel(pop.target) : "")
                    enabled: !MiseService.busy
                    onClicked: {
                        if (!modelData.installed) {
                            MiseService.install(modelData.name, pop.target);
                        } else if (!row.confirm) {
                            row.confirm = true;
                            confirmReset.restart();
                        } else {
                            MiseService.uninstall(modelData.name, modelData.scope);
                        }
                    }
                }

                // expanded: description, backend, installed versions, and the latest versions to pin
                Column {
                    id: details
                    visible: row.open
                    anchors.top: head.bottom
                    anchors.left: rowIcon.right
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    spacing: Theme.spacingXS

                    StyledText {
                        width: parent.width
                        visible: text !== ""
                        text: row.info.meta && row.info.meta.description ? row.info.meta.description : (modelData.installed ? "" : modelData.sub)
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                    }
                    StyledText {
                        width: parent.width
                        text: row.info.meta ? "Backend: " + row.info.meta.backend + "\nInstalled: " + ((row.info.meta.installed_versions || []).join(", ") || "none") : (row.info.metaError || "Loading…")
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.monoFontFamily
                        color: Theme.surfaceVariantText
                    }
                    StyledText {
                        width: parent.width
                        visible: !row.info.versions
                        text: row.info.versionsError || "Loading versions…"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                    Flow {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: row.chipVersions.length > 0 || row.unused.length > 0

                        // versions no tracked config uses: same shape as a version chip, with a broom
                        Rectangle {
                            visible: row.unused.length > 0
                            width: Math.min(details.width, pruneRow.implicitWidth + Theme.spacingM * 2)
                            height: pop.chipH
                            radius: Theme.cornerRadius
                            color: row.pruneArmed ? Theme.error : (pruneArea.containsMouse && !MiseService.busy ? Theme.withAlpha(Theme.error, 0.15) : "transparent")
                            border.width: 1
                            border.color: row.pruneArmed ? Theme.error : Theme.withAlpha(Theme.outline, 0.4)
                            opacity: MiseService.busy ? 0.5 : 1
                            Row {
                                id: pruneRow
                                anchors.centerIn: parent
                                spacing: Theme.spacingXXS
                                DankIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: row.pruneArmed ? "check" : "delete_sweep"
                                    size: Theme.fontSizeMedium
                                    color: row.pruneArmed ? Theme.surface : Theme.error
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.pruneArmed ? "Remove " + row.unused.join(", ") + "?" : "Prune " + row.unused.length + " unused"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: row.pruneArmed ? Theme.surface : Theme.surfaceText
                                }
                            }
                            Timer {
                                id: pruneReset
                                interval: 3000
                                onTriggered: row.pruneArmed = false
                            }
                            MouseArea {
                                id: pruneArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !MiseService.busy
                                onClicked: {
                                    if (!row.pruneArmed) {
                                        row.pruneArmed = true;
                                        pruneReset.restart();
                                    } else {
                                        row.pruneArmed = false;
                                        MiseService.prune(MiseService.bareName(row.modelData.name));
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: row.chipVersions
                            delegate: Rectangle {
                                id: chip
                                required property string modelData
                                property bool armed: false   // removing a version is two-step
                                readonly property bool have: ((row.info.meta || {}).installed_versions || []).includes(modelData)
                                readonly property bool active: ((row.info.meta || {}).active_versions || []).includes(modelData)
                                width: Theme.spacingM + verRow.implicitWidth + (trashBtn.visible ? Theme.spacingS + trashBtn.width + trashBtn.anchors.rightMargin : Theme.spacingM)
                                height: pop.chipH
                                radius: Theme.cornerRadius
                                color: chipArea.containsMouse && !MiseService.busy ? Theme.primaryHoverLight : chip.active ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
                                border.width: chip.active ? 2 : 1
                                border.color: chip.active ? Theme.primary : Theme.withAlpha(Theme.outline, 0.4)
                                opacity: MiseService.busy ? 0.5 : 1
                                Timer {
                                    id: chipReset
                                    interval: 3000
                                    onTriggered: chip.armed = false
                                }
                                MouseArea {
                                    id: chipArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !MiseService.busy
                                    onClicked: MiseService.install(MiseService.bareName(row.modelData.name) + "@" + chip.modelData, row.modelData.scope)
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
                                        text: chip.modelData
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.family: Theme.monoFontFamily
                                        color: chip.have ? Theme.surfaceVariantText : Theme.primary
                                    }
                                }
                                // installed, not the active one (that one goes with the tool's own bin)
                                Rectangle {
                                    id: trashBtn
                                    visible: chip.have && !chip.active
                                    anchors.right: parent.right
                                    anchors.rightMargin: (parent.height - height) / 2   // same gap on every side
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: pop.chipH - Theme.spacingS
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
                                        enabled: !MiseService.busy
                                        onClicked: {
                                            if (!chip.armed) {
                                                chip.armed = true;
                                                chipReset.restart();
                                            } else {
                                                chip.armed = false;
                                                MiseService.uninstallVersion(MiseService.bareName(row.modelData.name), chip.modelData);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- scope menu: opens under the toolbar button. The scrim swallows clicks outside, so nothing else
    // in the panel is reachable (or half-typed) while it is open ----
    MouseArea {
        anchors.fill: parent
        z: 10
        visible: pop.menuOpen
        onClicked: pop.closeMenu()
    }

    Rectangle {
        id: scopeMenu
        z: 11
        visible: pop.menuOpen
        anchors.top: toolbar.bottom
        anchors.topMargin: Theme.spacingXS
        anchors.right: parent.right
        width: Math.min(parent.width, pop.controlH * 7)
        height: menuCol.implicitHeight + Theme.spacingXS * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.3)

        Column {
            id: menuCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingXS
            spacing: Theme.spacingXXS

            // at most ~6 rows tall, scrolls beyond that
            Flickable {
                width: parent.width
                height: Math.min(optCol.implicitHeight, pop.controlH * 6)
                contentHeight: optCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: optCol
                    width: parent.width
                    Repeater {
                        model: pop.scopeOptions
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active: pop.scope === modelData.key
                            readonly property bool isProject: modelData.key !== "*" && modelData.key !== ""
                            width: optCol.width
                            height: pop.controlH
                            radius: Theme.cornerRadius
                            color: optHover.containsMouse ? Theme.primaryHoverLight : "transparent"
                            MouseArea {
                                id: optHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    pop.scope = modelData.key;
                                    pop.closeMenu();
                                }
                            }
                            DankIcon {
                                id: optIcon
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                name: parent.active ? "check" : (modelData.key === "*" ? "layers" : (modelData.key === "" ? "public" : "folder"))
                                size: Theme.iconSize - 6
                                color: parent.active ? Theme.primary : Theme.surfaceVariantText
                            }
                            StyledText {
                                anchors.left: optIcon.right
                                anchors.leftMargin: Theme.spacingS
                                anchors.right: optCount.visible ? optCount.left : (optRemove.visible ? optRemove.left : parent.right)
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: parent.active ? Font.Medium : Font.Normal
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                maximumLineCount: 1
                            }
                            // how many updates are waiting in this scope
                            StyledText {
                                id: optCount
                                visible: pop.pendingIn(modelData.key) > 0
                                anchors.right: optRemove.visible ? optRemove.left : parent.right
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                text: pop.pendingIn(modelData.key)
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.monoFontFamily
                                color: Theme.primary
                            }
                            // stop following: only edits the plugin's list, the config file is never touched
                            DankActionButton {
                                id: optRemove
                                visible: parent.isProject
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingXXS
                                anchors.verticalCenter: parent.verticalCenter
                                buttonSize: pop.iconBtn - Theme.spacingXS
                                iconSize: pop.actionIcon - Theme.spacingXS
                                iconName: "close"
                                iconColor: Theme.surfaceVariantText
                                tooltipText: "Stop following (the config file is not touched)"
                                onClicked: MiseService.removeProject(modelData.key)
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.withAlpha(Theme.outline, 0.2)
            }

            // "Add project…" row, which turns into the input in place
            Rectangle {
                visible: !pop.adding
                width: parent.width
                height: pop.controlH
                radius: Theme.cornerRadius
                color: addHover.containsMouse ? Theme.primaryHoverLight : "transparent"
                MouseArea {
                    id: addHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        pop.closeMenu();
                        projectPicker.open();
                    }
                }
                // the row opens the folder browser; this is the way to paste a path or a config file
                DankActionButton {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingXXS
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: pop.iconBtn - Theme.spacingXS
                    iconSize: pop.actionIcon - Theme.spacingXS
                    iconName: "keyboard"
                    iconColor: Theme.surfaceVariantText
                    tooltipText: "Type a path instead"
                    onClicked: {
                        pop.adding = true;
                        addField.forceActiveFocus();
                    }
                }
                DankIcon {
                    id: addIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    name: "add"
                    size: Theme.iconSize - 6
                    color: Theme.primary
                }
                StyledText {
                    anchors.left: addIcon.right
                    anchors.leftMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add project…"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                }
            }

            Column {
                visible: pop.adding
                width: parent.width
                spacing: Theme.spacingXXS
                DankTextField {
                    id: addField
                    width: parent.width
                    height: pop.controlH
                    leftIconName: "folder"
                    placeholderText: "Folder or mise config path, Enter"
                    onTextEdited: addErr.text = ""
                    onAccepted: {
                        pop.addPending = true;
                        MiseService.addProject(text);
                    }
                }
                StyledText {
                    id: addErr
                    width: parent.width
                    visible: text !== ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.error
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // DMS's own folder browser (overlay layer, keeps the popout open). The folder is what gets followed:
    // the service finds its mise config, or rejects it.
    FileBrowserSurfaceModal {
        id: projectPicker
        browserTitle: "Choose a project folder"
        browserIcon: "folder"
        browserType: "generic"
        folderMode: true
        showHiddenFiles: true
        onFileSelected: path => {
            pop.addPending = true;
            MiseService.addProject(MiseService.plainPath(path));
            close();
        }
    }
}
