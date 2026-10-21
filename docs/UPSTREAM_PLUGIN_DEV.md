# Native Caelestia plugin development migration

Experimental target: https://github.com/caelestia-dots/shell/pull/1703 (unmerged). Original default branch untouched.

- Identity: `dcqwqc/Devices` and shell requirement >=2.1.0.
- Declared types: bar-entry, bar-popout.
- Settings: Settings.qml; custom settings UI: SettingsUi.qml.
- The development parser supports `custom`, `bar-entry`, `bar-popout`, `quick-toggle`, `status-icon`, `dashboard-tab`. Only bar and quick toggles have integrated placements. Custom slot injection remains private and is not guaranteed by upstream.

## Before deployment
1. Build against isolated upstream PR #1703 and verify manifest, source paths, QML loading, and enable/disable/reload.
2. Verify actual UI placement, settings persistence, backend and device behavior.
3. Keep prior installed directory and config; verify automatic rollback before switching live plugins.
4. Do not deploy until runtime validation succeeds.

**State:** Native manifest version-gated; source functionality otherwise preserved; not yet runtime verified.
