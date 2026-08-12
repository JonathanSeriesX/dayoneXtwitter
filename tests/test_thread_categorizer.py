import unittest
from unittest.mock import patch
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import twitter_archive
from thread_categorizer import _get_reply_category, get_thread_category


class TestReplyCategory(unittest.TestCase):

    def test_get_reply_category_order(self):
        # Mock tweet data with mentions in a specific order
        mock_tweet = {
            "tweet": {
                "full_text": "@userA @userB @userC This is a reply.",
                "in_reply_to_status_id_str": "123456789", # Added this line
                "entities": {
                    "user_mentions": [
                        {"screen_name": "userA", "name": "User A"},
                        {"screen_name": "userB", "name": "User B"},
                        {"screen_name": "userC", "name": "User C"},
                    ]
                }
            }
        }
        expected_output = "Replied to User A, User B, and User C"
        self.assertEqual(_get_reply_category(mock_tweet), expected_output)

        mock_tweet_reordered = {
            "tweet": {
                "full_text": "@userC @userA @userB This is a reply.",
                "in_reply_to_status_id_str": "123456789", # Added this line
                "entities": {
                    "user_mentions": [
                        {"screen_name": "userA", "name": "User A"},
                        {"screen_name": "userB", "name": "User B"},
                        {"screen_name": "userC", "name": "User C"},
                    ]
                }
            }
        }
        expected_output_reordered = "Replied to User C, User A, and User B"
        self.assertEqual(_get_reply_category(mock_tweet_reordered), expected_output_reordered)

        # Test with duplicate mentions, ensuring first appearance order is kept
        mock_tweet_duplicates = {
            "tweet": {
                "full_text": "@userA @userB @userA This is a reply.",
                "in_reply_to_status_id_str": "123456789", # Added this line
                "entities": {
                    "user_mentions": [
                        {"screen_name": "userA", "name": "User A"},
                        {"screen_name": "userB", "name": "User B"},
                    ]
                }
            }
        }
        expected_output_duplicates = "Replied to User A and User B"
        self.assertEqual(_get_reply_category(mock_tweet_duplicates), expected_output_duplicates)


class TestQuotedMyself(unittest.TestCase):

    @staticmethod
    def _quote_tweet(quoted_url):
        return [
            {
                "tweet": {
                    "id_str": "500",
                    "full_text": f"lol look at this {quoted_url}",
                    "favorite_count": "0",
                    "retweet_count": "0",
                    "entities": {
                        "hashtags": [],
                        "user_mentions": [],
                        "urls": [
                            {
                                "url": "https://t.co/xyz",
                                "expanded_url": quoted_url,
                                "display_url": "twitter.com/…",
                            }
                        ],
                    },
                }
            }
        ]

    def setUp(self):
        twitter_archive.OWN_TWEET_IDS.clear()
        twitter_archive.OWN_TWEET_IDS.update({"100", "200"})

    def tearDown(self):
        twitter_archive.OWN_TWEET_IDS.clear()

    def test_quote_of_own_tweet_under_old_username(self):
        # Tweet 100 is in the archive even though it was posted as @Jonathan_x64
        thread = self._quote_tweet("https://twitter.com/Jonathan_x64/status/100")
        self.assertEqual(get_thread_category(thread), "Quoted myself")

    @patch("thread_categorizer.config")
    def test_quote_of_current_username_not_in_archive(self, mock_config):
        # Own tweet deleted from the archive, but the handle matches
        mock_config.CURRENT_USERNAME = "JonathanSeriesX"
        thread = self._quote_tweet("https://twitter.com/jonathanseriesx/status/999")
        self.assertEqual(get_thread_category(thread), "Quoted myself")

    @patch("thread_categorizer.config")
    def test_quote_of_someone_else(self, mock_config):
        mock_config.CURRENT_USERNAME = "JonathanSeriesX"
        thread = self._quote_tweet("https://twitter.com/lewishamilton/status/999")
        self.assertEqual(get_thread_category(thread), "Quoted @lewishamilton")


if __name__ == '__main__':
    unittest.main()
