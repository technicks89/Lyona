# attic

Code that is no longer reachable but is kept for reference.

Quickshell only scans `config/quickshell`, so QML parked here is inert: it is
not loaded, not linted, and not installed. Nothing outside this directory may
import from it — a file that earns a reference belongs back under
`config/quickshell`.

Delete a file from here once it is clear nobody wants it back.

| File | Why it is here |
|------|----------------|
| `ControlCenterActionButton.qml` | No references anywhere in the tree, and the shell creates no components dynamically, so nothing could reach it. |
| `ControlCenterOptionButton.qml` | Same. |
