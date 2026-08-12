import unittest
from unittest.mock import patch
from datetime import datetime
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from entry_composer import (
    aggregate_thread_data,
    build_entry_content,
    format_source_markdown,
    generate_entry_title,
)

class TestEntryComposer(unittest.TestCase):

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

        content = aggregate_thread_data(thread)

        self.assertIn('First tweet', content.text)
        self.assertIn('Likes: 10', content.text)
        self.assertIn('Retweets: 5', content.text)
        self.assertIn('Second tweet', content.text)
        self.assertIn('Likes: 20', content.text)
        self.assertIn('Retweets: 15', content.text)
        self.assertEqual(content.date, datetime(2025, 6, 27, 10, 0, 0))
        self.assertEqual(content.tags, [])
        self.assertEqual(content.media_files, [])
        self.assertIsNone(content.coordinate)

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

class TestTweetSource(unittest.TestCase):

    ANDROID = (
        '<a href="http://twitter.com/download/android" rel="nofollow">'
        "Twitter for Android</a>"
    )

    def test_format_source_markdown_builds_link(self):
        self.assertEqual(
            format_source_markdown(self.ANDROID),
            "[Twitter for Android](http://twitter.com/download/android)",
        )

    def test_format_source_markdown_plain_text_passes_through(self):
        self.assertEqual(format_source_markdown("web"), "web")

    def test_format_source_markdown_nothing_usable(self):
        self.assertIsNone(format_source_markdown(None))
        self.assertIsNone(format_source_markdown(""))
        self.assertIsNone(format_source_markdown("<span></span>"))

    def test_sent_from_added_after_last_separator(self):
        first_tweet = {"id_str": "1", "source": self.ANDROID}
        final_text = build_entry_content("Some text\n___\n", first_tweet, "Tweeted", "T")
        self.assertIn(
            "___\nSent from [Twitter for Android](http://twitter.com/download/android)",
            final_text,
        )

    def test_replies_get_no_sent_from(self):
        first_tweet = {
            "id_str": "1",
            "in_reply_to_status_id_str": "99",
            "source": self.ANDROID,
        }
        final_text = build_entry_content(
            "@vera hello\n___\n", first_tweet, "Replied to @vera", "T"
        )
        self.assertNotIn("Sent from", final_text)

    def test_sent_from_can_be_disabled(self):
        first_tweet = {"id_str": "1", "source": self.ANDROID}
        with patch("entry_composer.config.SHOW_TWEET_SOURCE", False):
            final_text = build_entry_content(
                "Some text\n___\n", first_tweet, "Tweeted", "T"
            )
        self.assertNotIn("Sent from", final_text)

    def test_missing_source_adds_nothing(self):
        first_tweet = {"id_str": "1"}
        final_text = build_entry_content("Some text\n___\n", first_tweet, "Tweeted", "T")
        self.assertNotIn("Sent from", final_text)


class TestGenerateEntryTitle(unittest.TestCase):

    @patch("entry_composer.generate_llm_title", return_value="Expressed frustration at Twitter")
    def test_thread_uses_llm_title(self, mock_llm):
        title = generate_entry_title("some rant", "Wrote a thread", 3, ["/x/a.jpg"])
        self.assertEqual(title, "Expressed frustration at Twitter")
        mock_llm.assert_called_once_with("some rant", ["/x/a.jpg"])

    @patch("entry_composer.generate_llm_title", return_value=None)
    def test_thread_falls_back_to_category(self, mock_llm):
        title = generate_entry_title("ыыы", "Wrote a thread", 2)
        self.assertEqual(title, "Wrote a thread")

    @patch("entry_composer.generate_llm_title", return_value="Posted a meme about cats")
    def test_single_tweet_titled_when_enabled(self, mock_llm):
        with patch("entry_composer.config") as mock_config:
            mock_config.PROCESS_TITLES_WITH_LLM = True
            mock_config.LLM_TITLES_FOR_SINGLE_TWEETS = True
            title = generate_entry_title("cat pic", "Tweeted", 1, ["/x/cat.jpg"])
        self.assertEqual(title, "Posted a meme about cats")

    @patch("entry_composer.generate_llm_title")
    def test_replies_never_hit_the_llm(self, mock_llm):
        title = generate_entry_title("text", "Replied to Vera", 5)
        self.assertEqual(title, "Replied to Vera")
        mock_llm.assert_not_called()

    @patch("entry_composer.generate_llm_title")
    def test_single_quote_keeps_category(self, mock_llm):
        title = generate_entry_title("text", "Quoted myself", 1)
        self.assertEqual(title, "Quoted myself")
        mock_llm.assert_not_called()


if __name__ == '__main__':
    unittest.main()
