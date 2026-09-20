# Sync Sprint 5 — Settings load stability, Flathub verification, floating toggles

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). Upstream surveyed at `d155edc`
(2026-09-18), found by [S4-08](SYNC-SPRINT-4-COMPOSITOR-DEFAULTS-RELEASE.md#s4-08-re-survey-and-release-qualification)'s
re-survey of `d4c6d89..origin/main`: 12 non-merge commits, belonging to Chris's
issues `#330` and `#332` and PRs `#329`, `#331` and `#333`–`#339`.

**Goal:** the three pieces of that range that apply to Lyona, and the record
of why the rest does not. Independent of each other; land them as separate
commits in the order below.

| Item | Upstream | Kind | Size |
| --- | --- | --- | --- |
| [S5-01](#s5-01-settings-panes-stay-hidden-until-their-data-has-loaded) | `#335` `709bcd0`, `4b0d438` — **completes Lyona's `#315`** | Port | ~+180 code, ~+110 tests |
| [S5-02](#s5-02-verify-the-flathub-remote-before-a-flatpak-install) | `#334` `dd64bbf`, issue `#332` | Port, adapted | ~+60 script, ~+70 tests |
| [S5-03](#s5-03-floating-toggles-visibly-shrink-the-window) | `#331` `2e77c11`, `#333` `841d3cd` | Port — **decision D-9** | ~+40 C, ~+80 tests |

Not taken: see [Declined](#declined-from-this-survey).

---

## S5-01: Settings panes stay hidden until their data has loaded

Upstream `#335` (`709bcd0`, then `4b0d438`, which fixes a race in the first).

### Why this exists

Lyona already has a `#315` implementation ([S3-05](SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md#s3-05-settings-readiness-and-startup-work)),
written when upstream had none. It only covers the **component** load: it
fades the pane in as soon as `Loader.Ready`. The pane's first **data** reads
finish afterwards, so cards still appear and reflow inside a visible pane. That
is exactly what `#335` fixes, and S3-05's own note said the in-pane part was
unresolved. **This replaces S3-05's placeholder and fade-in.**

### What upstream did

- Every model exposes a read-only `initialLoading`: true while a *finite*
  initial read is running or queued (never for resident watch subscriptions).
- `DeferredSettingsPane` takes `dataLoading`, stays invisible and disabled
  until the component is `Ready` **and** `dataLoading` is false, then presents
  once (a zero-interval timer, so the layout has polished). Later refreshes
  never hide controls again.
- `4b0d438`: each `…Pending = false` moves to **after** the process starts
  (see [the ordering rule](#the-ordering-rule)), so `initialLoading` has no
  frame where a queued refresh is about to run but nothing reports it.

### `config/quickshell/settings/DeferredSettingsPane.qml`

Take upstream's file **verbatim**. It removes S3-05's `Rectangle`
placeholder and `fadeIn` animation; `Theme.reducedMotion` is no longer needed
here because nothing animates.

```qml
import QtQuick
import qs.core

Loader {
    id: root

    required property bool selected
    required property bool windowVisible
    property bool dataLoading: false
    property bool visited: false
    property bool presented: false

    // Keep visited items alive to preserve drafts and scroll positions. Reserve
    // the whole pane while its initial asynchronous snapshot and layout settle.
    active: visited
    asynchronous: true
    visible: selected
    focus: true

    function updatePresentation() {
        if (!windowVisible || !selected) return;
        visited = true;
        if (!presented && status === Loader.Ready && !dataLoading)
            presentationTimer.restart();
    }
    onSelectedChanged: updatePresentation()
    onWindowVisibleChanged: updatePresentation()
    onDataLoadingChanged: updatePresentation()
    onStatusChanged: updatePresentation()
    Component.onCompleted: updatePresentation()

    // Opacity keeps the loaded layout participating in polish while hiding
    // intermediate geometry. Later refreshes never hide usable controls.
    Binding {
        target: root.item
        property: "opacity"
        value: root.presented ? 1 : 0
        when: root.item !== null
    }
    Binding {
        target: root.item
        property: "enabled"
        value: root.presented
        when: root.item !== null
    }
    Timer {
        id: presentationTimer
        interval: 0
        onTriggered: {
            if (root.windowVisible && root.selected && root.status === Loader.Ready
                    && !root.dataLoading)
                root.presented = true;
        }
    }
    UiText {
        anchors.centerIn: parent
        width: Math.max(0, parent.width - Theme.spacingXl * 2)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        visible: !root.presented
        text: root.status === Loader.Error ? "This settings panel could not be loaded."
            : "Loading settings..."
        color: Theme.menuMutedText
    }
}
```

### The flags, mapped onto Lyona's models

Every process id below was checked to exist in Lyona's file. Add each line
near the top of the named model.

```diff
 network/NetworkModel.qml
+    readonly property bool initialLoading: snapshotProcess.running || editorCheckProcess.running

 controls/BluetoothModel.qml
+    readonly property bool initialLoading: snapshotProcess.running || statusProcess.running || devicesProcess.running

 controls/ControlsModel.qml
+    readonly property bool initialLoading: audioSnapshotProcess.running || volumeStatusProcess.running
+        || micStatusProcess.running || mediaStatusProcess.running || bluetoothStatusProcess.running

 defaults/AutostartModel.qml, defaults/DefaultAppsModel.qml, power/PowerModel.qml
+    readonly property bool initialLoading: snapshotProcess.running || root.snapshotPending

 accessibility/AccessibilityModel.qml, panel/PanelSettingsModel.qml
+    readonly property bool initialLoading: statusProcess.running || root.refreshPending

 notifications/NotificationModel.qml
+    readonly property bool initialLoading: policyState === "loading" || policyState === "defaults" || policySaving

 appearance/PicomModel.qml
+    readonly property bool statusBusy: statusProcess.running || root.pending

 systemmanagement/SystemManagementModel.qml
+    readonly property bool initialLoading: root.settingsVisible && (!root.discoveryReady()
+        || root.snapshotOwned || root.snapshotPending)
```

`appearance/AppearanceModel.qml`. Upstream's list, with Lyona's toolkit
provider in place of upstream's personalization provider (Lyona has no
`personalization*` state; see `UPSTREAM-SYNC.md`):

```diff
     property bool settingsVisible: false
+    // Only finite initial reads belong here, never resident subscriptions.
+    readonly property bool initialLoading: snapshotProcess.running || root.snapshotPending
+        || readinessProcess.running || root.mutationReadinessPending
+        || previewStatusProcess.running || recoveryStatusProcess.running
+        || root.wallpaperStatusBusy || root.fontStatusBusy
+        || root.toolkitStatusBusy || root.toolkitStatusPending
+        || root.fontStatusPending || picomModel.statusBusy
```

`settings/SettingsModel.qml`. Lyona already has `displayActionProcess`,
`inputActionProcess` and `automaticDisplayBusy`:

```diff
     property bool displayRefreshPending: false
+    readonly property bool displayActionBusy: displayActionProcess.running
 …
     property bool inputRefreshPending: false
+    readonly property bool inputActionBusy: inputActionProcess.running
```

### `config/quickshell/settings/SettingsWindow.qml`

One `dataLoading:` line per `DeferredSettingsPane`, directly under its
`selected:` line, plus a fixed height for the message row so it cannot push
the panes down when its text appears:

```diff
 selected: root.settingsModel.selectedSectionId === "displays"
+dataLoading: root.settingsModel.displayState === "loading" || root.settingsModel.displayRefreshPending || root.settingsModel.automaticDisplayBusy || root.settingsModel.automaticDisplayRefreshPending || root.settingsModel.displayActionBusy
 selected: root.settingsModel.selectedSectionId === "input"
+dataLoading: root.settingsModel.inputState === "loading" || root.settingsModel.inputRefreshPending || root.settingsModel.inputActionBusy
 selected: root.settingsModel.selectedSectionId === "network"
+dataLoading: root.networkModel.initialLoading
 selected: root.settingsModel.selectedSectionId === "bluetooth"
+dataLoading: root.bluetoothModel.initialLoading
 selected: root.settingsModel.selectedSectionId === "audio"
+dataLoading: root.controlsModel.initialLoading
 selected: root.settingsModel.selectedSectionId === "power"
+dataLoading: root.powerModel.initialLoading
 selected: root.settingsModel.selectedSectionId === "defaults"
+dataLoading: root.defaultsModel.initialLoading || root.autostartModel.initialLoading
 selected: root.settingsModel.selectedSectionId === "appearance"
+dataLoading: root.appearanceModel.initialLoading || root.accessibilityModel.initialLoading
+    || root.panelSettingsModel.initialLoading || root.notificationModel.initialLoading
+    || root.settingsModel.busy || root.settingsModel.capabilityRefreshPending
 selected: root.settingsModel.selectedSectionId === "system"
+dataLoading: root.systemManagementModel.initialLoading

 UiText {
     Layout.fillWidth: true
+    Layout.preferredHeight: Math.ceil(Theme.fontBodySmallSize * 1.5)
     text: root.settingsModel.message
```

Upstream's `system` line also ORs in `desktopUpdateModel.initialLoading`.
**Drop that term:** `DesktopUpdateModel` is upstream's git-`main` updater,
declined under D-8 (see [Declined](#declined-from-this-survey)).

### The ordering rule

From `4b0d438`. A pending flag must stay true until the process it queued
has actually started, or `initialLoading` (`running || pending`) can be false
for one frame between "queued" and "running". Move every clear **after** the
start; delete the ones inside `onRunningChanged`, because the refresh function
they call clears the flag itself once it has started:

```diff
 function refreshSnapshot() {
     …
-    root.snapshotPending = false;
     root.snapshotRunGeneration = root.snapshotGeneration;
     root.snapshotParsed = false;
     snapshotProcess.running = true;
+    root.snapshotPending = false;
 }
 …
 onRunningChanged: {
     if (!running && root.snapshotPending) {
-        root.snapshotPending = false;
         Qt.callLater(root.refreshSnapshot);
     }
 }
```

Audit each of these in Lyona (every `…Pending = false;`, checked with
`grep -n "Pending = false;"` on 2026-09-20). Apply the rule wherever the
flag feeds an `initialLoading` above; leave the others alone.

| File | Flags to reorder |
| --- | --- |
| `appearance/AppearanceModel.qml` | `snapshotPending`, `mutationReadinessPending`, `wallpaperStatusPending`, `inventoryPending` + `inventoryPendingAllowUnwatched`, `fontStatusPending`, `toolkitStatusPending` |
| `defaults/AutostartModel.qml` (`:134`, `:144`, `:259`), `defaults/DefaultAppsModel.qml` (`:177`, `:186`, `:238`), `power/PowerModel.qml` (`:265`, `:277`, `:538`) | `snapshotPending` |
| `accessibility/AccessibilityModel.qml` (`:36`), `panel/PanelSettingsModel.qml` (`:64`) | `refreshPending` |
| `systemmanagement/SystemManagementModel.qml` (`:558`, `:653`) | `snapshotPending`, `requiredPending` |
| `settings/SettingsModel.qml` | `displayRefreshPending`, `inputRefreshPending`, `automaticDisplayRefreshPending`, `capabilityRefreshPending` — **`capabilityRefreshPending` is Lyona's own port from S3-09 (`#191`); reorder it the same way** |

Read each site first: some of those lines are the *start* of a refresh (move
the clear below `running = true`) and some are inside `onRunningChanged`
(delete the clear).

### Tests

Take upstream's test changes and adapt them:

```bash
git -C "$U" show 709bcd0 4b0d438 -- tests/fixtures/settings-responsiveness.py tests/qml/SettingsResponsiveness.inc
```

- The fixture delays the providers; the harness asserts each pane's **first
  child `y` is unchanged** between `Loader.Ready` and two seconds later. That
  is `#315`'s acceptance, which
  [S3-05](SYNC-SPRINT-3-DISPLAYS-AND-SETTINGS.md#issue-315-open-upstream-no-layout-shift-while-panels-load)
  deferred until Sprint 3 and 4 had landed. Record the result.
- Lyona's harness already carries the 200%-text stage from S3-07; append, do
  not replace.
- Provider names in the fixture that mention personalization map to Lyona's
  toolkit provider.
- Add grep assertions for each `initialLoading` line and for the removal of
  `root.snapshotPending = false;` from the `onRunningChanged` handlers, next to
  the existing model-contract tests.

---

## S5-02: Verify the Flathub remote before a Flatpak install

Upstream issue `#332`, PR `#334` (`dd64bbf`). The issue asks that every
Flatpak install happen only after Flatpak is installed **and** the official
Flathub remote is configured and *verified*.

### What Lyona already does, and the gap

`scripts/install-gearlever` (Lyona's only Flatpak installer; the other
`flatpak` mentions are the launcher and a package scanner) checks that
`flatpak` exists, refuses a `flathub` remote whose URL is not the official
one, and adds the remote when missing. It does **not**:

- refuse a `flathub` remote that has **signature verification disabled**
  (`no-gpg-verify`), so an app could be installed from an unverified remote;
- refuse a **disabled** remote (the install then fails late and confusingly);
- re-verify after adding the remote.

### New file `scripts/dwm-flatpak-setup`

Upstream's script, with the Fedora wording changed. It stays scope-aware
(`--user | --system`) so any future Flatpak install reuses it instead of
repeating the checks, which is the issue's "cannot bypass it" point:

```bash
#!/usr/bin/env bash
# Configure the official remote before installing applications in this scope.
set -euo pipefail

case ${1:-} in
--user | --system) scope=$1 ;;
*)
	printf 'Usage: dwm-flatpak-setup --user|--system\n' >&2
	exit 2
	;;
esac
[[ $# == 1 ]] || exit 2

if ! command -v flatpak >/dev/null 2>&1; then
	printf 'Flatpak setup requires the flatpak package; rerun install.sh with the recommended profile.\n' >&2
	exit 1
fi

verify_remote() {
	local remotes remote url options
	# Capture first so a failed query cannot be lost in process substitution.
	remotes=$(flatpak remotes "$scope" --show-disabled --columns=name,url,options) || return 1
	while IFS=$'\t' read -r remote url options; do
		[[ $remote == flathub ]] || continue
		if [[ ${url%/} != https://dl.flathub.org/repo ]]; then
			printf 'Refusing non-official %s Flathub remote URL: %s\n' "${scope#--}" "$url" >&2
			return 1
		fi
		case ,$options, in
		*,no-gpg-verify,*)
			printf 'The %s Flathub remote has signature verification disabled; repair it before installing apps.\n' "${scope#--}" >&2
			return 1
			;;
		*,disabled,*)
			printf 'The %s Flathub remote is disabled; enable it before installing apps.\n' "${scope#--}" >&2
			return 1
			;;
		esac
		return 0
	done <<<"$remotes"
	return 3
}

if verify_remote; then
	printf 'Flatpak and %s Flathub are ready.\n' "${scope#--}"
	exit 0
else
	status=$?
	[[ $status == 3 ]] || exit "$status"
fi

printf 'Adding the official %s Flathub remote...\n' "${scope#--}"
flatpak remote-add "$scope" --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
if ! verify_remote; then
	printf 'The %s Flathub remote could not be verified after setup.\n' "${scope#--}" >&2
	exit 1
fi
printf 'Flatpak and %s Flathub are ready.\n' "${scope#--}"
```

### `scripts/install-gearlever`

**Adaptation from upstream.** Upstream also runs the helper on the
"already installed" early-exit paths, which would make an app that is already
installed report a setup failure because of a remote problem. The issue is
about ordering *before an install*, so Lyona runs it only there. The
system-scope branch (factory images) has no Lyona counterpart.

```diff
 readonly FLATHUB_REMOTE=flathub
-readonly FLATHUB_REPOSITORY=https://dl.flathub.org/repo/flathub.flatpakrepo
-readonly FLATHUB_URL=https://dl.flathub.org/repo/
 readonly APPIMAGE_MIME=application/vnd.appimage
 …
-remote_present=false
-while IFS=$'\t' read -r remote remote_url; do
-	if [[ $remote == "$FLATHUB_REMOTE" ]]; then
-		…
-	fi
-done < <(flatpak remotes --user --columns=name,url)
-
-if [[ $remote_present != true ]]; then
-	printf 'Adding the user-scoped Flathub remote for Gear Lever...\n'
-	flatpak remote-add --user --if-not-exists \
-		"$FLATHUB_REMOTE" "$FLATHUB_REPOSITORY"
-fi
+helper_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
+# Verified, not just present: an unofficial, disabled or unsigned remote
+# stops the install before anything is fetched from it.
+"$helper_dir/dwm-flatpak-setup" --user

 printf 'Installing Gear Lever from Flathub for %s...\n' "$(id -un)"
```

### Registration

```diff
 INSTALL_COMMANDS = \
+	scripts/dwm-flatpak-setup \
```

Add `scripts/dwm-flatpak-setup` to `check-shell` and `check-format` (it is a
Bash script), and to `UPSTREAM-SYNC.md`'s helper notes. The
`FLATHUB_REMOTE=flathub` constant stays: it is still used by the install
line.

### Tests

Port the gearlever test changes:

```bash
git -C "$U" show dd64bbf -- tests/test-install-gearlever.sh
```

Cases to cover, with a stub `flatpak` that reports a scripted `remotes`
output: official verified remote is accepted and nothing is added; **a
`no-gpg-verify` remote is refused and no install runs**; a disabled remote is
refused; a wrong URL is refused; a missing remote is added and then verified;
a remote that still fails verification after being added is refused; and an
app that is already installed exits without calling the helper.

---

## S5-03: Floating toggles visibly shrink the window

Upstream `#331` (`2e77c11`) and `#333` (`841d3cd`, which moves the shared
math into `shrinkfloating()`).

### Decision D-9 — ask the user before starting

This changes how the window manager behaves, not just how it is built.
Today, `togglefloating` on a tiled window floats it at its **current tile
size**, so nothing visibly happens (the report behind `#331`). Upstream now
shrinks it to **85% and centers it** (clamped to the monitor's work area), and
also shrinks tiled windows when the **layout** switches to floating.

Lyona's `dwm.c` has upstream's exact pre-fix code, so the change applies
cleanly. The choice is whether Lyona wants the behavior:

| Option | Effect |
| --- | --- |
| **Port as upstream (recommended)** | 85%, centered, on `Super+Shift+M` / `Super+Space` and on switching to the floating layout. Mouse drags keep their geometry |
| Port with another factor | Same code, different percentage |
| Decline | Keep today's behavior; record it as a preference |

### `dwm.c` — the combined final state of `#331` and `#333`

```diff
 static void setlayout(const Arg *arg);
+static void shrinkfloating(Client *c);
 …
 void
 setlayout(const Arg *arg)
 {
+	Client *c;
+	int wasarranged = selmon->lt[selmon->sellt]->arrange != NULL;
+
 	if (!arg || !arg->v || arg->v != selmon->lt[selmon->sellt]) {
 …
 	selmon->lt[selmon->sellt] = selmon->pertag->ltidxs[selmon->pertag->curtag][selmon->sellt];
 
+	if (wasarranged && !selmon->lt[selmon->sellt]->arrange)
+		for (c = selmon->clients; c; c = c->next)
+			if (ISVISIBLE(c) && !c->isfloating && !c->isfixed
+			    && (!c->isfullscreen || c->fakefullscreen == 1))
+				shrinkfloating(c);
+
 	copystr(selmon->ltsymbol, sizeof selmon->ltsymbol,
 …
+void
+shrinkfloating(Client *c)
+{
+	int x, y, w, h;
+
+	x = c->x;
+	y = c->y;
+	w = MAX(1, c->w * 85 / 100);
+	h = MAX(1, c->h * 85 / 100);
+	applysizehints(c, &x, &y, &w, &h, 0);
+	x = c->x + (c->w - w) / 2;
+	y = c->y + (c->h - h) / 2;
+	x = MAX(c->mon->wx, MIN(x, c->mon->wx + c->mon->ww - w - 2 * c->bw));
+	y = MAX(c->mon->wy, MIN(y, c->mon->wy + c->mon->wh - h - 2 * c->bw));
+	resizeclient(c, x, y, w, h);
+}
+
 void
 togglefloating(const Arg *arg)
 {
-	if (!selmon->sel)
+	Client *c = selmon->sel;
+	int wasfloating;
+
+	if (!c)
 		return;
-	if (selmon->sel->isfullscreen && selmon->sel->fakefullscreen != 1)
+	if (c->isfullscreen && c->fakefullscreen != 1)
 		return;
-	selmon->sel->isfloating = !selmon->sel->isfloating || selmon->sel->isfixed;
-	if (selmon->sel->isfloating)
-		resize(selmon->sel, selmon->sel->x, selmon->sel->y,
-			selmon->sel->w, selmon->sel->h, 0);
+	wasfloating = c->isfloating;
+	c->isfloating = !wasfloating || c->isfixed;
+	if (c->isfloating) {
+		if (arg && !wasfloating && !c->isfixed && c->mon->lt[c->mon->sellt]->arrange) {
+			/* Explicit toggles pop out of the tile; mouse drags keep their geometry. */
+			shrinkfloating(c);
+		} else {
+			resize(c, c->x, c->y, c->w, c->h, 0);
+		}
+	}
 	arrange(selmon);
 }
```

`docs/PATCH-OWNERSHIP.md` names neither `togglefloating` nor `setlayout` (its
only floating rule is that swallowing must respect `swallowfloating`), so it
needs no entry unless this becomes a documented Lyona-owned behavior. Add the
behavior to `docs/src/keybinds.md` and `CHANGELOG.md`.

### Tests

```bash
git -C "$U" show 841d3cd -- tests/test-xvfb-runtime.sh   # the final state; 2e77c11's intermediate version is superseded
```

`tests/test-xvfb-runtime.sh` already exists. Cover: an explicit toggle floats a
tiled window at 85% inside the work area and centered; toggling back re-tiles
it; a **fixed-size** window is not resized; a **mouse drag** to float keeps its
geometry; switching to the floating layout shrinks visible tiled windows once
and a second switch does not shrink them again; fullscreen (non-fake) clients
are skipped.

---

## Declined from this survey

Record in `UPSTREAM-SYNC.md`'s coverage table. No code.

| Upstream | Why N/A |
| --- | --- |
| `#329` `5c7140f` | Edits `scripts/dwm-desktop-update*` and its tests: upstream's git-`main` updater, declined under D-8 |
| `#330` (issue), `#336` `f0abbdb` | Fedora kickstart / Anaconda defaults (shared root and home) |
| `f02d965`, `af7cc1d` | Fedora public installers' disk selection, and Anaconda docs |
| `f31a7b9`, `222378b`, `#337`, `#339` | Cloudflare ISO download URLs in the docs; Lyona ships ISOs on GitHub releases |
| `4e05248`, `#338` | dwm-titus 0.7.1 changelog |

---

## Verification

```bash
scripts/run-tests make clean all check-shell check-format check-quickshell-qml
scripts/run-tests make check-quickshell-settings-responsiveness-xvfb check-quickshell-settings-xvfb \
  check-quickshell-appearance-model check-quickshell-update-model check-gearlever-install \
  check-xvfb-runtime check-arch-packages check-no-aur
scripts/run-tests make check
```

Manual: open Settings and visit every section for the first time on a slow
provider; no card appears, disappears or reflows inside a visible pane (S5-01).
`flatpak remote-modify --user --no-gpg-verify flathub`, then run
`scripts/install-gearlever`: it must refuse (S5-02). Toggle a tiled window to
floating with `Super+Space` (S5-03).

## Closes

Upstream `#335` (and, for Lyona, the in-pane half of `#315`), `#332`/`#334`,
and, once D-9 is decided, `#331`/`#333`. Decisions recorded for `#329`,
`#330`, `#336`, `#337`–`#339`, and every Fedora-only commit in
`d4c6d89..d155edc`.
