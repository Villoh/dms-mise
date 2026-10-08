import QtQuick

// What is typed into the `http:` install form, and the `mise use` spec it adds up to. Lives on the
// panel so the text survives the tool list being rebuilt; asks MiseInfo whether `latest` resolves.
QtObject {
    id: draft

    property bool active: true   // check the version list only while the form can be seen
    property string name: ""
    property string url: ""
    property string list: ""
    property string paste: ""
    property bool advanced: false
    // the optional tool options, in the order they are written; empty = left out
    property var opt: ({
            version_json_path: "",
            version_regex: "",
            version_order: ""   // "semver" = the list is not oldest-first
            ,
            strip_components: "",
            bin_path: "",
            rename_exe: "",
            format: "",
            checksum_url: ""
        })
    function setOpt(k, v) {
        const o = Object.assign({}, opt);
        o[k] = v;
        opt = o;
    }
    // fills the form from a pasted `[tools."http:name"]` block or `"http:name" = { … }` line. Keys are looked
    // up one by one, so it works with newlines, spaces or neither (a single-line field may drop them).
    function fill(txt) {
        // "double", 'single' (regexes) or a bare number
        const val = k => {
            const m = new RegExp("\\b" + k + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|(\\d+))").exec(txt);
            return m ? (m[1] || m[2] || m[3] || "") : "";
        };
        const n = /http:([^"'\]\s=]+)/.exec(txt);
        const url = val("url");
        if (!n && !url)
            return false;
        if (n)
            name = n[1];
        if (url)
            url = url;
        const list = val("version_list_url");
        if (list)
            list = list;
        // a paste replaces the options too, so nothing from an earlier one is left behind
        const o = {};
        Object.keys(opt).forEach(k => o[k] = val(k));
        opt = o;
        return true;
    }

    // once the fields stop changing, ask mise what the version list gives
    onSpecChanged: check.restart()
    readonly property Timer check: Timer {
        interval: 600
        onTriggered: {
            if (draft.ready && draft.active)
                MiseInfo.checkHttp(draft.spec);
        }
    }
    readonly property bool ready: name.trim() !== "" && url.trim() !== "" && list.trim() !== ""
    // version_list_url is what lets `latest` resolve
    readonly property string spec: "http:" + name.trim() + "[url=" + url.trim() + ",version_list_url=" + list.trim() + Object.keys(opt).filter(k => opt[k].trim() !== "").map(k => "," + k + "=" + opt[k].trim()).join("") + "]@latest"
}
