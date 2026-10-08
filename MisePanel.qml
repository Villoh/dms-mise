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

    readonly property string summary: MiseService.error || MiseService.scopeWarning(scope) || ((count > 0 ? count + " outdated" : (MiseProjects.scopes.length ? scopeName + " is up to date" : "All up to date")) + (bumpCount ? " · " + bumpCount + " bumpable" : "") + " · " + installedRows.filter(r => r.installed).length + " installed" + checkedText)

    // on open. "updates" / "tools" are fixed; anything else is auto:
    // Updates if something is pending (updates or bumps), Tools otherwise
    function pickInitialTab(mode) {
        tab = mode === "updates" ? 0 : mode === "tools" ? 1 : (count > 0 || bumpCount > 0) ? 0 : 1;
    }

    function focusSearch() {
        field.forceActiveFocus();
    }

    property int tab: 0            // 0 = updates, 1 = tools (installed + install), 2 = mise settings
    property string updFilter: ""
    property string cfgFilter: ""
    property string query: ""
    property string backend: ""     // backend chip filter ("" = all)
    property string openRow: ""    // tools tab: the one expanded row (name|scope)
    // scope picker (Settings > Project tools): "" = global (default), "*" = everything, else a project's config path
    property string scope: ""
    property bool menuOpen: false   // scope menu (toolbar button)
    property bool fixOpen: false    // fix list (toolbar button): which scopes to trust / lock
    property bool addPending: false // an add (typed or picked) is in flight: select the project when it lands
    function closeMenu() {
        menuOpen = false;
        fixOpen = false;
        scopeMenu.reset();
    }
    // the scopes of the picked one that need the same fix (see MiseService.warnedScopes)
    readonly property var fixScopes: MiseService.warnedScopes(scope)
    // the icon of the fix button: a trust is more pressing than a lock (an untrusted project cannot be locked)
    readonly property string fixKind: fixScopes.some(s => MiseService.warnOf(s) === "untrusted") ? "untrusted" : fixScopes.length ? "unlocked" : ""
    // where Install writes: the picked scope, global when looking at everything
    readonly property string target: scope === "*" ? "" : scope
    readonly property bool showScope: scope === "*" && MiseProjects.scopes.length > 0
    readonly property var scopeOptions: [
        {
            key: "",
            label: "Global"
        },
        {
            key: "*",
            label: "All"
        }
    ].concat(MiseProjects.scopes.map(s => ({
                key: s,
                label: MiseProjects.label(s)
            })))
    readonly property string scopeName: scope === "*" ? "All" : scope === "" ? "Global" : MiseProjects.label(scope)
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
    onQueryChanged: MiseRemote.lookup(tab === 1 ? query : "")
    onTabChanged: MiseRemote.lookup(tab === 1 ? query : "")
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
        (scope === "*" ? [""].concat(MiseProjects.scopes) : [scope]).forEach(s => {
            const v = MiseService.toolsIn(s);
            MiseService.installedIn(s).forEach(n => out.push({
                    name: n,
                    scope: s,
                    installed: true,
                    direct: false,
                    sub: (v[n] || "") + (showScope ? (v[n] ? " · " : "") + MiseProjects.label(s) : "")
                }));
            // declared but not installed: listed apart, with the install button
            MiseService.missingIn(s).forEach(n => out.push({
                    name: n,
                    scope: s,
                    installed: false,
                    missing: true,
                    direct: false,
                    sub: (v[n] || "") + " · not installed" + (showScope ? " · " + MiseProjects.label(s) : "")
                }));
        });
        return out.sort((a, b) => a.name.localeCompare(b.name) || a.scope.localeCompare(b.scope));
    }
    readonly property var baseNames: tab === 0 ? updRows.filter(inScope).map(t => t.name) : installedRows.map(t => t.name)
    readonly property var backends: {
        // settings: the sections of what the filter leaves, in list order (Configured, General, then by name)
        if (tab === 2) {
            const n = {};
            const keys = [];
            MiseConfig.matching(cfgFilter).forEach(s => {
                if (!(s.section in n))
                    keys.push(s.section);
                n[s.section] = (n[s.section] || 0) + 1;
            });
            return keys.map(k => ({
                        key: k,
                        label: k + " " + n[k]
                    }));
        }
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
        // `http:` alone: a row that opens a small form (the http backend needs several options)
        const tpl = q === "http:" ? [
            {
                name: "http: custom download URL",
                scope: target,
                installed: false,
                direct: false,
                template: true,
                sub: "Fill in a form to install from a URL"
            }
        ] : [];
        return tpl.concat(installedRows.filter(hit), MiseService.search(query, target).filter(r => !r.installed).map(r => ({
                    name: r.name,
                    scope: target,
                    installed: false,
                    direct: r.direct,
                    sub: r.backend + (scope === "*" && MiseProjects.scopes.length ? " · installs globally" : "")
                })));
    }
    // mise settings (global config): only read once the tab is opened
    // the picked section chip; "" = all, also when the picked one is gone (reset the last Configured setting)
    readonly property string cfgSection: tab === 2 && backends.some(b => b.key === backend) ? backend : ""
    // with a header row ({header: true, title}) before each section: a ListView `section` header kept a stale
    // title after the list was replaced
    readonly property var cfgList: {
        const out = [];
        let last = "";
        (tab === 2 ? MiseConfig.matching(cfgFilter) : []).filter(s => !cfgSection || s.section === cfgSection).forEach(s => {
            if (!cfgSection && s.section !== last)
                out.push({
                    header: true,
                    title: s.section
                });
            last = s.section;
            out.push(s);
        });
        return out;
    }
    readonly property int shown: tab === 0 ? updList.length : tab === 1 ? toolList.length : cfgList.length
    // the `http:` form's text lives here, not in its row: the list is rebuilt now and then, and a row would lose it
    MiseHttpDraft {
        id: http
        active: pop.tab === 1
    }

    // ---- toolbar: tabs, scope picker, fix, refresh ----
    MisePanelToolbar {
        id: toolbar
        width: parent.width
        count: pop.count
        tab: pop.tab
        scope: pop.scope
        scopeName: pop.scopeName
        menuOpen: pop.menuOpen
        fixOpen: pop.fixOpen
        fixKind: pop.fixKind
        fixCount: pop.fixScopes.length
        elsewhere: pop.elsewhere
        checking: pop.checkingShown
        controlH: pop.controlH
        iconBtn: pop.iconBtn
        onTabPicked: index => pop.tab = index
        onScopeClicked: pop.menuOpen ? pop.closeMenu() : (pop.menuOpen = true)
        onFixClicked: {
            if (pop.fixOpen) {
                pop.closeMenu();
                return;
            }
            fixMenu.open();
            pop.fixOpen = true;
        }
    }

    // ---- job banner: what mise is doing right now ----
    MiseJobBanner {
        id: banner
        anchors.top: toolbar.bottom
        anchors.topMargin: Theme.spacingS
        width: parent.width
    }

    Connections {
        target: MiseProjects
        function onScopesChanged() {
            if (pop.scope !== "*" && pop.scope !== "" && !MiseProjects.scopes.includes(pop.scope))
                pop.scope = "";
        }
        function onModeChanged() {
            if (MiseProjects.mode === "off") {
                pop.scope = "";
                pop.closeMenu();
            }
        }
        function onAdded(path) {
            if (!pop.addPending)
                return;
            pop.addPending = false;
            pop.scope = path;
            pop.closeMenu();
        }
        function onAddFailed(message) {
            if (!pop.addPending)
                return;
            pop.addPending = false;
            // typed: the error shows under the field. Picked: the menu is already closed, so a toast
            if (scopeMenu.adding)
                scopeMenu.showError(message);
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
        placeholderText: pop.tab === 0 ? "Filter updates…" : pop.tab === 1 ? "Search installed & registry, or type backend:tool…" : "Filter mise settings…"
        onTextEdited: {
            if (pop.tab === 0)
                pop.updFilter = text;
            else if (pop.tab === 1)
                pop.query = text;
            else
                pop.cfgFilter = text;
        }
        // Enter installs the top not-yet-installed hit
        onAccepted: {
            if (pop.tab !== 1 || MiseJobs.busy)
                return;
            const r = pop.toolList.find(x => !x.installed && !x.missing && !x.template);
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
        visible: pop.tab === 1 && MiseRemote.lookingUp

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
        enabled: pop.scopedCount > 0 && !MiseJobs.busy
        onClicked: MiseService.upgrade("", pop.scope)
    }

    // rewrites pins in your config: arm first, click again to confirm
    DankButton {
        id: bumpAll
        readonly property bool armed: bumpConfirm.armed
        visible: pop.tab === 0 && pop.scopedBumps > 0
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: (parent.width - Theme.spacingS) / 2
        text: armed ? "Confirm bump (" + pop.scopedBumps + ")" : "Bump all (" + pop.scopedBumps + ")"
        iconName: armed ? "check" : "upgrade"
        buttonHeight: pop.controlH + Theme.spacingXS
        backgroundColor: armed ? Theme.error : Theme.warning
        textColor: Theme.surface
        enabled: !MiseJobs.busy
        onClicked: bumpConfirm.click()
        MiseConfirm {
            id: bumpConfirm
            onConfirmed: MiseService.bumpAll(pop.scope)
        }
    }

    // versions no config uses: arm first, click again to confirm
    DankButton {
        id: pruneAll
        readonly property bool armed: pruneAllConfirm.armed
        visible: pop.tab === 1 && MiseService.prunableCount > 0
        anchors.bottom: parent.bottom
        width: parent.width
        text: armed ? "Confirm prune (" + MiseService.prunableCount + ")" : "Prune unused versions (" + MiseService.prunableCount + ")"
        iconName: armed ? "check" : "delete_sweep"
        buttonHeight: pop.controlH + Theme.spacingXS
        backgroundColor: armed ? Theme.error : Theme.surfaceContainerHigh
        textColor: armed ? Theme.surface : Theme.surfaceText
        enabled: !MiseJobs.busy
        onClicked: pruneAllConfirm.click()
        MiseConfirm {
            id: pruneAllConfirm
            onConfirmed: MiseService.prune("")
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
            field.text = pop.tab === 0 ? pop.updFilter : pop.tab === 1 ? pop.query : pop.cfgFilter;
            if (pop.tab === 2)
                MiseConfig.refresh();   // the config may have been edited by hand
        }
    }

    // ---- backend filter chips (updates, or tools when not searching); settings: section chips ----
    MiseBackendChips {
        id: chips
        anchors.top: field.bottom
        anchors.topMargin: visible ? Theme.spacingS : 0
        width: parent.width
        visible: pop.tab === 2 ? pop.backends.length > 1 : !pop.searching && (pop.backends.length > 1 || (pop.tab === 0 && MiseService.ignored.length > 0))
        chipH: pop.chipH
        current: pop.tab === 2 ? pop.cfgSection : pop.backend
        options: [
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
        onPicked: key => pop.backend = key
    }

    // a backend of this query did not answer (the loading bar is gone by then)
    StyledText {
        id: notice
        anchors.top: chips.bottom
        anchors.topMargin: visible ? Theme.spacingS : 0
        width: parent.width
        height: visible ? implicitHeight : 0
        visible: pop.tab === 1 && MiseRemote.notices.length > 0
        text: MiseRemote.notices.join("\n")
        color: Theme.warning
        font.pixelSize: Theme.fontSizeSmall
        elide: Text.ElideRight
    }

    // ---- lists ----
    Rectangle {
        anchors.top: notice.bottom
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
                if (pop.tab === 2)
                    return MiseConfig.all.length ? "No settings match" : "Loading settings…";
                if (!pop.searching)
                    return "Nothing installed yet.\nType a name, or any backend:tool\ne.g. pipx:package, npm:package, cargo:crate, github:owner/repo\nOptions: pipx:package[uvx_args=--python 3.14]";
                if (MiseRemote.lookingUp)
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

            delegate: MiseUpdateRow {
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                row: modelData
                showScope: pop.showScope
                rowH: pop.rowH
                iconBtn: pop.iconBtn
                actionIcon: pop.actionIcon
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

            delegate: MiseToolRow {
                width: ListView.view ? ListView.view.width : 0
                open: pop.openRow === key
                target: pop.target
                draft: http
                rowH: pop.rowH
                controlH: pop.controlH
                iconBtn: pop.iconBtn
                chipH: pop.chipH
                onToggled: pop.openRow = open ? "" : key
                onInstalled: pop.openRow = ""
            }
        }

        // mise settings: switch or value per row
        DankListView {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            visible: pop.tab === 2 && pop.cfgList.length > 0
            clip: true
            spacing: Theme.spacingXS
            model: pop.cfgList

            delegate: Loader {
                id: cfgItem
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                sourceComponent: modelData.header ? cfgHeader : cfgRow

                Component {
                    id: cfgHeader
                    StyledText {
                        height: implicitHeight + Theme.spacingM
                        verticalAlignment: Text.AlignBottom
                        leftPadding: Theme.spacingM
                        text: cfgItem.modelData.title
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: Theme.surfaceVariantText
                    }
                }
                Component {
                    id: cfgRow
                    MiseConfigRow {
                        row: cfgItem.modelData
                        iconBtn: pop.iconBtn
                        actionIcon: pop.actionIcon
                    }
                }
            }
        }
    }

    // ---- scope menu and fix list: open under the toolbar. The scrim swallows clicks outside, so nothing else
    // in the panel is reachable (or half-typed) while one is open ----
    MouseArea {
        anchors.fill: parent
        z: 10
        visible: pop.menuOpen || pop.fixOpen
        onClicked: pop.closeMenu()
        onWheel: wheel => wheel.accepted = true
        // don't scroll the list underneath
    }

    MiseFixMenu {
        id: fixMenu
        z: 11
        visible: pop.fixOpen && pop.fixScopes.length > 0
        anchors.top: toolbar.bottom
        anchors.topMargin: Theme.spacingXS
        anchors.right: parent.right
        width: Math.min(parent.width, pop.controlH * 8)
        scopes: pop.fixScopes
        controlH: pop.controlH
        onRun: scopes => {
            pop.closeMenu();
            MiseService.fix(scopes);
        }
    }

    MiseScopeMenu {
        id: scopeMenu
        z: 11
        visible: pop.menuOpen
        anchors.top: toolbar.bottom
        anchors.topMargin: Theme.spacingXS
        anchors.right: parent.right
        width: Math.min(parent.width, pop.controlH * 7)
        options: pop.scopeOptions
        scope: pop.scope
        pendingIn: pop.pendingIn
        controlH: pop.controlH
        iconBtn: pop.iconBtn
        actionIcon: pop.actionIcon
        onPicked: key => {
            pop.scope = key;
            pop.closeMenu();
        }
        onBrowse: {
            pop.closeMenu();
            projectPicker.open();
        }
        onAddTyped: path => {
            pop.addPending = true;
            MiseProjects.add(path);
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
            MiseProjects.add(MiseService.plainPath(path));
            close();
        }
    }
}
