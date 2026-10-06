import QtQuick
import qs.Common
import qs.Widgets
import qs.Services
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "mise"

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
            {label: "15 minutes", value: "15"},
            {label: "30 minutes", value: "30"},
            {label: "1 hour", value: "60"},
            {label: "4 hours", value: "240"},
            {label: "Once a day", value: "1440"}
        ]
        defaultValue: "30"
    }

    SelectionSetting {
        settingKey: "panelMode"
        label: "Keybind panel"
        description: "What `dms ipc call mise toggle` opens. Overlay: centered over everything, closes on click outside, drag the header to move it. Window: a real window, so the border and rounding come from your compositor config, and it moves and resizes natively."
        options: [
            {label: "Overlay", value: "modal"},
            {label: "Window", value: "window"}
        ]
        defaultValue: "modal"
    }

    SelectionSetting {
        settingKey: "panelTab"
        label: "Keybind panel opens on"
        description: "Auto: Updates if something is pending (updates or bumps), Tools otherwise."
        options: [
            {label: "Auto", value: "auto"},
            {label: "Updates", value: "updates"},
            {label: "Tools", value: "tools"}
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

    // Ignored updates (skipped versions / ignored tools). Same list as the `ignored N` chip in the popout.
    Column {
        id: ignoredSection
        width: parent.width
        spacing: Theme.spacingS

        property var entries: PluginService.loadPluginState("mise", "ignored", []) || []

        function label(k) {
            const m = k.match(/^(.*)@([^\/@:]+)$/);
            return m ? m[1] + "  ·  skipping " + m[2] : k + "  ·  all versions";
        }

        Connections {
            target: PluginService
            function onPluginStateChanged(pluginId) {
                if (pluginId === "mise")
                    ignoredSection.entries = PluginService.loadPluginState("mise", "ignored", []) || [];
            }
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
                onClicked: PluginService.savePluginState("mise", "ignored", [])
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
                    onClicked: PluginService.savePluginState("mise", "ignored", ignoredSection.entries.filter(k => k !== modelData))
                }
            }
        }
    }
}
