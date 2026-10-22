from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
POP=(ROOT/"bar/RemotePopout.qml").read_text()
SETTINGS=(ROOT/"SettingsUi.qml").read_text()
CONNECT=(ROOT/"PluginConnectSettings.qml").read_text()

class AttachedRouteTests(unittest.TestCase):
    def test_attached_expansion_not_floating(self):
        self.assertIn("implicitWidth: routeExpanded && routeCanExpandRight",POP)
        self.assertIn("devicePaneWidth + routePaneWidth",POP)
        self.assertIn("x: root.routeCanExpandRight ? root.devicePaneWidth : 0",POP)
        self.assertIn("width: root.devicePaneWidth",POP)
        self.assertNotIn("id: routeDetails",POP)
        self.assertEqual(POP.count("id: routeFlyout"),1)
        self.assertEqual(POP.count("id: vpnPanel"),1)
    def test_icons_and_countries(self):
        self.assertIn("icon: " + chr(34) + "public" + chr(34),POP)
        self.assertIn("icon: " + chr(34) + "router" + chr(34),POP)
        self.assertIn("model: vpnPanel.filteredCountries",POP)
        self.assertIn("id: allCountryList",POP)
        self.assertIn("interactive: contentHeight > height",POP)
        self.assertIn("root.countryFlag(countryOption.modelData.code)",POP)
        self.assertIn("String.fromCodePoint(127397",POP)
    def test_direct_and_tailscale_choices(self):
        self.assertIn("title: qsTr(" + chr(34) + "Direct" + chr(34) + ")",POP)
        self.assertIn("model: RemoteDesktop.RemoteStatus.exitNodes",POP)
        self.assertIn("onChosen: root.selectRoute(modelData.id)",POP)
        self.assertIn("RemoteDesktop.RemoteStatus.setExitNode(nodeId)",POP)
    def test_search_and_manual_mode(self):
        self.assertIn("placeholderText: qsTr(" + chr(34) + "Search countries" + chr(34) + ")",POP)
        self.assertIn('onClicked: root.openRoutePage("servers")',POP)
        self.assertIn("id: serverList",POP)
    def test_open_has_no_connect_side_effect(self):
        fn=POP.split("onRouteExpandedChanged: {",1)[1].split("implicitWidth: routeExpanded",1)[0]
        self.assertIn("vpnPanel.readStatus()",fn)
        self.assertNotIn("RemoteDesktop.RemoteStatus.setExitNode(",fn)
        self.assertNotIn("vpnPanel.action(",fn)
    def test_accurate_state(self):
        self.assertIn("readonly property bool vpnVerified:",POP)
        self.assertIn("verifiedCountryCode === vpnPanel.countryCode",POP)
        self.assertIn('vpn.connectAttempts < 3',POP)
    def test_transparent_settings(self):
        self.assertIn('text: qsTr("Device appearance")',SETTINGS)
        self.assertNotIn("ConnectedRect {",SETTINGS)
        self.assertNotIn("m3surfaceContainerLowest",CONNECT)
        self.assertIn("onToggled: root.writeOverride",SETTINGS)

if __name__=="__main__":
    unittest.main()
