"""Load the system-management package for tests and fixtures (Sync Sprint 12 S12-16).

dwm-system-management is a launcher; the code is the lyona_system_management
package beside it. The test and the bus fixtures load the package from the
checkout the launcher is in, instead of running the launcher with runpy, which
would return only the launcher's own names.
"""

import importlib
import pathlib
import sys


def load(launcher):
    """The package beside the launcher at `launcher`: a read-only facade over its
    modules. Read any name from it; patch a name on the module that defines it
    (`provider.journal`, `provider.regional`, ...), which is where the code looks
    it up. Patching the package itself raises, naming that module."""
    scripts = str(pathlib.Path(launcher).resolve().parent)
    if scripts not in sys.path:
        sys.path.insert(0, scripts)
    return importlib.import_module("lyona_system_management")
