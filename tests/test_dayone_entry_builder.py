import unittest
from unittest.mock import MagicMock, patch
from datetime import datetime
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from dayone_entry_builder import aggregate_thread_data, build_entry_content, generate_entry_title
from llm_analyzer import _normalize_title, _pick_images

class TestDayoneEntryBuilder(unittest.TestCase):

    def test_aggregate_thread_data(self):
        thread = [
            {
                'tweet': {
                    'id_str': '1',
                    'full_text': 'First tweet',
                    'favorite_count': '10',
                    'retweet_count': '5',
                    'created_at': datetime(2025, 6, 27, 10, 0, 0),
                    'entities': {'hashtags': []},
                    'coordinates': None
                }
            },
            {
                'tweet': {
                    'id_str': '2',
                    'full_text': 'Second tweet',
                    'favorite_count': '20',
                    'retweet_count': '15',
                    'created_at': datetime(2025, 6, 27, 10, 5, 0),
                    'entities': {'hashtags': []},
                    'coordinates': None
                }
            }
        ]

        entry_text, _, _, _, _ = aggregate_thread_data(thread)

        self.assertIn('First tweet', entry_text)
        self.assertIn('Likes: 10', entry_text)
        self.assertIn('Retweets: 5', entry_text)
        self.assertIn('Second tweet', entry_text)
        self.assertIn('Likes: 20', entry_text)
        self.assertIn('Retweets: 15', entry_text)

    def test_build_entry_content(self):
        first_tweet = {
            'id_str': '1',
            'in_reply_to_status_id_str': None
        }
        entry_text = 'Some text'
        category = 'Tweeted'
        title = 'My Tweet'

        final_text = build_entry_content(entry_text, first_tweet, category, title)

        self.assertIn('# My Tweet', final_text)
        self.assertIn('Some text', final_text)
        self.assertNotIn('Likes:', final_text)

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
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            jpg = os.path.join(tmp, "a.JPG")
            mp4 = os.path.join(tmp, "b.mp4")
            for p in (jpg, mp4):
                open(p, "wb").close()
            missing = os.path.join(tmp, "gone.png")
            self.assertEqual(_pick_images([mp4, jpg, missing]), [jpg])

    def test_caps_image_count(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            paths = []
            for i in range(6):
                p = os.path.join(tmp, f"{i}.png")
                open(p, "wb").close()
                paths.append(p)
            self.assertEqual(len(_pick_images(paths)), 4)


class TestGenerateEntryTitle(unittest.TestCase):

    @patch("dayone_entry_builder.generate_llm_title", return_value="Expressed frustration at Twitter")
    def test_thread_uses_llm_title(self, mock_llm):
        title = generate_entry_title("some rant", "Wrote a thread", 3, ["/x/a.jpg"])
        self.assertEqual(title, "Expressed frustration at Twitter")
        mock_llm.assert_called_once_with("some rant", ["/x/a.jpg"])

    @patch("dayone_entry_builder.generate_llm_title", return_value=None)
    def test_thread_falls_back_to_category(self, mock_llm):
        title = generate_entry_title("ыыы", "Wrote a thread", 2)
        self.assertEqual(title, "Wrote a thread")

    @patch("dayone_entry_builder.generate_llm_title", return_value="Posted a meme about cats")
    def test_single_tweet_titled_when_enabled(self, mock_llm):
        with patch("dayone_entry_builder.config") as mock_config:
            mock_config.PROCESS_TITLES_WITH_LLM = True
            mock_config.LLM_TITLES_FOR_SINGLE_TWEETS = True
            title = generate_entry_title("cat pic", "Tweeted", 1, ["/x/cat.jpg"])
        self.assertEqual(title, "Posted a meme about cats")

    @patch("dayone_entry_builder.generate_llm_title")
    def test_replies_never_hit_the_llm(self, mock_llm):
        title = generate_entry_title("text", "Replied to Vera", 5)
        self.assertEqual(title, "Replied to Vera")
        mock_llm.assert_not_called()

    @patch("dayone_entry_builder.generate_llm_title")
    def test_single_quote_keeps_category(self, mock_llm):
        title = generate_entry_title("text", "Quoted myself", 1)
        self.assertEqual(title, "Quoted myself")
        mock_llm.assert_not_called()


if __name__ == '__main__':
    unittest.main()