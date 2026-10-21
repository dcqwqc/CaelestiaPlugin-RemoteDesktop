"""Ensure the compact Devices toolbar remains the canonical design."""
from pathlib import Path
import unittest

QML=(Path(__file__).resolve().parents[1]/"bar/RemotePopout.qml").read_text()


class RoundedActionsContract(unittest.TestCase):
    def test_all_four_controls_share_rounded_action_component(self):
        assert "component ActionButton: IconButton" in QML
        for s in ('isRound: true', 'radiusMorph: false',
                  'inactiveColour: Qt.alpha(Colours.palette.m3primary, 0.12)',
                  'label.fill: accent ? 1 : 0'):
            self.assertIn(s, QML)

    def test_icons_are_distinct_and_actions_preserved(self):
        for glyph in ('swap_horiz','desktop_windows','visibility','code'):
            self.assertIn(f'icon: "{glyph}"', QML)
        for action in ('onClicked: root.chooseMouseMode(', '"open"])',
                       'caelestia-connect-window-preview-launch', '"ssh"])'):
            self.assertIn(action, QML)

    def test_active_state_tracks_real_mode_or_session(self):
        self.assertIn('accent: root.mouseMode === "unified"', QML)
        self.assertIn('accent: hostRow.viewing', QML)
        self.assertNotIn('text: qsTr("Share mouse & keyboard")', QML)

    def test_no_overlay_tooltips_or_bulky_global_control(self):
        self.assertNotIn('Tooltip {', QML)
        self.assertNotIn('text: qsTr("Mouse & keyboard")', QML)
        self.assertIn('hint: qsTr("Preview one app (view only)")', QML)


if __name__ == "__main__":
    unittest.main()
