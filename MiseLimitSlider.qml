import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

// Slider for one of the result limits. Saves once, when you let go, instead of on every step of the drag
// (SliderSetting does the latter, and DMS reloads every setting after each save).
SettingsSliderRow {
    required property var settings   // the PluginSettings page it sits in
    required property string key

    minimum: 1

    // the row pads its content by spacingM; the other settings in the card do not
    x: -Theme.spacingM
    width: (parent?.width ?? 0) + Theme.spacingM * 2

    function loadValue() {
        value = settings.loadValue(key, defaultValue);
    }

    Component.onCompleted: loadValue()
    onSliderDragFinished: finalValue => settings.saveValue(key, finalValue)
}
