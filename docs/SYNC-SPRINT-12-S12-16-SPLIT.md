# S12-16 plan -- split dwm-system-management, and move test IPC out of the shell

Parent: `docs/SYNC-SPRINT-12-WHOLE-REPO-REVIEW.md#s12-16-split-dwm-system-management-and-move-test-ipc-out-of-the-shell`.
Issue `#179`. Two parts from the review, in three steps:

1. A package skeleton, with no change to any logic.
2. The split itself, made by a tool whose code is below.
3. The test-only IPC.

Each step keeps `tests/test-system-management.py` (686 tests) and the Quickshell
tests green.

**Progress:** all three steps are implemented (2026-10-02). See each step for what differs from the plan.

## What exists today (surveyed 2026-10-01, `main` at `e714bb5`)

### `scripts/dwm-system-management`

- **Size:** 10,379 lines, 248 top-level functions and classes, in one file
  installed to `PREFIX/bin`.
- **The docstring (`:2-12`) is wrong.** It says "read-only", "no mutation" and
  "no transaction calls". The file has run PackageKit transactions
  (`UpdatePackages`) since Sync Phase 5, along with regional, time and account
  changes.
- **No `global` statements.** No function rebinds module state, so moving code
  between modules can't split a shared variable in two.
- **One `__file__` use (`:2650`).** It finds the sibling
  `dwm-quickshell-controlcenter` script. After the move, `__file__` points into
  the package, so this use needs a lookup that works from the package.

### How the tests reach it

- **`tests/test-system-management.py`** loads the file with `SourceFileLoader`
  as `provider`.
- **304 `mock.patch.object(provider, ...)` calls.** Most patch the standard
  library through the module (`provider.subprocess.Popen` 20 times,
  `provider.time.monotonic` 17, `provider.os.open` 12). Those change the stdlib
  module itself, so they work wherever the code lives.
- **74 of the helper's own names are patched** (`PackageKitBackend` 18 times,
  `open_journal_directory` 15, `RegionalRead` 12, ...). These are the risk. A
  patch replaces the name in one module's namespace, so after a split, a patch on
  the wrong module silently tests nothing.
- **13 bus and process fixtures** (`tests/fixtures/system-*.py`) run the file
  with `runpy.run_path(sys.argv[1])` and read about 30 names from the returned
  globals (`provider["AccountRead"]`, `provider["main"]`, ...). Ten sites, in the
  fixtures and in the test, patch a function's `__globals__` directly.
- **`tests/test-quickshell-system-management.sh`** greps the file's source text
  (`class UpdateEventMonitor:` and three more).
- **The Quickshell Xvfb tests** use stub providers. They don't load this file.

### The `settings` IPC target in `shell.qml`

- **Size:** 165 functions over 740 lines (`:605-1347`).
- **Six are used by the product:**
  - `open`, `close`, `toggle`, `refresh` and `status`, through `scripts/dwm-settings`;
  - `select`, from the command menu (`CommandMenuCatalog.js`).
- **The other 159 are for tests:** getters, and a few test drivers such as
  `updateApply`, `powerSetDpms` and `panelWidgetSet`.
- **Callers:**
  - mostly `tests/test-quickshell-settings-xvfb.sh` (233 calls);
  - `-system-management-xvfb.sh`, `-large-surfaces-xvfb.sh` and
    `test-quickshell-watcher-lifetime-xvfb.py` also call it.
- **What the handler reads:** 14 of `shell.qml`'s objects. These are
  `settingsModel`, `appearanceModel`, `systemManagementModel`, `updateModel`,
  `autostartModel`, `powerModel`, `defaultsModel`, `controlsModel`,
  `panelSettingsModel`, `networkModel`, `bluetoothModel`, `dwmState`, `clock`
  and the `Theme` singleton.

## Design

### Layout

```
scripts/dwm-system-management               the command: a 17-line launcher
scripts/lyona_system_management/
    __init__.py                             the package docstring, and the read-only facade
    shared.py ... cli.py                    one module per domain (14)
```

- **Installed:** the launcher goes to `PREFIX/bin` as now, and the package to
  `PREFIX/lib/lyona/python/lyona_system_management/`.
- **Finding the package:** the launcher uses S12-13's rule for shell libraries,
  `${lyona_lib%bin}lib/lyona`. It looks beside itself first (a checkout), then
  in `PREFIX/lib/lyona/python` (an install).
- **No runtime source changes:** `LYONA_DEV_SCRIPTS` still selects the
  checkout's scripts, and the checkout's launcher finds the checkout's package.
- **Precompiled files:** no `.pyc` is installed. As a script, the helper was
  compiled on every run anyway; byte-compiling the installed package is a
  possible later speed-up, outside this item.

### The modules

Functions and classes go by where they sat in the file: each range starts at a
named definition. A module-level constant goes to the one module that uses it,
or to `shared` when several do. Sizes are the generated files.

| Module | Range starts at | Lines | Contents |
| --- | --- | --- | --- |
| `shared` | the top, and `ServiceRead` | 294 | Constants several modules use; `SnapshotFailure`; `ServiceRead`, the D-Bus read base class; `clean_text` |
| `system_information` | `InformationState`, `HardwareRead`, `parse_screen_lock` | 738 | OS, CPU, memory, security, filesystems, root encryption, hardware, screen lock |
| `regional_settings` | `validate_timezone_name`, `RegionalRead`, `locale_process_status` | 1022 | Time zones, locales, the regional preview, NTP, `RegionalMutation`, the locale process |
| `system_services` | `RepositoryRow` | 429 | Repositories, systemd units, CUPS, firewall units |
| `user_accounts` | `AccountRecord` | 257 | AccountsService reads |
| `delegated_tools` | `trusted_delegated_executable` | 217 | Trusted delegated tools and the terminal selection |
| `operation_journal` | `JournalFrameError` | 2757 | The operation journal: frames, files, layout, locks, operations |
| `update_plans` | `Package`, `recover_journal_active` | 930 | Update rows and plans, snapshot generations, the operation stream, recovery |
| `snapshots` | `InformationSnapshotSources` | 619 | `build_snapshot` and the information, native and managed snapshots |
| `native_operations` | `NativeOperationOwner` | 515 | Native operation ownership, regional and delegated runs, `PackageKitMutation` |
| `packagekit` | `PackageKitBackend` | 1148 | `PackageKitBackend` |
| `event_monitors` | `UpdateEventMonitor` | 823 | The update, authenticated, regional, time, account and unit event monitors |
| `watch_commands` | `control_output_writer` | 523 | Output writers, the mount, service and journal watches, cancellation |
| `cli` | `ntp_sample_command` | 342 | The commands, `usage` and `main` |

**Why the names are long.** The first run used short names (`journal`,
`updates`, `regional`, ...). Comparing outputs before and after the split
caught `snapshot-core` failing with `UnboundLocalError`: `read_recovery_snapshot`
has a local called `journal`, which hid the `journal` module inside that
function. Nine short names were in use as locals (`journal` 195 times). Every
module name now appears nowhere in the code as a name, a parameter or a
definition, and the tool refuses to run if one does.

`operation_journal` stays one module. It is one domain, and its format and file
halves call each other throughout.

### Cross-module references: one rule

- **Bare names within a module**, as before.
- **`module.name` across modules:** each module imports its neighbours with
  `from . import ...` and calls, for example,
  `operation_journal.open_journal_directory(...)` at call time. Nothing does
  `from .module import name`.

So a name is always looked up in the module that defines it, and a test patches
that module: `mock.patch.object(provider.operation_journal, "open_journal_directory")`.

### No import cycles at load time

`from . import x` between modules is safe in a cycle as long as no module needs
a name from a module that is still loading. A name is needed at load time when
it appears in a base class, a decorator, a default argument, or a module-level
value.

- **Load-time uses:** every one is of `shared`, except one: `watch_commands`
  uses `packagekit.PackageKitBackend` as a default. The tool checks this and
  fails on any other.
- **`shared` imports nothing from the package,** and nothing that `packagekit`
  imports, directly or not, imports `watch_commands`.
- **Pinned by a test:** `test_every_module_imports_first` imports each module
  first in a fresh interpreter.

### The facade

`__init__.py` imports every module and copies each defined name onto the
package. So `provider.build_snapshot` and the fixtures' `provider["AccountRead"]`
keep working for reads. It then makes the package read-only: setting or
deleting a name on it raises, and the message names the module that defines
it. A test that patches the package instead of the defining module fails at
once, instead of patching a copy nobody reads.

---

## Step 1: a package with one module, no logic change

**Implemented (2026-10-02).** Where it differs from the text below:

- **The loader:** `tests/lyona_provider.py` is used by:
  - the unit test;
  - its seven inline `-c` programs (they find `tests/` beside the launcher's
    `scripts/`);
  - the mount-monitor runner;
  - 11 fixtures. `system-locale-process.py` loaded the helper with
    `SourceFileLoader`, not `runpy`. Two fixtures run another fixture, not the
    helper, and are unchanged.
- **The verifier:** it checks file by file, not with `verify_tree`, because a
  checkout's package directory can hold an untracked `__pycache__`. It backs
  up the package directory as a whole.
- **`check-dev-sync-install`:** its fake install now installs the package. A new
  case removes `core.py` and adds `retired.py`, and expects both reported.
- **The manifest check** runs the staged launcher with
  `PYTHONDONTWRITEBYTECODE=1`, so it leaves no `__pycache__` in the stage.
- **Validated:**
  - 686 unit tests pass, through `scripts/run-tests`;
  - `check-install-manifest`, `check-dev-sync-install`, `release-check`,
    `check-shell`, `check-format`, shell contracts and
    `check-quickshell-system-management` pass;
  - an install staged without a checkout beside it, run from `/`, gave the same
    `snapshot-core` record types as the checkout;
  - `sibling_command` resolves `scripts/` in a checkout and `PREFIX/bin` when
    installed.

The file moves to `scripts/lyona_system_management/core.py` with `git mv`, so its
history follows it. A launcher takes its place.

### `scripts/dwm-system-management` (new, the launcher)

```python
#!/usr/bin/python3
"""Settings' system-management helper; the code is the lyona_system_management package."""
import os
import sys

# A checkout keeps the package beside this script; an install keeps it in
# PREFIX/lib/lyona/python, beside PREFIX/bin: the rule the shell libraries
# follow (Sync Sprint 12 S12-13, S12-16).
_here = os.path.dirname(os.path.realpath(__file__))
if not os.path.isdir(os.path.join(_here, "lyona_system_management")):
    _here = os.path.join(os.path.dirname(_here), "lib", "lyona", "python")
sys.path.insert(0, _here)

from lyona_system_management.core import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
```

### `core.py` (the moved file)

```diff
-#!/usr/bin/python3
-"""Bounded, machine-readable read-only Arch update-discovery provider.
-
-Sync Phase 2 (docs/SYNC-P2-UPDATE-SNAPSHOT.md): a single `snapshot`
-subcommand over PackageKit's alpm backend. No mutation, no journal, no
-root, no polkit prompt. Sync Phase 3 added no new commands here (the
-Settings pane wraps `snapshot` directly). Sync Phase 4
-(docs/SYNC-P4-DISCOVERY-EVENTS.md) adds `watch-updates`: a bounded,
-read-only event stream over PackageKit's manager signals, still no
-transaction calls and still no root. Every later phase in
-docs/UPSTREAM-SYNC.md's system-management port builds on this file without
-rewriting it.
-"""
+"""Settings' system-management helper (step 1 of S12-16: one module).
+
+The package docstring in __init__.py describes what it does.
+"""
```

```diff
     elif kind == "screen-lock":
         label = "Automatic screen lock"
-        command = [os.path.join(os.path.dirname(os.path.realpath(__file__)),
-                               "dwm-quickshell-controlcenter"), "power-lock-snapshot"]
+        command = [sibling_command("dwm-quickshell-controlcenter"), "power-lock-snapshot"]
```

```python
def sibling_command(name: str) -> str:
    """A lyona command beside this package: scripts/ in a checkout, PREFIX/bin when installed."""
    parent = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    beside = os.path.join(parent, name)
    if os.path.exists(beside):
        return beside
    # PREFIX/lib/lyona/python -> PREFIX/bin
    return os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(parent))), "bin", name)
```

```diff
-if __name__ == "__main__":
-    raise SystemExit(main(sys.argv[1:]))
```

### `__init__.py` (new): the docstring the file should have had

```python
"""Settings' system-management helper, behind scripts/dwm-system-management.

It reads system state for Settings and System Health, as bounded,
machine-readable snapshots and event streams: updates through PackageKit,
time, locale and regional settings, accounts, printers, repositories,
services, storage, security and hardware.

It also makes changes, each one confirmed by the user in Settings:
  - package updates, as PackageKit transactions (UpdatePackages), recorded in
    an operation journal so an interrupted update can be recovered;
  - time, time zone, NTP and locale changes through systemd's D-Bus services;
  - delegated launches of trusted administration tools.

It never runs as root. Privileged changes go through the D-Bus services,
which ask polkit.
"""
```

### `Makefile`

```diff
+# The Python package behind dwm-system-management (Sync Sprint 12 S12-16):
+# installed to PREFIX/lib/lyona/python, where the command finds it.
+PYTHON_PACKAGE = lyona_system_management
+INSTALL_PYTHON = $(sort $(wildcard scripts/${PYTHON_PACKAGE}/*.py))
+PYTHON_LIB_DIR = ${LIB_DIR}/python
```

`install-system`, after the shared shell code. The directory is lyona's, so it is
replaced whole, and a module removed in a later release doesn't linger:

```diff
+	@echo "==> Installing the system-management package..."
+	rm -rf ${DESTDIR}${PYTHON_LIB_DIR}/${PYTHON_PACKAGE}
+	for f in ${INSTALL_PYTHON}; do \
+		install -Dm644 "$$f" ${DESTDIR}${PYTHON_LIB_DIR}/${PYTHON_PACKAGE}/$$(basename "$$f"); \
+	done
```

- **`uninstall`:** `rm -rf` the package directory and `-rmdir` `PYTHON_LIB_DIR`.
- **The manifest and `check-install-manifest`:** each file is listed at
  `usr/lib/lyona/python/lyona_system_management/NAME`.
- **`check-install-manifest`** also runs the staged launcher's `usage`, which
  exits 2. That proves the installed launcher finds the installed package.

### `scripts/lyona-install-verify.sh`

The verifier gets a fourth Makefile query,
`dwm-dev-print-python-sources: ; @printf "%s\n" $(INSTALL_PYTHON)`. It runs
`verify_file` on each file at
`$prefix/lib/lyona/python/lyona_system_management/<name>`, like the shell
libraries. It also reports a `.py` file in that directory that the Makefile no
longer lists as `STALE`.

### Tests

- **`tests/lyona_provider.py` (new):** one loader for the test and the
  fixtures. The fixtures stop using `runpy.run_path`, which would now return only
  the launcher's names.

  ```python
  """Load the system-management package for tests and fixtures (S12-16)."""
  import importlib
  import pathlib
  import sys


  def load(launcher):
      """The package module beside the launcher at `launcher` (a checkout's scripts/)."""
      scripts = str(pathlib.Path(launcher).resolve().parent)
      if scripts not in sys.path:
          sys.path.insert(0, scripts)
      return importlib.import_module("lyona_system_management.core")
  ```

- **`test-system-management.py`:** `provider = lyona_provider.load(PROVIDER_PATH)`.
  Every patch stays as it is, because in step 1 everything is still one module.
- **The 13 fixtures:** `provider = vars(lyona_provider.load(sys.argv[1]))`, so
  `provider["AccountRead"]` reads are unchanged.
- **`runpy` runners in the test** (the mount-monitor runner at `:3968`, and three
  `-c` programs) get the same change.
- **`test-quickshell-system-management.sh`:** `provider_root` becomes
  `scripts/lyona_system_management/core.py`.

### Validation

- `make check-system-management`, through `scripts/run-tests`: 686 tests.
- `check-quickshell-system-management`.
- `check-install-manifest`, `check-dev-sync-install` and `release-check`.
- The staged launcher runs `snapshot` against the session bus.
- `py_compile` on every module.

---

## Step 2: the split, by a tool

**Implemented (2026-10-02).**

### The tool

A one-time tool. It was run from the repository root on step 1's `core.py`. Its
output is committed, and the tool itself is kept only here:

```python
"""Split scripts/lyona_system_management/core.py into one module per domain.

Sync Sprint 12 S12-16 step 2. A one-time tool: run from the repository root,
it writes the modules and __init__.py, removes core.py, and rewrites the
tests' patches of the helper's own names to the module that defines them.
Nothing about the code's behaviour changes: statements move whole, and a
reference to a name another module now defines becomes `module.name`.
"""

import ast
import collections
import pathlib
import re
import sys

PKG = pathlib.Path("scripts/lyona_system_management")
SOURCE = PKG / "core.py"
TESTS = pathlib.Path("tests/test-system-management.py")

# Ranges of the file, in order: each starts at the definition named, and runs
# to the next. Functions and classes go to their range's module. A
# module-level constant goes to the one module that uses it, or to shared
# when several do (or when shared needs it while loading).
ANCHORS = [
    ("InformationState", "system_information"), ("validate_timezone_name", "regional_settings"),
    ("ServiceRead", "shared"), ("HardwareRead", "system_information"), ("RepositoryRow", "system_services"),
    ("RegionalRead", "regional_settings"), ("AccountRecord", "user_accounts"), ("locale_process_status", "regional_settings"),
    ("parse_screen_lock", "system_information"), ("trusted_delegated_executable", "delegated_tools"),
    ("JournalFrameError", "operation_journal"), ("Package", "update_plans"),
    ("InformationSnapshotSources", "snapshots"), ("recover_journal_active", "update_plans"),
    ("NativeOperationOwner", "native_operations"), ("PackageKitBackend", "packagekit"),
    ("UpdateEventMonitor", "event_monitors"), ("control_output_writer", "watch_commands"),
    ("ntp_sample_command", "cli"),
]
# Generic helpers that sit in a domain's range but serve every module.
OVERRIDES = {"clean_text": "shared"}
# The only load-time references allowed between modules: anything may need
# shared while loading, and watch's default backend is packagekit's class.
LOAD_TIME_ALLOWED = {("watch_commands", "packagekit")}

DOCS = {
    "shared": "Constants, the shared failure type, and the D-Bus read base class every reader builds on.",
    "system_information": "Read-only system information: OS, CPU, memory, security, filesystems, encryption, hardware, screen lock.",
    "regional_settings": "Time zones, locales, NTP and the regional preview: validation, reads, and the regional mutation client.",
    "system_services": "Package repositories, systemd units, CUPS and firewall units.",
    "user_accounts": "AccountsService reads.",
    "delegated_tools": "Trusted delegated administration tools and the terminal they open in.",
    "operation_journal": "The durable operation journal: frames, files, directory layout, locks and operations.",
    "update_plans": "Update rows and plans, snapshot generations, the operation stream, and journal recovery.",
    "snapshots": "The snapshots Settings reads: information, native, managed, and the combined build_snapshot.",
    "native_operations": "Native operation ownership, regional and delegated runs, and PackageKit mutations.",
    "packagekit": "The PackageKit backend.",
    "event_monitors": "Event monitors: updates, authenticated changes, regional settings, time, accounts and units.",
    "watch_commands": "Output writers and the watch commands: mounts, services, updates, regional settings, accounts, journal.",
    "cli": "The command line: subcommands, usage and main.",
}
ORDER = list(DOCS)

text = SOURCE.read_text()
raw_lines = text.encode().split(b"\n")  # byte lines: ast column offsets are UTF-8 bytes
tree = ast.parse(text)

# The header: the docstring and the imports, before any other statement.
body = list(tree.body)
header = []
while body and (isinstance(body[0], (ast.Import, ast.ImportFrom))
                or (isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant))):
    header.append(body.pop(0))
assert not [n for n in body if isinstance(n, (ast.Import, ast.ImportFrom))], "imports after the header"
assert not [n for n in ast.walk(tree) if isinstance(n, ast.Global)], "global statements"


def bound_names(node):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        return [node.name]
    targets = node.targets if isinstance(node, ast.Assign) else [node.target]
    return [n.id for t in targets for n in ast.walk(t) if isinstance(n, ast.Name)]


# A module name must never be an identifier in the code: a local named like a
# module would shadow `module.name` in the function that has it.
identifiers = set()
for n in ast.walk(tree):
    if isinstance(n, ast.arg):
        identifiers.add(n.arg)
    elif isinstance(n, ast.Name):
        identifiers.add(n.id)
    elif isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        identifiers.add(n.name)
    elif isinstance(n, ast.alias):
        identifiers.add((n.asname or n.name).split(".")[0])
clashes = identifiers & set(DOCS)
assert not clashes, f"module names used as identifiers: {sorted(clashes)}"

anchor_module = dict(ANCHORS)
range_of = {}
current = "shared"
for node in body:
    for name in bound_names(node):
        if name in anchor_module:
            current = anchor_module[name]
    range_of[id(node)] = current
assert set(anchor_module) <= {n for node in body for n in bound_names(node)}, "an anchor is missing"

constants = [node for node in body if isinstance(node, (ast.Assign, ast.AnnAssign))]
owner_of = {}
for node in body:
    if node not in constants:
        owner_of[id(node)] = OVERRIDES.get(getattr(node, "name", None), range_of[id(node)])
definer = {}
for node in body:
    for name in bound_names(node):
        assert name not in definer, f"{name} defined twice"
        definer[name] = node


def loads(node):
    return {n.id for n in ast.walk(node) if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load)}


node_loads = {id(node): loads(node) for node in body}
users = collections.defaultdict(list)  # constant node id -> nodes that use one of its names
for node in body:
    for name in node_loads[id(node)]:
        target = definer.get(name)
        if target is not None and target is not node and target in constants:
            users[id(target)].append(node)


def load_time_names(node):
    """Names a statement needs while its module loads."""
    evaluated = []
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        evaluated += node.decorator_list + node.args.defaults + [d for d in node.args.kw_defaults if d]
    elif isinstance(node, ast.ClassDef):
        evaluated += node.decorator_list + node.bases + node.keywords
        for item in node.body:
            if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                evaluated += item.decorator_list + item.args.defaults + [d for d in item.args.kw_defaults if d]
            elif isinstance(item, ast.AnnAssign):
                evaluated += [item.value] if item.value else []
            else:
                evaluated.append(item)
    else:
        evaluated.append(node)
    return {n.id for e in evaluated for n in ast.walk(e) if isinstance(n, ast.Name)}


for node in constants:
    owner_of[id(node)] = range_of[id(node)]
for _ in range(20):
    changed = False
    for node in constants:
        modules = {owner_of[id(user)] for user in users[id(node)]}
        if len(modules) == 1:
            wanted = modules.pop()
        elif modules:
            wanted = "shared"
        else:
            wanted = range_of[id(node)]
        # shared loads first and imports nothing, so whatever it needs while
        # loading must be in shared too.
        for user in users[id(node)]:
            if owner_of[id(user)] == "shared" and set(bound_names(node)) & load_time_names(user):
                wanted = "shared"
        if owner_of[id(node)] != wanted:
            owner_of[id(node)] = wanted
            changed = True
    if not changed:
        break
else:
    raise SystemExit("constant placement did not settle")
definer = {name: owner_of[id(node)] for name, node in definer.items()}

load_time = collections.defaultdict(set)
for node in body:
    module = owner_of[id(node)]
    for name in load_time_names(node):
        other = definer.get(name)
        if other and other != module:
            load_time[(module, other)].add(name)
bad = {pair: names for pair, names in load_time.items()
       if pair[1] != "shared" and pair not in LOAD_TIME_ALLOWED}
assert not bad, f"load-time references outside shared: {bad}"

# Rewrite cross-module references, in bytes, right to left per line.
edits = collections.defaultdict(list)  # line index -> [(start, end, replacement)]
uses = collections.defaultdict(set)    # module -> modules it references
names_used = collections.defaultdict(set)
for node in body:
    module = owner_of[id(node)]
    for n in ast.walk(node):
        if isinstance(n, ast.Name):
            names_used[module].add(n.id)
            other = definer.get(n.id)
            if other and other != module:
                assert isinstance(n.ctx, ast.Load), f"store to {n.id} at {n.lineno}"
                assert n.lineno == n.end_lineno
                edits[n.lineno - 1].append((n.col_offset, n.end_col_offset, f"{other}.{n.id}".encode()))
                uses[module].add(other)
lines = list(raw_lines)
for index, changes in edits.items():
    line = lines[index]
    for start, end, replacement in sorted(changes, reverse=True):
        line = line[:start] + replacement + line[end:]
    lines[index] = line

# Each statement's text runs from the end of the previous statement, so the
# comments and blank lines before it travel with it.
segments = collections.defaultdict(list)  # module -> [(index, node, text)]
previous_end = header[-1].end_lineno
for index, node in enumerate(body):
    segments[owner_of[id(node)]].append((index, node, b"\n".join(lines[previous_end:node.end_lineno])))
    previous_end = node.end_lineno
assert not b"".join(raw_lines[previous_end:]).strip(), "text after the last statement"


def is_block(node):
    return isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))


def module_body(parts):
    """Join a module's statements. Where two were not neighbours before, the
    blank lines are set afresh: two around a function or class, one between
    constants (PEP 8)."""
    out = []
    previous = None
    for index, node, text in parts:
        if previous is not None and previous[0] == index - 1:
            out.append(text)
        else:
            stripped = text.lstrip(b"\n")
            blank = 2 if previous is None or is_block(node) or is_block(previous[1]) else 1
            out.append(b"\n" * blank + stripped)
        previous = (index, node)
    return b"\n".join(out)


def import_lines(module):
    used = names_used[module]
    out = []
    for node in header:
        if isinstance(node, ast.Import):
            keep = [a for a in node.names if (a.asname or a.name).split(".")[0] in used]
            out += [f"import {a.name}" + (f" as {a.asname}" if a.asname else "") for a in keep]
        elif isinstance(node, ast.ImportFrom) and node.module != "__future__":
            keep = [a.name + (f" as {a.asname}" if a.asname else "") for a in node.names
                    if (a.asname or a.name) in used]
            if keep:
                out.append(f"from {node.module} import {', '.join(keep)}")
    return out


def wrap_import(modules):
    line = f"from . import {', '.join(modules)}"
    if len(line) <= 99:
        return line
    return "from . import (\n" + "".join(f"    {m},\n" for m in modules) + ")"


for module in ORDER:
    parts = [f'"""{DOCS[module]}"""', "", "from __future__ import annotations", ""]
    parts += import_lines(module)
    siblings = sorted(uses[module])
    if siblings:
        parts += ["", wrap_import(siblings)]
    content = "\n".join(parts) + "\n" + module_body(segments[module]).decode()
    content = content.rstrip("\n") + "\n"
    (PKG / f"{module}.py").write_text(content)

# __init__.py: the docstring, every module, and the read-only facade.
init = (PKG / "__init__.py").read_text()
docstring = init[:init.index('"""', 3) + 3]
names_used["__facade__"] = set().union(*names_used.values())
facade_imports = import_lines("__facade__")
defined = "".join(f"    {name!r}: {definer[name]!r},\n" for name in sorted(definer))
init_text = f'''{docstring}

# The package is a read-only facade over its modules (Sync Sprint 12 S12-16):
# every name a module defines can be read here, for the tests and the bus
# fixtures, but a name is patched only on the module that defines it, which
# is where every module looks it up. Patching the package raises.

import sys
import types

{chr(10).join(facade_imports)}

from . import {", ".join(sorted(ORDER))}

# name -> the module that defines it
_DEFINED_IN = {{
{defined}}}

for _name, _module in _DEFINED_IN.items():
    globals()[_name] = getattr(globals()[_module], _name)
del _name, _module


class _ReadOnlyFacade(types.ModuleType):
    def __setattr__(self, name, value):
        raise AttributeError(
            f"{{name}}: patch the module that defines it "
            f"(lyona_system_management.{{_DEFINED_IN.get(name, '<module>')}}), not the package")

    def __delattr__(self, name):
        self.__setattr__(name, None)


sys.modules[__name__].__class__ = _ReadOnlyFacade
'''
(PKG / "__init__.py").write_text(init_text)
SOURCE.unlink()

# The tests: a patch of one of the helper's names moves to its module.
tests = TESTS.read_text()
pattern = re.compile(r'mock\.patch\.object\((\s*)provider,(\s*)"([A-Za-z_]+)"')
moved = collections.Counter()


def retarget(match):
    name = match.group(3)
    if name not in definer:
        return match.group(0)
    moved[definer[name]] += 1
    return f'mock.patch.object({match.group(1)}provider.{definer[name]},{match.group(2)}"{name}"'


tests = pattern.sub(retarget, tests)
TESTS.write_text(tests)

print("module sizes:", {m: (PKG / f"{m}.py").read_text().count("\n") for m in ORDER})
print("patches retargeted:", dict(moved))
left = [(tests.count("\n", 0, m.start()) + 1, m.group(0).replace("\n", " "))
        for m in re.finditer(r'mock\.patch\.object\(\s*provider,[^)]{0,40}', tests)]
print("patches left on the package (fix by hand):")
for line, snippet in left:
    print(f"  {TESTS}:{line}: {snippet}")
```

### What it did

- **Wrote the modules:** 14 modules and the facade, and removed `core.py`.
- **Retargeted patches:** each `mock.patch.object(provider, "NAME")` on one of
  the helper's names now names the defining module.
- **Left nine patches for review.** Each now patches the module that looks the
  name up:
  - the three `open` patches, on `system_information`;
  - the `os` patch, on `delegated_tools`;
  - five that pick the name at run time, on `regional_settings` and
    `operation_journal`.

### Hand changes

- **`__globals__` patches.** Seven sites patched a function's `__globals__`.
  Four still patch the right namespace, because the function and the patched
  name share a module. Three didn't:
  - `main.__globals__` for `time_status_output` now uses
    `time_status_output.__globals__`;
  - the preflight program sets `package.regional_settings.regional_preflight_output`;
  - the native-watch program sets `p["watch_commands"].NATIVE_WATCH_SECONDS`.
- **The launcher** imports `main` from `cli`.
- **`tests/lyona_provider.py`** loads the package, which is the facade.
- **`test-quickshell-system-management.sh`** greps `event_monitors.py`,
  `watch_commands.py` and `cli.py`. It checks `UpdateEventMonitor`'s class
  body on its own, which is the intent of the old range.
- **`check-dev-sync-install`'s** retired-module case moves `cli.py`.
- **New `PackageLayoutTests`** (5 tests):
  - the package has exactly the 14 modules;
  - every module imports first;
  - every defined name is the same object on its module and on the facade;
  - the facade refuses a patch and names the module;
  - a patch on the defining module reaches a caller in another module.

### Validation

- **The unit tests:** 686 plus the 5 new ones, through `scripts/run-tests`.
- **Output comparison, before and after the split.** Five commands ran three
  ways: the step 1 single module, the split checkout, and the split package
  installed into a scratch prefix. The commands were `snapshot-core`,
  `snapshot-without-storage`, `snapshot`, `time-status` and
  `regional-choices timezone`.
  - Comparing record kinds and fields, the single module and the installed copy
    agreed on all five.
  - The checkout differed only in the screen-lock record. The checkout finds
    `dwm-quickshell-controlcenter` beside the package and the scratch prefix
    has none, which also shows that `sibling_command` works after the split.
- **No undefined names or unused imports** in any module. No linter is
  installed, so a `symtable`-based check did this; it catches all three
  problems it was shown when tested.
- **Install checks:** `check-install-manifest`, `check-dev-sync-install`,
  `release-check`, `check-shell` and `check-format`.

---

## Step 3: test-only IPC

**Implemented (2026-10-02).**

### The shell

- **The `settings` target in `shell.qml`** keeps its six commands: `open`,
  `close`, `toggle`, `refresh`, `select` and `status`. `shell.qml` is 714 lines
  shorter.
- **The other 159 functions** are in
  `config/quickshell/settings/SettingsTestIpc.qml`, an `IpcHandler` with
  `target: "settingsTest"`.
  - The handler sits inside a `Scope`, which takes the 12 objects it reads as
    required properties; every use reads `root.<object>`.
  - Properties declared on the `IpcHandler` itself failed: it offers its own
    properties over IPC, and logged "Type QVariant cannot be used across IPC"
    for each one. The first Settings Xvfb run showed this.
  - `dwmState` stayed behind: only `open` and `toggle` use it.
  - `Theme` comes from `qs.core`.
  - The file sits in `settings/` because `shell.qml` already imports
    `qs.settings`.
- **`shell.qml` creates it only under the test flag:**

```qml
    LazyLoader {
        active: Quickshell.env("LYONA_SHELL_TEST_IPC") === "1"

        component: SettingsTestIpc {
            settingsModel: settingsModel
            // ... the other eleven
        }
    }
```

- **The move was made by a script and checked.** Taking the `root.`
  qualification and the extra indent back out of the new file gives exactly the
  159 functions of HEAD's handler, comments included.

### Tests

- **Calls renamed:** the Xvfb tests' calls to the moved functions use
  `settingsTest`:
  - 186 in `test-quickshell-settings-xvfb.sh`, plus its two pass-through
    wrappers, which only ever carry test functions. Four of the 186 had a line
    break after `call settings`; the first Settings Xvfb run caught them;
  - 77 in `-system-management-xvfb.sh`;
  - 1 in `-large-surfaces-xvfb.sh`.
- **The flag:** those three harnesses start the shell with
  `LYONA_SHELL_TEST_IPC=1`. The watcher-lifetime test calls only `open` and
  `select`, and is unchanged.
- **Static pins:** five static tests pinned 31 of the moved signatures in
  `shell.qml`, and they now read `settings/SettingsTestIpc.qml`. Four body pins
  gained `root.`.
- **New contract in `test-shell-contracts.sh`:**
  - the `settings` handler has exactly the six functions;
  - `dwm-settings` accepts only five of them, and the command menu calls only
    `open` and `select`;
  - `shell.qml` gates `SettingsTestIpc` on the flag;
  - nothing in `scripts/`, `config/`, `install.sh` or `archiso/` sets the flag.

  It fails when a getter is put back on the `settings` target.

### Validation

- **The Xvfb tests:** `check-quickshell-settings-xvfb` passes, with a
  closed-idle sample of 0.067% CPU. So do `-system-management-xvfb`,
  `-large-surfaces-xvfb` and `-watcher-lifetime-xvfb`.
- **The real shell in Xvfb:** I copied the checkout's shell, started it with
  `quickshell --no-duplicate`, and listed its targets with
  `quickshell ipc show`.
  - Without the flag, there is no `settingsTest` target, the `settings` target
    offers exactly the six commands, and the shell used 0.000% CPU over 10 s,
    idle.
  - With `LYONA_SHELL_TEST_IPC=1`, `settingsTest` is there.
- **Lint:** `qmllint` (`scripts/quickshell-qmllint`) is clean on
  `SettingsTestIpc.qml` and `shell.qml`.
- **Static tests:** `test-shell-contracts.sh` and the five Quickshell static
  tests pass.

---

## Not in scope

- Splitting the other IPC targets' getters (`notifications`, `controls`). The
  review named `settings`, and they are small.
- Byte-compiling the installed package.
- Any change of behaviour in the helper. Step 2 moved code and qualified names,
  and nothing else.
