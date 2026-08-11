import os
import sys
import tempfile
import unittest
from datetime import datetime
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import dayone_entry
from dayone_entry import _build_command, _stage_attachments, _cleanup_staged


class TestBuildCommand(unittest.TestCase):

    def test_options_come_before_the_new_command(self):
        command = _build_command(
            text="hello world",
            journal="Tweets",
            tags=["f1", "travel"],
            date_time=datetime(2025, 6, 24, 13, 2),
            coordinate=(41.7, 44.8),
            attachments=["/tmp/a.jpg", "/tmp/b.jpg"],
        )
        self.assertEqual(command[0], "dayone")
        # `new` is the command; everything else must precede it
        self.assertEqual(command[-3:], ["--", "new", "hello world"])
        self.assertLess(command.index("--journal"), command.index("new"))
        self.assertLess(command.index("--attachments"), command.index("--"))
        # attachment paths sit between the flag and the terminator
        att = command.index("--attachments")
        self.assertEqual(command[att + 1:command.index("--")], ["/tmp/a.jpg", "/tmp/b.jpg"])
        self.assertEqual(command[command.index("--date") + 1], "2025-06-24 13:02:00")
        self.assertEqual(command[command.index("-z") + 1], "UTC")

    def test_minimal_command(self):
        command = _build_command("just text", None, None, None, None, None)
        self.assertEqual(command, ["dayone", "--", "new", "just text"])


class TestStaging(unittest.TestCase):

    def test_stage_copies_into_container_and_cleanup_removes(self):
        with tempfile.TemporaryDirectory() as src, tempfile.TemporaryDirectory() as container:
            staging = os.path.join(container, "twixodus-staging")
            a = os.path.join(src, "photo.jpg")
            b = os.path.join(src, "clip.mp4")
            for p in (a, b):
                with open(p, "wb") as f:
                    f.write(b"data")

            with patch.object(dayone_entry, "_STAGING_DIR", staging):
                staged = _stage_attachments([a, b])
                self.assertEqual(len(staged), 2)
                for p in staged:
                    self.assertTrue(p.startswith(staging))
                    self.assertTrue(os.path.exists(p))
                # same-named sources from different folders must not collide
                self.assertEqual(
                    sorted(os.path.basename(p) for p in staged),
                    ["00-photo.jpg", "01-clip.mp4"],
                )
                _cleanup_staged(staged)
                self.assertEqual(os.listdir(staging), [])

    def test_missing_source_falls_through_unstaged(self):
        with tempfile.TemporaryDirectory() as container:
            staging = os.path.join(container, "twixodus-staging")
            with patch.object(dayone_entry, "_STAGING_DIR", staging):
                staged = _stage_attachments(["/nonexistent/file.jpg"])
                self.assertEqual(staged, ["/nonexistent/file.jpg"])
                # cleanup must not touch paths outside the staging dir
                _cleanup_staged(staged)


if __name__ == "__main__":
    unittest.main()
