#!/usr/bin/env python3
"""
test_check_orphan_nix.py

A check that cannot fail is worth nothing, so this exercises check_orphan_nix
against small fixture trees rather than trusting it. It runs on a synthetic
tree under a tempdir outside this repo, never on nixos-config's own working
tree — unlike a manual test, it cannot leave a stray file staged here.

Building fixtures outside any git repo also exercises the exact code path the
real check depends on inside a flake-check sandbox: cleanSource strips .git,
so all_nix_files() falls back to a filesystem walk there. A tempdir under
/tmp is never inside nixos-config's repo, so `git ls-files` run from it fails
the same way (not a git repository) and the same fallback fires — this test
and the production flake-check sandbox exercise identical code, not merely
similar code.
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_orphan_nix as orphan_check  # noqa: E402


def write(root: Path, relative: str, content: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def orphans_in(root: Path) -> set[str]:
    all_files = set(orphan_check.all_nix_files(root))
    reached = orphan_check.reachable(root)
    return all_files - reached - orphan_check.ALLOWED_ORPHANS


class TestCheckOrphanNix(unittest.TestCase):
    def test_fully_imported_tree_has_no_orphans(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "flake.nix", "{ x = import ./default.nix; }")
            write(root, "default.nix", "{ imports = [ ./clean.nix ]; }")
            write(root, "clean.nix", "{ }")

            self.assertEqual(orphans_in(root), set())

    def test_unimported_file_is_caught(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "flake.nix", "{ x = import ./default.nix; }")
            write(root, "default.nix", "{ imports = [ ./clean.nix ]; }")
            write(root, "clean.nix", "{ }")
            write(root, "orphan.nix", "{ }")

            self.assertEqual(orphans_in(root), {"orphan.nix"})

    def test_secrets_prefix_is_excluded_even_when_unimported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "flake.nix", "{ x = import ./default.nix; }")
            write(root, "default.nix", "{ imports = [ ./clean.nix ]; }")
            write(root, "clean.nix", "{ }")
            write(root, "secrets/wifi/example.nix", "{ }")

            self.assertEqual(orphans_in(root), set())

    def test_directory_import_resolves_to_its_default_nix(self):
        # profiles/common and modules are both imported as bare directory
        # references (`./modules`, not `./modules/default.nix`) — the real
        # tree depends on this resolving the way Nix itself resolves it.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "flake.nix", "{ x = import ./sub; }")
            write(root, "sub/default.nix", "{ imports = [ ./leaf.nix ]; }")
            write(root, "sub/leaf.nix", "{ }")

            self.assertEqual(orphans_in(root), set())

    def test_no_git_fallback_matches_the_flake_check_sandbox(self):
        # No .git anywhere under `root`, and root itself is outside this
        # repo (tempfile always allocates under a fresh prefix) — so
        # `git ls-files` run with cwd=root fails exactly as it does inside
        # the cleanSource sandbox, and all_nix_files() must still find every
        # file via its filesystem-walk fallback rather than returning [].
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write(root, "flake.nix", "{ x = import ./default.nix; }")
            write(root, "default.nix", "{ imports = [ ./clean.nix ]; }")
            write(root, "clean.nix", "{ }")
            write(root, "orphan.nix", "{ }")

            found = set(orphan_check.all_nix_files(root))
            self.assertEqual(
                found, {"flake.nix", "default.nix", "clean.nix", "orphan.nix"}
            )


if __name__ == "__main__":
    unittest.main()
