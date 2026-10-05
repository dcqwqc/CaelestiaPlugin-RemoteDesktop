import Caelestia.Plugins

// Session preferences, editable from the Plugins page and persisted by the
// shell into ~/.config/caelestia/plugins.json under this plugin's id.
//
// kagami-remote reads the same file, so the SUPER+ALT+T keybind and a session
// started from the bar agree -- there is one source of truth rather than a UI
// that only governs half the ways in.
//
// Which machines exist stays in ~/.config/kagami/hosts.conf: that is identity,
// it needs MAC addresses, and it differs per desk.
SettingsObject {
    property int bitrate: 0
    SettingMeta on bitrate {
        label: "Bitrate"
        description: "Kbps. Zero derives it from the streamed resolution, about 20 Mbps for 1080p60."
        icon: "speed"
        inputType: SettingMeta.SpinBox
        min: 0
        max: 80000
        step: 500
    }

    property int fps: 60
    SettingMeta on fps {
        label: "Frame rate"
        icon: "60fps"
        inputType: SettingMeta.SpinBox
        min: 30
        max: 144
        step: 5
    }

    property int freezeDelay: 300
    SettingMeta on freezeDelay {
        label: "Freeze after"
        description: "Seconds the remote workspace may sit unwatched before the client is dropped. Returning inside this window is only a workspace switch."
        icon: "ac_unit"
        inputType: SettingMeta.SpinBox
        min: 15
        max: 3600
        step: 15
    }

    property bool followKeyboardLayout: true
    SettingMeta on followKeyboardLayout {
        label: "Follow the client's keyboard layout"
        description: "The streamed machine decodes key positions with its own layout, so a German keyboard on a US host types the wrong letters. This retargets only the injected keyboard; the host's own keys are untouched."
        icon: "keyboard"
        inputType: SettingMeta.Switch
    }

    property string captureSystemKeys: "always"
    SettingMeta on captureSystemKeys {
        label: "Send system shortcuts to the remote"
        description: "`always` gives the remote everything, Super included, so nothing local answers while you are in the session -- the compositor keybind that toggles it is marked dont_inhibit and is the deliberate way out. `never` keeps your own shortcuts and lets any of them release the pointer."
        icon: "keyboard_command_key"
        inputType: SettingMeta.SplitButton
        options: ["never", "fullscreen", "always"]
    }
}
