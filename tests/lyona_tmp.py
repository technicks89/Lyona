"""Where the Python tests put their workspaces.

Imported for its effect, first thing after the standard imports:

    import lyona_tmp  # noqa: F401  (workspaces under the test root)

Test workspaces go under ${DWM_TEST_TMP_ROOT:-$HOME/tmp} (AGENTS.md). Under
scripts/run-tests, TMPDIR already points at its per-run workspace and is kept; a
test run on its own (a plain `make check-...`) would otherwise fall back to /tmp.
tests/lib.sh does the same for the shell tests.
"""
import os
import tempfile

root = os.environ.get('TMPDIR') or os.environ.get('DWM_TEST_TMP_ROOT') \
    or os.path.join(os.path.expanduser('~'), 'tmp')
os.makedirs(root, exist_ok=True)
os.environ['TMPDIR'] = root  # for the shells and helpers the test starts
tempfile.tempdir = root
