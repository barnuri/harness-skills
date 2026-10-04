#!/usr/bin/env python3
"""Imports python-docx, bootstrapping a skill-local venv on first use.

Author-side only — the docx export needs this dependency, the HTML path deliberately does not, and
neither reaches a document recipient. Split into its own module because the repo's Python rules
allow one public class per file.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


class DocxModuleLoader:
    """Resolves the `docx` module, creating and populating a venv if it is not importable."""

    _VENV_PATH = Path(__file__).resolve().parent.parent / ".venv"
    _PACKAGE = "python-docx"

    def load(self):
        module = self._try_import()
        if module is not None:
            return module
        self._bootstrap_venv()
        module = self._try_import()
        if module is None:
            raise ImportError(
                f"{self._PACKAGE} could not be installed automatically. Install it manually into "
                f"{self._VENV_PATH}, or run: pip install {self._PACKAGE}"
            )
        return module

    def _try_import(self):
        for path in self._site_packages():
            if str(path) not in sys.path:
                sys.path.insert(0, str(path))
        try:
            import docx
        except ImportError:
            return None
        # A stale namespace package can shadow python-docx and import without Document.
        return docx if hasattr(docx, "Document") else None

    def _site_packages(self) -> list[Path]:
        """Both venv layouts: POSIX `lib/pythonX.Y/site-packages`, Windows `Lib/site-packages`."""
        return sorted(self._VENV_PATH.glob("lib/python*/site-packages")) + sorted(
            self._VENV_PATH.glob("Lib/site-packages")
        )

    def _venv_python(self) -> Path:
        windows = self._VENV_PATH / "Scripts" / "python.exe"
        return windows if windows.is_file() else self._VENV_PATH / "bin" / "python"

    def _bootstrap_venv(self) -> None:
        print(f"bootstrapping {self._PACKAGE} into {self._VENV_PATH} …", file=sys.stderr)
        if not self._VENV_PATH.is_dir():
            subprocess.run([sys.executable, "-m", "venv", str(self._VENV_PATH)], check=True)
        # `python -m pip` rather than the pip executable: the script name differs per platform.
        # A global pip config with `user = true` makes pip refuse to install inside a venv.
        subprocess.run(
            [str(self._venv_python()), "-m", "pip", "install", "--quiet", self._PACKAGE],
            check=True,
            env={**os.environ, "PIP_USER": "0"},
        )
