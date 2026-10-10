import QtQuick
import qs.Common
import qs.Widgets
import qs.Services
import qs.Modules.Plugins
import qs.Modals.FileBrowser

PluginSettings {
    id: root
    pluginId: "mise"

    // Window mode needs DankFloatingWindow (DMS 1.6.0+); MiseWindow.qml does not compile without it
    readonly property bool windowSupported: Qt.createComponent(Qt.resolvedUrl("MiseWindow.qml")).status !== Component.Error

    StyledText {
        width: parent.width
        text: "mise"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Background check for outdated tools. Use the refresh button in the popout to check on demand."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SelectionSetting {
        settingKey: "interval"
        label: "Check interval"
        description: "How often to look for updates"
        options: [
            {
                label: "15 minutes",
                value: "15"
            },
            {
                label: "30 minutes",
                value: "30"
            },
            {
                label: "1 hour",
                value: "60"
            },
            {
                label: "4 hours",
                value: "240"
            },
            {
                label: "Once a day",
                value: "1440"
            }
        ]
        defaultValue: "30"
    }

    SelectionSetting {
        settingKey: "panelMode"
        label: "Keybind panel"
        description: "What `dms ipc call mise toggle` opens. Overlay: centered over everything, closes on click outside, drag the header to move it. Window: a real window, so the border and rounding come from your compositor config, and it moves and resizes natively." + (root.windowSupported ? "" : " Window needs DMS 1.6.0 or newer; the overlay is used until you update.")
        enabled: root.windowSupported
        options: [
            {
                label: "Overlay",
                value: "modal"
            },
            {
                label: root.windowSupported ? "Window" : "Window (needs DMS 1.6.0+)",
                value: "window"
            }
        ]
        defaultValue: "modal"
    }

    SelectionSetting {
        settingKey: "panelTab"
        label: "Keybind panel opens on"
        description: "Auto: Updates if something is pending (updates or bumps), Tools otherwise."
        options: [
            {
                label: "Auto",
                value: "auto"
            },
            {
                label: "Updates",
                value: "updates"
            },
            {
                label: "Tools",
                value: "tools"
            }
        ]
        defaultValue: "auto"
    }

    ToggleSetting {
        settingKey: "showBumps"
        label: "Show pinned / major updates"
        description: "Tools pinned to an exact version, or with a newer major, are listed with a bump button. Bumping rewrites the version in your mise config. Not counted in the badge or in Update all."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "remoteSearch"
        label: "Live search and verification"
        description: "While you type in Tools / the launcher, query npm and crates.io (gem, dotnet and GitHub after their `backend:` prefix) and check that a typed `backend:tool` exists. Sends what you type to those sites. Off = registry only."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "installUnlocked"
        label: "Install with `locked` off"
        description: "With `locked = true`, Install already works for plain tools (it writes the config, runs `mise lock`, then installs). Tools with [options] or a `.` in the name fail with a hint. On: Install runs with `locked` off for those too, and mise adds them to the lockfile. Update and Bump always follow your settings."
        defaultValue: false
    }

    SelectionSetting {
        settingKey: "projectsMode"
        label: "Project tools"
        description: "Also list, update, install and remove tools of project configs (mise.toml), not just the global one. Off: global only. Manual: only the projects you add below. Tracked: every config mise has already seen, plus the ones you add."
        options: [
            {
                label: "Off",
                value: "off"
            },
            {
                label: "Manual",
                value: "manual"
            },
            {
                label: "Tracked",
                value: "tracked"
            }
        ]
        defaultValue: "off"
    }

    SelectionSetting {
        visible: MiseProjects.mode !== "off"
        settingKey: "badgeScope"
        label: "Bar badge counts"
        description: "Global: only the global config, as before. Global + projects: also the updates and bumps of the projects you follow. The popout always shows the scope you pick there."
        options: [
            {
                label: "Global",
                value: "global"
            },
            {
                label: "Global + projects",
                value: "all"
            }
        ]
        defaultValue: "global"
    }

    // Projects: the ones you added, and the tracked ones you dropped. Same lists as the scope picker in the popout.
    Column {
        id: projectsSection
        width: parent.width
        spacing: Theme.spacingS

        readonly property bool active: MiseProjects.mode !== "off"

        Connections {
            target: MiseProjects
            function onAdded(path) {
                pathField.text = "";
                addError.text = "";
            }
            function onAddFailed(message) {
                addError.text = message;
            }
        }

        StyledText {
            text: "Projects"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: projectsSection.active ? "Browse for a project folder, or type the path of the folder or of its mise config file. Removing a project only stops following it, the file is never touched." : "Turn on Project tools above to follow projects."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS
            visible: projectsSection.active

            DankTextField {
                id: pathField
                width: parent.width - browseBtn.width - addBtn.width - parent.spacing * 2
                leftIconName: "folder"
                placeholderText: "~/code/my-project"
                onTextEdited: addError.text = ""
                onAccepted: MiseProjects.add(text)
            }

            DankButton {
                id: browseBtn
                anchors.verticalCenter: parent.verticalCenter
                text: "Browse"
                iconName: "folder_open"
                buttonHeight: pathField.height
                onClicked: projectPicker.open()
            }

            DankButton {
                id: addBtn
                anchors.verticalCenter: parent.verticalCenter
                text: "Add"
                iconName: "add"
                buttonHeight: pathField.height
                onClicked: MiseProjects.add(pathField.text)
            }
        }

        StyledText {
            id: addError
            width: parent.width
            visible: text !== ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
            wrapMode: Text.WordWrap
        }

        StyledText {
            width: parent.width
            visible: projectsSection.active && MiseProjects.manual.length === 0
            text: "No projects added."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        // your list, then the tracked ones you hid (undo)
        Repeater {
            model: projectsSection.active ? MiseProjects.manual.map(p => ({
                        path: p,
                        hidden: false
                    })).concat(MiseProjects.mode === "tracked" ? MiseProjects.hidden.filter(p => MiseProjects.tracked.includes(p) && !MiseProjects.manual.includes(p)).map(p => ({
                        path: p,
                        hidden: true
                    })) : []) : []
            delegate: Rectangle {
                required property var modelData
                width: projectsSection.width
                height: Theme.iconSize + Theme.spacingL
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceVariant, 0.1)

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: rowBtn.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: MiseProjects.label(modelData.path) + "  ·  " + modelData.path + (modelData.hidden ? "  ·  hidden" : "")
                    font.pixelSize: Theme.fontSizeSmall
                    color: modelData.hidden ? Theme.surfaceVariantText : Theme.surfaceText
                    elide: Text.ElideMiddle
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                }

                DankActionButton {
                    id: rowBtn
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: Theme.iconSize + Theme.spacingS
                    iconSize: Theme.iconSize - Theme.spacingS
                    iconName: modelData.hidden ? "undo" : "close"
                    iconColor: modelData.hidden ? Theme.primary : Theme.surfaceVariantText
                    tooltipText: modelData.hidden ? "Follow again" : "Stop following"
                    onClicked: modelData.hidden ? MiseProjects.show(modelData.path) : MiseProjects.remove(modelData.path)
                }
            }
        }
    }

    FileBrowserSurfaceModal {
        id: projectPicker
        browserTitle: "Choose a project folder"
        browserIcon: "folder"
        browserType: "generic"
        folderMode: true
        showHiddenFiles: true
        onFileSelected: path => {
            MiseProjects.add(MiseService.plainPath(path));
            close();
        }
    }

    // Ignored updates (skipped versions / ignored tools). Same list as the `ignored N` chip in the popout.
    Column {
        id: ignoredSection
        width: parent.width
        spacing: Theme.spacingS

        readonly property var entries: MiseService.ignored

        function label(k) {
            const p = MiseService.parseIgnored(k);
            return p.name + "  ·  " + (p.version ? "skipping " + p.version : "all versions") + (p.scoped ? "  ·  " + MiseProjects.label(p.scope) : "");
        }

        Item {
            width: parent.width
            height: Theme.iconSize + Theme.spacingM

            StyledText {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Ignored updates"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            DankButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: ignoredSection.entries.length > 0
                text: "Clear all"
                iconName: "delete_sweep"
                buttonHeight: Theme.iconSize + Theme.spacingS
                onClicked: MiseService.clearIgnored()
            }
        }

        StyledText {
            width: parent.width
            visible: ignoredSection.entries.length === 0
            text: "Nothing ignored. Skip a version or ignore a tool from the popout's Updates tab."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        // at most 6 rows tall, scrolls beyond that
        DankListView {
            width: parent.width
            height: Math.min(ignoredSection.entries.length, 6) * (Theme.iconSize + Theme.spacingL + Theme.spacingXS)
            visible: ignoredSection.entries.length > 0
            clip: true
            spacing: Theme.spacingXS
            model: ignoredSection.entries
            delegate: Rectangle {
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                height: Theme.iconSize + Theme.spacingL
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceVariant, 0.1)

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: undoBtn.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: ignoredSection.label(modelData)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                }

                DankActionButton {
                    id: undoBtn
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: Theme.iconSize + Theme.spacingS
                    iconSize: Theme.iconSize - Theme.spacingS
                    iconName: "undo"
                    iconColor: Theme.primary
                    tooltipText: "Stop ignoring"
                    onClicked: MiseService.unignore(modelData)
                }
            }
        }
    }
}
