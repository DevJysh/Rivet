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

 Name           Version     Size       Installed
 ────────────────────────────────────────────────────
 Krita          5.2.1       182 MB     2026-11-11 05:08 UTC
 Obsidian       1.5.8       148 MB     2026-11-10 17:42 UTC
 Neovim         0.9.5       12 MB      2026-11-09 09:00 UTC
"""


class ParseList(unittest.TestCase):
    def test_rows_are_read_in_order(self):
        self.assertEqual(
            gui.parse_list(LIST_OUTPUT),
            [
                ("Krita", "5.2.1", "182 MB", "2026-11-11 05:08 UTC"),
                ("Obsidian", "1.5.8", "148 MB", "2026-11-10 17:42 UTC"),
                ("Neovim", "0.9.5", "12 MB", "2026-11-09 09:00 UTC"),
            ],
        )

    def test_older_output_without_the_install_column_still_parses(self):
        text = " Installed AppImages (1)\n\n Name  Version  Size\n ----\n Krita  5.2.1  182 MB\n"
        self.assertEqual(gui.parse_list(text), [("Krita", "5.2.1", "182 MB", "")])

    def test_the_empty_message_gives_no_rows(self):
        self.assertEqual(gui.parse_list("no AppImages installed\n"), [])

    def test_a_row_with_only_a_name_is_skipped(self):
        text = " Name  Version  Size\n ----\n Tool  \n"
        self.assertEqual(gui.parse_list(text), [])


class Filtering(unittest.TestCase):
    ROWS = [("Krita", "5.2.1", "1 MB", ""), ("Neovim", "0.9.5", "2 MB", "")]

    def test_an_empty_query_keeps_everything(self):
        self.assertEqual(gui.filter_rows(self.ROWS, "  "), self.ROWS)

    def test_the_query_matches_names_ignoring_case(self):
        self.assertEqual(gui.filter_rows(self.ROWS, "NEO"), [self.ROWS[1]])

    def test_the_query_matches_versions(self):
        self.assertEqual(gui.filter_rows(self.ROWS, "5.2"), [self.ROWS[0]])

    def test_counts_read_naturally(self):
        self.assertEqual(gui.describe_count(0), "No apps installed")
        self.assertEqual(gui.describe_count(1), "1 app installed")
        self.assertEqual(gui.describe_count(3), "3 apps installed")


class Confirmation(unittest.TestCase):
    def test_only_a_refused_install_asks(self):
        self.assertTrue(gui.needs_confirmation(1, "X 1.0 is installed. Pass --yes to replace it."))
        self.assertFalse(gui.needs_confirmation(0, "installed X"))
        self.assertFalse(gui.needs_confirmation(1, "rivet: no such file"))

    def test_the_argument_lists_are_right(self):
        self.assertEqual(gui.install_args("/a.AppImage"), ["install", "/a.AppImage"])
        self.assertEqual(gui.install_yes_args("/a.AppImage"), ["install", "--yes", "/a.AppImage"])
        self.assertEqual(gui.uninstall_args("Krita"), ["uninstall", "Krita"])
        self.assertEqual(gui.info_args("krita"), ["info", "krita"])


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


class WindowBuilds(unittest.TestCase):
    """Builds the window against a mock tkinter. This catches names that do not
    exist in the window code, which the other tests never reach. It does not
    check how the window looks."""

    def test_the_window_is_built_and_its_loop_started(self):
        from unittest import mock

        fake_tk = mock.MagicMock()
        env = {"RIVET": RIVET, "HOME": tempfile.mkdtemp(), "XDG_DATA_HOME": tempfile.mkdtemp()}
        self.addCleanup(shutil.rmtree, env["HOME"], True)
        self.addCleanup(shutil.rmtree, env["XDG_DATA_HOME"], True)
        with mock.patch.dict(sys.modules, {"tkinter": fake_tk}), mock.patch.dict(os.environ, env):
            if not os.access(RIVET, os.X_OK):
                self.skipTest("rivet is not built")
            self.assertEqual(gui.main(), 0)
        fake_tk.Tk.return_value.mainloop.assert_called_once()


class WindowFlow(unittest.TestCase):
    """Runs the window's own callbacks against a mock tkinter. rivet is replaced
    by canned output, and the background thread runs at once, so each step is
    deterministic. This checks the logic of the window, not its appearance."""

    LIST = (" Installed AppImages (1)\n\n Name  Version  Size  Installed\n"
            " ----\n Ferret  1.0  16 KB  2026-11-11 05:08 UTC\n")

    class ImmediateThread:
        def __init__(self, target, daemon=False):
            self.target = target

        def start(self):
            self.target()

    def canned(self, rivet, args):
        self.calls.append(list(args))
        if args[0] == "list":
            return 0, self.LIST
        if args[:2] == ["install", "--yes"]:
            return 0, "updated Ferret 1.0 to Ferret 1.1"
        if args[0] == "install":
            return 1, "Ferret 1.0 is installed. Pass --yes to replace it with Ferret 1.1."
        return 0, ""

    def test_an_update_from_the_window_asks_then_replaces(self):
        from unittest import mock

        self.calls = []
        fake_tk = mock.MagicMock()
        fake_tk.StringVar.return_value.get.return_value = ""
        fake_tk.filedialog.askopenfilename.return_value = "/x/Ferret-1.1-x86_64.AppImage"
        fake_tk.messagebox.askyesno.return_value = True
        env = {"RIVET": RIVET, "HOME": tempfile.mkdtemp(), "XDG_DATA_HOME": tempfile.mkdtemp()}
        self.addCleanup(shutil.rmtree, env["HOME"], True)
        self.addCleanup(shutil.rmtree, env["XDG_DATA_HOME"], True)
        if not os.access(RIVET, os.X_OK):
            self.skipTest("rivet is not built")
        with mock.patch.dict(sys.modules, {"tkinter": fake_tk}), \
                mock.patch.dict(os.environ, env), \
                mock.patch("threading.Thread", self.ImmediateThread), \
                mock.patch.object(gui, "run_rivet", self.canned):
            self.assertEqual(gui.main(), 0)
            poll = fake_tk.Tk.return_value.after.call_args[0][1]
            # Press the Install button, as a user would.
            install = next(c for c in fake_tk.ttk.Button.call_args_list
                           if c.kwargs.get("text") == "Install AppImage…")
            install.kwargs["command"]()
            poll()

        self.assertIn(["install", "/x/Ferret-1.1-x86_64.AppImage"], self.calls)
        self.assertIn(["install", "--yes", "/x/Ferret-1.1-x86_64.AppImage"], self.calls)
        fake_tk.messagebox.askyesno.assert_called()
        said = [c.args[0] for c in fake_tk.StringVar.return_value.set.call_args_list]
        self.assertIn("updated Ferret 1.0 to Ferret 1.1", said)

    def test_the_list_fills_the_table(self):
        from unittest import mock

        self.calls = []
        fake_tk = mock.MagicMock()
        fake_tk.StringVar.return_value.get.return_value = ""
        env = {"RIVET": RIVET, "HOME": tempfile.mkdtemp(), "XDG_DATA_HOME": tempfile.mkdtemp()}
        self.addCleanup(shutil.rmtree, env["HOME"], True)
        self.addCleanup(shutil.rmtree, env["XDG_DATA_HOME"], True)
        if not os.access(RIVET, os.X_OK):
            self.skipTest("rivet is not built")
        with mock.patch.dict(sys.modules, {"tkinter": fake_tk}), \
                mock.patch.dict(os.environ, env), \
                mock.patch("threading.Thread", self.ImmediateThread), \
                mock.patch.object(gui, "run_rivet", self.canned):
            gui.main()
            poll = fake_tk.Tk.return_value.after.call_args[0][1]
            poll()
        table = fake_tk.ttk.Treeview.return_value
        values = [c.kwargs.get("values") for c in table.insert.call_args_list]
        self.assertEqual(values, [("Ferret", "1.0", "16 KB", "2026-11-11 05:08 UTC")])


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
