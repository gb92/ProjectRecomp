import contextlib
import hashlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts import import_game


class ImportGameTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.source = self.root / "source"
        self.destination = self.root / "installed"
        self.source.mkdir()

        self.xex_contents = b"supported test executable"
        (self.source / "default.xex").write_bytes(self.xex_contents)
        (self.source / "DATA").mkdir()
        (self.source / "DATA" / "asset.bin").write_bytes(b"first")
        (self.source / "$SYSTEMUPDATE").mkdir()
        (self.source / "$SYSTEMUPDATE" / "update.bin").write_bytes(b"excluded")

        supported_hash = hashlib.sha256(self.xex_contents).hexdigest()
        hash_patch = mock.patch.object(
            import_game, "SUPPORTED_XEX_SHA256", supported_hash
        )
        hash_patch.start()
        self.addCleanup(hash_patch.stop)

    def install(self, *args, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()):
            import_game.install_game(*args, **kwargs)

    def test_imports_valid_game_without_system_update(self):
        self.install(self.source, self.destination)

        self.assertEqual(
            (self.destination / "DATA" / "asset.bin").read_bytes(), b"first"
        )
        self.assertFalse((self.destination / "$SYSTEMUPDATE").exists())
        self.assertTrue(
            (self.destination / import_game.INSTALL_MARKER).is_file()
        )

    def test_existing_import_requires_force(self):
        self.install(self.source, self.destination)

        with self.assertRaises(import_game.ImportFailure):
            self.install(self.source, self.destination)

        (self.source / "DATA" / "asset.bin").write_bytes(b"second")
        self.install(self.source, self.destination, force=True)
        self.assertEqual(
            (self.destination / "DATA" / "asset.bin").read_bytes(), b"second"
        )

    def test_refuses_to_replace_unmanaged_directory(self):
        self.destination.mkdir()

        with self.assertRaises(import_game.ImportFailure):
            self.install(self.source, self.destination, force=True)

    def test_rejects_title_update(self):
        (self.source / "default.xexp").write_bytes(b"unsupported")

        with self.assertRaises(import_game.ImportFailure):
            import_game.validate_source(self.source)

    def test_rejects_overlapping_paths(self):
        with self.assertRaises(import_game.ImportFailure):
            self.install(self.source, self.source / "installed")
        with self.assertRaises(import_game.ImportFailure):
            self.install(self.source, self.source.parent)

    def test_dry_run_does_not_create_destination(self):
        self.install(self.source, self.destination, dry_run=True)

        self.assertFalse(self.destination.exists())

    @mock.patch.object(import_game.os, "name", "posix")
    def test_empty_xdg_data_home_uses_home_fallback(self):
        with (
            mock.patch.dict(
                import_game.os.environ, {"XDG_DATA_HOME": ""}, clear=True
            ),
            mock.patch.object(import_game.Path, "home", return_value=self.root),
        ):
            self.assertEqual(
                import_game.default_install_root(),
                self.root / ".local" / "share" / "projectrecomp" / "game",
            )

    @mock.patch.object(import_game.os, "name", "nt")
    def test_windows_default_uses_visible_games_directory(self):
        with mock.patch.object(
            import_game.Path, "home", return_value=self.root
        ):
            self.assertEqual(
                import_game.default_install_root(),
                self.root / "Games" / "ProjectRecomp",
            )


if __name__ == "__main__":
    unittest.main()
