import os
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from llm_analyzer import _normalize_title, _pick_images


class TestNormalizeTitle(unittest.TestCase):

    def test_cleans_quotes_period_and_capitalizes(self):
        self.assertEqual(
            _normalize_title('"posted a meme about cats."'),
            "Posted a meme about cats",
        )

    def test_tweeted_fallback_returns_none(self):
        self.assertIsNone(_normalize_title("Tweeted"))
        self.assertIsNone(_normalize_title("  tweeted.  "))
        self.assertIsNone(_normalize_title(""))

    def test_rambling_output_returns_none(self):
        self.assertIsNone(_normalize_title("Wrote " + "very " * 15 + "long title"))

    def test_multiline_keeps_first_line(self):
        self.assertEqual(
            _normalize_title("Shared photos from Monza\nThe tweet shows..."),
            "Shared photos from Monza",
        )


class TestPickImages(unittest.TestCase):

    def test_filters_videos_and_missing_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            jpg = os.path.join(tmp, "a.JPG")
            mp4 = os.path.join(tmp, "b.mp4")
            for p in (jpg, mp4):
                open(p, "wb").close()
            missing = os.path.join(tmp, "gone.png")
            self.assertEqual(_pick_images([mp4, jpg, missing]), [jpg])

    def test_caps_image_count(self):
        with tempfile.TemporaryDirectory() as tmp:
            paths = []
            for i in range(6):
                p = os.path.join(tmp, f"{i}.png")
                open(p, "wb").close()
                paths.append(p)
            with patch("llm_analyzer.config.LLM_MAX_IMAGES", 4):
                self.assertEqual(len(_pick_images(paths)), 4)


if __name__ == '__main__':
    unittest.main()
