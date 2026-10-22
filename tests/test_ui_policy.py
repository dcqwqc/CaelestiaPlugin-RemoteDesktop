"""Guard against reverting the current-device-first, collapsed-peers UX."""
import shutil
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
POP = (ROOT / 'bar/RemotePopout.qml').read_text()
STATUS = (ROOT / 'services/RemoteStatus.qml').read_text()
BAR = (ROOT / 'bar/RemoteEntry.qml').read_text()
SETTINGS_UI = (ROOT / 'SettingsUi.qml').read_text()
QUEST = (ROOT / 'quest/QuestSession.qml').read_text()


class DevicePanelPolicyTests(unittest.TestCase):
    def test_current_device_always_listed_independent_of_user_hide_setting(self):
        self.assertIn('return [local].concat(peers)', POP)
        self.assertIn('.filter(device => !device.isSelf && root.deviceEnabled(device))', POP)

    def test_hide_generic_loopback_peer_default(self):
        self.assertIn('String(device.name ?? "").trim().toLowerCase() === "localhost"', POP)
        self.assertIn('return [local].concat(peers)', POP)
        self.assertIn('cfg.enabled === undefined ? root.defaultDeviceEnabled(device) : !!cfg.enabled', POP)

    def test_offline_servers_remain_visible(self):
        self.assertIn('|| device.type === "server"', POP)
        self.assertIn('|| device.type === "server"', SETTINGS_UI)

    def test_current_device_has_no_expand_control(self):
        self.assertIn('readonly property bool expanded: isSelf || root.isDeviceExpanded(device.id)', POP)
        self.assertIn('visible: !hostRow.isSelf', POP)

    def test_non_green_local_diagnostic_is_automatically_visible(self):
        self.assertIn('visible: hostRow.health !== "reachable" && hostRow.expanded', POP)
        self.assertIn('RemoteDesktop.RemoteStatus.overallError', POP)
        self.assertIn('RemoteDesktop.RemoteStatus.overallHealth', POP)

    def test_expansion_persists_across_refresh(self):
        self.assertIn('property var expandedDevices: ({})', POP)
        self.assertIn('root.isDeviceExpanded(device.id)', POP)
        self.assertIn('root.toggleDeviceExpanded(hostRow.device.id)', POP)

    def test_long_content_scrolls_inside_screen_bound(self):
        self.assertIn('contentHeight: deviceContent.implicitHeight', POP)
        self.assertIn('routeExpanded ? routePaneContents.implicitHeight + 24 : 0', POP)
        self.assertIn('clip: true', POP)

    def test_aggregate_reasons_have_valid_newline_separator(self):
        self.assertIn('return errors.join(String.fromCharCode(10));', STATUS)

    def test_action_buttons_always_in_compact_row(self):
        row = POP.split('component HostRow: ColumnLayout {', 1)[1]
        # Actions appear on the same row as the name, before the inline error.
        controls = row.split('// Connect / Wake / Terminal stay on the main row', 1)[1]
        controls = controls.split('visible: hostRow.health !== "reachable" && hostRow.expanded', 1)[0]
        self.assertIn('Layout.alignment: Qt.AlignVCenter | Qt.AlignRight', controls)
        self.assertIn('RowLayout {', controls)
        self.assertNotIn('ColumnLayout {', controls)
        for action in ('Mirror phone', 'View remote desktop', 'Preview one app', 'Disconnect', 'Wake', 'Open terminal'):
            with self.subTest(action=action):
                self.assertIn(action, controls)
        self.assertNotIn('visible: !hostRow.isSelf && hostRow.expanded', controls)
        self.assertNotIn('Devices actions: labelled, expanded only', POP)

    def test_only_errors_live_below_device_row(self):
        self.assertIn('visible: hostRow.health !== "reachable" && hostRow.expanded', POP)
        self.assertIn('hostRow.healthError', POP)
        self.assertNotIn("Drop files on this device's name to send to", POP)
        self.assertNotIn('Tailscale connected · SSH TCP/22 reachable', POP)
        self.assertIn('onDropped: drop => root.sendFilesToDevice(hostRow.device, drop)', POP)

    def test_chevron_is_small_and_immediately_after_name(self):
        self.assertIn('anchors.left: deviceNameText.right', POP)
        self.assertIn('fontStyle: Tokens.font.icon.size(deviceNameText.font.pointSize).build()', POP)
        self.assertIn('onClicked: root.toggleDeviceExpanded(hostRow.device.id)', POP)
        self.assertIn('visible: !hostRow.isSelf', POP)

    def test_status_has_coloured_dot_but_no_status_word_labels(self):
        self.assertNotIn('readonly property string statusLabel:', POP)
        self.assertNotIn('qsTr("Healthy")', POP)
        self.assertNotIn('qsTr("Degraded")', POP)
        self.assertNotIn('qsTr("Offline")', POP)
        self.assertNotIn('qsTr("Checking")', POP)
        self.assertNotIn('Devices status: %1', BAR)
        self.assertIn('"#43a047"', POP)
        self.assertIn('"#d99a00"', POP)
        self.assertIn('Colours.palette.m3error', POP)

    def test_refresh_is_diagnostic_only_and_auto_polling_remains(self):
        self.assertIn('onClicked: RemoteDesktop.RemoteStatus.refreshNow()', POP)
        self.assertNotIn('onClicked: RemoteDesktop.RemoteStatus.repairConnectivity()', POP)
        self.assertIn('function refreshNow(): void', STATUS)
        self.assertIn('root.diagnoseConnectivity();', STATUS)
        self.assertIn('if (!tunnelStatusProc.running)', STATUS)
        self.assertIn('interval: 5000', STATUS)
        self.assertIn('interval: 10000', STATUS)
        # Never tear down the only remote-access path by clicking refresh.
        self.assertNotIn('"pkexec"', STATUS)
        self.assertNotIn('repairUserProc.running = true', STATUS)
        self.assertNotIn('systemctl", "restart"', STATUS)

    def test_tunnel_refresh_uses_latest_tailscale_reachability(self):
        self.assertIn('device.tunnelCandidate', STATUS)
        self.assertIn('explicitTunnelTargets.length > 0', STATUS)
        self.assertIn('.filter(device => device.online)', STATUS)
        self.assertIn('if (root.tunnelProbeTargets.length > 0)', STATUS)
        self.assertIn('is offline in the latest Tailscale status', STATUS)
        self.assertIn('replaced by a real watchdog probe as', STATUS)
        self.assertIn('root.tunnelProbeTargets.length > 0)', STATUS)

    def test_route_dropdown_uses_fixed_floating_switcher(self):
        self.assertIn("id: routeFlyout", POP)
        self.assertIn("visible: root.routeExpanded", POP)
        self.assertIn("onClicked: root.routeExpanded = !root.routeExpanded", POP)
        self.assertNotIn("id: routeMenu", POP)

    def test_refresh_reloads_tunnel_roles(self):
        self.assertIn('if (!deviceTypesProc.running)', STATUS)
        self.assertIn('root.deviceRoles = roles;' + chr(10) + '                // Initial Tailscale', STATUS)

    def test_no_oversized_device_tooltips_but_inline_errors_remain(self):
        self.assertNotIn('Tooltip {', POP)
        self.assertNotIn('Tooltip {', BAR)
        self.assertIn('visible: hostRow.health !== "reachable" && hostRow.expanded', POP)
        self.assertIn('color: Colours.palette.m3error', POP)
        self.assertIn('RemoteDesktop.RemoteStatus.overallError', BAR)

    def test_settings_agree_with_loopback_visibility(self):
        self.assertIn('String(device.name ?? "").trim().toLowerCase() === "localhost"', SETTINGS_UI)
        self.assertIn('cfg.enabled === undefined ? root.defaultEnabled(device) : !!cfg.enabled', SETTINGS_UI)

    def test_no_stale_quest_desktop_controls_in_devices(self):
        # qsw-session-mode availability is NOT proof of a connected headset.
        # Its UI used to sit below Mirai permanently even when Quest was offline.
        for stale in ('HeadsetDesktop', 'Hosted by', 'Quest desktop',
                      'choice.session.selectPrivate()', 'dcqwqc.devices.quest as Quest'):
            with self.subTest(stale=stale):
                self.assertNotIn(stale, POP)
        # CLI/session capability is retained outside the Devices popout.
        self.assertIn('root.run("select-private", ["select", "private"]);', QUEST)
        self.assertIn('readonly property bool privateSelected: available && mode === "private"', QUEST)
        self.assertIn('root.privateReady = data.private_ready === true;', QUEST)

    def test_unreachable_headset_does_not_appear_in_devices(self):
        self.assertIn('device.type === "headset" && !device.online && !root.questMirrorAvailable', POP)
        self.assertIn('return false;', POP)
        self.assertIn('device.type === "headset" && root.questMirrorAvailable', POP)
        self.assertIn('isHeadset ? (hostRow.online ? "reachable" : "offline")', POP)
        self.assertIn('onTriggered: if (!questMirrorProbe.running) questMirrorProbe.running = true', POP)

    def test_headset_row_mirrors_instead_of_ssh(self):
        self.assertIn('&& /quest/i.test(`${node.HostName} ${actionHost}`) ? "headset"', STATUS)
        self.assertIn('return "head_mounted_device";', POP)
        self.assertIn('visible: hostRow.device.canSsh && !hostRow.isHeadset', POP)
        self.assertIn('Quickshell.execDetached([root.questMirrorBin]);', POP)
        self.assertIn('running: root.visible', POP)

    def test_quest_cli_failures_clear_availability_and_propagate(self):
        self.assertIn('if (code !== 0 || !validMode) {' + chr(10) + '            root.available = false;', QUEST)
        self.assertIn('if (!running && !didStart && command.length > 0)', QUEST)
        self.assertIn('[ -x "$0" ] ||', QUEST)
        self.assertIn('root.actionError = reported || err', QUEST)
        self.assertIn('${Quickshell.env("HOME")}/.local/bin/qsw-session-mode', QUEST)

    def test_qml_syntax(self):
        exe = '/usr/lib/qt6/bin/qmlformat' if Path('/usr/lib/qt6/bin/qmlformat').exists() else shutil.which('qmlformat')
        for rel in ('bar/RemotePopout.qml', 'bar/RemoteEntry.qml', 'services/RemoteStatus.qml', 'SettingsUi.qml',
                    'quest/QuestSession.qml'):
            with self.subTest(file=rel):
                run = subprocess.run([exe, str(ROOT/rel)], text=True, capture_output=True)
                self.assertEqual(run.returncode, 0, run.stderr)


if __name__ == '__main__':
    unittest.main()
