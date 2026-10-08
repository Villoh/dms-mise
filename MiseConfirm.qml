import QtQuick

// Two-step action: the first click arms, the second within `timeout` ms fires `confirmed`.
// Bind the look to `armed`; call click() from the control and cancel() when the target changes.
QtObject {
    id: root

    property bool armed: false
    property int timeout: 3000
    signal confirmed

    readonly property Timer reset: Timer {
        interval: root.timeout
        onTriggered: root.armed = false
    }

    function click() {
        if (!armed) {
            armed = true;
            reset.restart();
            return;
        }
        cancel();
        confirmed();
    }

    function cancel() {
        armed = false;
        reset.stop();
    }
}
