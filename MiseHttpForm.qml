import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Install form for the `http:` backend: paste a mise.toml block or fill name / URL / version list and the
// options, see the spec and whether `latest` resolves, install. The text is the owner's MiseHttpDraft.
Column {
    id: form

    required property MiseHttpDraft draft
    property string target: ""   // scope the install writes to ("" = global)
    property real controlH: Theme.iconSize + Theme.spacingL
    property real chipH: Theme.iconSizeLarge - Theme.spacingXXS
    signal installed

    spacing: Theme.spacingXS
    onVisibleChanged: {
        if (visible)
            draft.check.restart();
    }

    // a labeled single-line field
    component FormField: Column {
        id: ff
        property string label: ""
        property string placeholder: ""
        property string value: ""
        property real fieldHeight: 0
        signal edited(string text)
        spacing: Theme.spacingXXS
        StyledText {
            width: parent.width
            text: ff.label
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
        }
        DankTextField {
            width: parent.width
            height: ff.fieldHeight
            placeholderText: ff.placeholder
            text: ff.value
            onTextEdited: ff.edited(text)
        }
    }

    FormField {
        width: parent.width
        fieldHeight: form.controlH
        label: "Paste a mise.toml block (optional)"
        placeholder: "[tools.\"http:name\"] …"
        value: form.draft.paste
        onEdited: t => {
            form.draft.paste = t;
            if (form.draft.fill(t))
                form.draft.paste = "";
        }
    }
    FormField {
        width: parent.width
        fieldHeight: form.controlH
        label: "Name"
        placeholder: "devin"
        value: form.draft.name
        onEdited: t => form.draft.name = t
    }
    FormField {
        width: parent.width
        fieldHeight: form.controlH
        label: "Download URL, with {{version}} in it"
        placeholder: "https://example.com/tool-{{version}}-linux-x64.tar.gz"
        value: form.draft.url
        onEdited: t => form.draft.url = t
    }
    FormField {
        width: parent.width
        fieldHeight: form.controlH
        label: "Version list URL (what `latest` resolves from)"
        placeholder: "https://api.github.com/repos/OWNER/REPO/releases"
        value: form.draft.list
        onEdited: t => form.draft.list = t
    }
    FormField {
        width: parent.width
        fieldHeight: form.controlH
        label: "Version path in that JSON (optional)"
        placeholder: ".[].tag_name"
        value: form.draft.opt.version_json_path
        onEdited: t => form.draft.setOpt("version_json_path", t)
    }
    FormField {
        width: parent.width
        fieldHeight: form.controlH
        label: "Version regex, if the list is not JSON (optional)"
        placeholder: "my-tool-v(\\d+\\.\\d+\\.\\d+)\\.tar\\.gz"
        value: form.draft.opt.version_regex
        onEdited: t => form.draft.setOpt("version_regex", t)
    }
    // GitHub's releases come newest first, and mise takes the last entry as `latest`
    Item {
        width: parent.width
        height: form.chipH
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS
            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: form.draft.opt.version_order === "semver" ? "check_box" : "check_box_outline_blank"
                size: Theme.iconSize - 4
                color: Theme.primary
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "List is not oldest first (GitHub releases): order by version"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: form.draft.setOpt("version_order", form.draft.opt.version_order === "semver" ? "" : "semver")
        }
    }
    Item {
        width: parent.width
        height: form.chipH
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS
            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: form.draft.advanced ? "expand_less" : "expand_more"
                size: Theme.iconSize - 4
                color: Theme.surfaceVariantText
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Advanced"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: form.draft.advanced = !form.draft.advanced
        }
    }
    Column {
        width: parent.width
        visible: form.draft.advanced
        spacing: Theme.spacingXS
        FormField {
            width: parent.width
            fieldHeight: form.controlH
            label: "Directories to strip when extracting (mise guesses when empty)"
            placeholder: "1"
            value: form.draft.opt.strip_components
            onEdited: t => form.draft.setOpt("strip_components", t)
        }
        FormField {
            width: parent.width
            fieldHeight: form.controlH
            label: "Folder with the binaries, inside the archive"
            placeholder: "bin"
            value: form.draft.opt.bin_path
            onEdited: t => form.draft.setOpt("bin_path", t)
        }
        FormField {
            width: parent.width
            fieldHeight: form.controlH
            label: "Rename the executable to"
            placeholder: "my-tool"
            value: form.draft.opt.rename_exe
            onEdited: t => form.draft.setOpt("rename_exe", t)
        }
        FormField {
            width: parent.width
            fieldHeight: form.controlH
            label: "Archive format, when the URL has no extension"
            placeholder: "tar.gz"
            value: form.draft.opt.format
            onEdited: t => form.draft.setOpt("format", t)
        }
        FormField {
            width: parent.width
            fieldHeight: form.controlH
            label: "Checksum URL (used by `mise lock`, not by install)"
            placeholder: "https://example.com/tool-{{version}}.tar.gz.sha256"
            value: form.draft.opt.checksum_url
            onEdited: t => form.draft.setOpt("checksum_url", t)
        }
    }
    // the exact line `mise use` gets, and whether the list answers
    StyledText {
        width: parent.width
        visible: form.draft.ready
        text: form.draft.spec
        wrapMode: Text.WrapAnywhere
        font.pixelSize: Theme.fontSizeSmall
        font.family: Theme.monoFontFamily
        color: Theme.surfaceVariantText
    }
    StyledText {
        width: parent.width
        visible: form.draft.ready
        readonly property var chk: MiseInfo.httpCheck
        readonly property bool fresh: chk.spec === form.draft.spec
        text: !fresh || chk.pending ? "Checking the version list…" : chk.latest ? "✓ latest resolves to " + chk.latest : "✗ No versions found: check the list URL, the path and the regex"
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeSmall
        color: fresh && !chk.pending && !chk.latest ? Theme.error : Theme.surfaceVariantText
    }
    DankButton {
        width: parent.width
        text: "Install latest" + (form.target ? MiseService.inLabel(form.target) : "")
        iconName: "download"
        buttonHeight: form.controlH
        enabled: form.draft.ready && !MiseJobs.busy
        onClicked: {
            MiseService.install(form.draft.spec, form.target);
            form.installed();
        }
    }
}
