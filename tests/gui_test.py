#!/usr/bin/env python3
"""Tests for gui/rivet-gui. They do not open a window, so they run without a
display or Tk. Usage: python3 tests/gui_test.py [path/to/rivet]"""

import importlib.machinery
import importlib.util
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GUI = os.path.join(HERE, "..", "gui", "rivet-gui")
RIVET = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else None
if RIVET is None:
    RIVET = os.path.abspath(os.path.join(HERE, "..", "rivet"))

loader = importlib.machinery.SourceFileLoader("rivet_gui", GUI)
spec = importlib.util.spec_from_loader("rivet_gui", loader)
gui = importlib.util.module_from_spec(spec)
loader.exec_module(gui)

# The output of `rivet list`, as the binary prints it.
LIST_OUTPUT = """\
 Installed AppImages (3)

 Name           Version     Size
 ───────────────────────────────
 Krita          5.2.1       182 MB
 Obsidian       1.5.8       148 MB
 Neovim         0.9.5       12 MB
"""


class ParseList(unittest.TestCase):
    def test_rows_are_read_in_order(self):
        self.assertEqual(
            gui.parse_list(LIST_OUTPUT),
            [("Krita", "5.2.1", "182 MB"), ("Obsidian", "1.5.8", "148 MB"), ("Neovim", "0.9.5", "12 MB")],
        )

    def test_the_empty_message_gives_no_rows(self):
        self.assertEqual(gui.parse_list("no AppImages installed\n"), [])

    def test_a_row_with_only_a_name_is_skipped(self):
        text = " Name  Version  Size\n ----\n Tool  \n"
        self.assertEqual(gui.parse_list(text), [])


class FakeRivet(unittest.TestCase):
    """Replaces the rivet binary with a script that prints a fixed answer."""

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir)
        self.script = os.path.join(self.dir, "rivet")

    def make(self, body):
        with open(self.script, "w") as f:
            f.write("#!/bin/sh\n" + body + "\n")
        os.chmod(self.script, stat.S_IRWXU)
        return self.script


class InstallFlow(FakeRivet):
    def test_a_plain_install_needs_no_question(self):
        rivet = self.make('echo "installed Krita 5.2.1"')
        asked = []
        ok, msg = gui.install_file(rivet, "/x/Krita.AppImage", lambda q: asked.append(q) or True)
        self.assertTrue(ok)
        self.assertEqual(msg, "installed Krita 5.2.1")
        self.assertEqual(asked, [])

    def test_an_update_asks_and_then_repeats_with_yes(self):
        # Without a terminal, rivet refuses and asks for --yes.
        rivet = self.make(
            'if [ "$1" = install ] && [ "$2" = --yes ]; then echo "updated Ferret 1.0 to Ferret 1.1"; exit 0; fi\n'
            'echo "Ferret 1.0 is installed. Pass --yes to replace it with Ferret 1.1."; exit 1'
        )
        asked = []
        ok, msg = gui.install_file(rivet, "/x/Ferret-1.1.AppImage", lambda q: asked.append(q) or True)
        self.assertTrue(ok)
        self.assertEqual(msg, "updated Ferret 1.0 to Ferret 1.1")
        self.assertEqual(len(asked), 1)
        self.assertIn("Pass --yes", asked[0])

    def test_declining_the_update_changes_nothing(self):
        rivet = self.make(
            'echo "Ferret 1.0 is installed. Pass --yes to replace it with Ferret 1.1."; exit 1'
        )
        ok, msg = gui.install_file(rivet, "/x/Ferret-1.1.AppImage", lambda q: False)
        self.assertFalse(ok)
        self.assertEqual(msg, "Nothing was changed.")

    def test_other_failures_are_reported(self):
        rivet = self.make('echo "rivet: no such file: /x" >&2; exit 1')
        ok, msg = gui.install_file(rivet, "/x", lambda q: True)
        self.assertFalse(ok)
        self.assertIn("no such file", msg)


class UninstallFlow(FakeRivet):
    def test_uninstall_passes_the_name(self):
        rivet = self.make('echo "removed $2 ($1)"')
        ok, msg = gui.uninstall_app(rivet, "Krita")
        self.assertTrue(ok)
        self.assertIn("Krita", msg)


class FindRivet(unittest.TestCase):
    def test_the_environment_variable_wins(self):
        old = os.environ.get("RIVET")
        os.environ["RIVET"] = RIVET
        try:
            self.assertEqual(gui.find_rivet(), RIVET)
        finally:
            if old is None:
                del os.environ["RIVET"]
            else:
                os.environ["RIVET"] = old


class RealRivet(unittest.TestCase):
    """Runs the real rivet binary against a stand-in AppImage in a scratch home."""

    @classmethod
    def setUpClass(cls):
        if not os.access(RIVET, os.X_OK):
            raise unittest.SkipTest("rivet is not built")
        cls.tmp = tempfile.mkdtemp()
        cls.env_old = dict(os.environ)
        os.environ["HOME"] = os.path.join(cls.tmp, "home")
        os.environ["XDG_DATA_HOME"] = os.path.join(cls.tmp, "data")
        os.makedirs(os.environ["HOME"])
        fake = os.path.join(cls.tmp, "fake")
        src = os.path.join(HERE, "fake_appimage.c")
        subprocess.run(["cc", "-O2", "-o", fake, src], check=True)
        with open(fake, "r+b") as f:
            f.seek(8)
            f.write(b"AI\x02")
        cls.v1 = os.path.join(cls.tmp, "Widget-1.0-x86_64.AppImage")
        cls.v2 = os.path.join(cls.tmp, "Widget-2.0-x86_64.AppImage")
        shutil.copy(fake, cls.v1)
        shutil.copy(fake, cls.v2)

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "tmp"):
            os.environ.clear()
            os.environ.update(cls.env_old)
            shutil.rmtree(cls.tmp)

    def test_install_list_update_and_uninstall(self):
        ok, msg = gui.install_file(RIVET, self.v1, lambda q: False)
        self.assertTrue(ok, msg)
        rows, err = gui.list_apps(RIVET)
        self.assertIsNone(err)
        self.assertEqual([r[:2] for r in rows], [("Widget", "1.0")])

        asked = []
        ok, msg = gui.install_file(RIVET, self.v2, lambda q: asked.append(q) or True)
        self.assertTrue(ok, msg)
        self.assertEqual(len(asked), 1)
        rows, _ = gui.list_apps(RIVET)
        self.assertEqual([r[:2] for r in rows], [("Widget", "2.0")])

        ok, msg = gui.uninstall_app(RIVET, rows[0][0])
        self.assertTrue(ok, msg)
        rows, _ = gui.list_apps(RIVET)
        self.assertEqual(rows, [])


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]], verbosity=2)
