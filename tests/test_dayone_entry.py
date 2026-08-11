import os
import sys
import unittest
from datetime import datetime

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from dayone_entry import _build_command


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


if __name__ == "__main__":
    unittest.main()
