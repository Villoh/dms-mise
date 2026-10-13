import QtQuick
import qs.Common
import qs.Widgets

// Check-interval slider. DankSlider only counts integers, so it walks a fixed scale of steps (each one a
// round number of minutes); the step is written out in its tooltip and next to the title. Saves once, on release,
// as minutes in a string, the same value the dropdown used to store.
Column {
    id: root

    required property var settings   // the PluginSettings page it sits in
    required property string key
    property string label: ""
    property string description: ""
    property int defaultMinutes: 30

    readonly property var steps: [15, 30, 60, 120, 180, 240, 360, 480, 720, 1440, 2880, 4320, 5760, 7200, 8640, 10080]
    readonly property int defaultIndex: nearest(defaultMinutes)

    width: parent?.width ?? 0
    spacing: Theme.spacingS

    function labelFor(minutes) {
        if (minutes === 1440)
            return "Once a day";
        if (minutes === 10080)
            return "Once a week";
        if (minutes > 1440)
            return minutes / 1440 + " days";
        if (minutes < 60)
            return minutes + " minutes";
        const h = minutes / 60;
        return h + (h === 1 ? " hour" : " hours");
    }

    // a saved value that is not on the scale (an older one) lands on the closest step
    function nearest(minutes) {
        let best = 0;
        steps.forEach((s, i) => {
            if (Math.abs(s - minutes) < Math.abs(steps[best] - minutes))
                best = i;
        });
        return best;
    }

    function loadValue() {
        const m = parseInt(settings.loadValue(key, String(defaultMinutes)));
        slider.value = nearest(m > 0 ? m : defaultMinutes);
    }

    function save() {
        settings.saveValue(key, String(steps[slider.value]));
    }

    Component.onCompleted: loadValue()

    Item {
        width: parent.width
        height: 36

        StyledText {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.labelFor(root.steps[slider.value])
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.primary
            }

            DankActionButton {
                anchors.verticalCenter: parent.verticalCenter
                buttonSize: 36
                iconName: "restart_alt"
                iconSize: 20
                iconColor: Theme.surfaceVariantText
                visible: slider.value !== root.defaultIndex
                onClicked: {
                    slider.value = root.defaultIndex;
                    root.save();
                }
            }
        }
    }

    StyledText {
        width: parent.width
        visible: root.description !== ""
        text: root.description
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    DankSlider {
        id: slider
        width: parent.width
        height: 32
        minimum: 0
        maximum: root.steps.length - 1
        wheelEnabled: false
        thumbOutlineColor: Theme.surfaceContainerHigh
        // the tooltip over the handle (hover / drag) says "4 hours", not the step number
        function formatValue(v) {
            return root.labelFor(root.steps[Math.round(v)]);
        }
        onSliderDragFinished: root.save()
    }

    Item {
        width: parent.width
        height: ends.height

        StyledText {
            id: ends
            anchors.left: parent.left
            text: root.labelFor(root.steps[0])
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        StyledText {
            anchors.right: parent.right
            text: root.labelFor(root.steps[root.steps.length - 1])
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }
}
