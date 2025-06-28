import unittest
from unittest.mock import patch, MagicMock
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from tweet_parser import process_tweet_text_for_markdown_links, _get_reply_category

class TestTweetParser(unittest.TestCase):

    def test_process_tweet_text_for_markdown_links_with_media(self):
        tweet = {
            'tweet': {
                'id_str': '12345',
                'full_text': 'Check out this photo! https://t.co/abcdefg',
                'entities': {
                    'urls': [],
                    'media': [
                        {
                            'url': 'https://t.co/abcdefg',
                            'media_url_https': 'https://pbs.twimg.com/media/some_image.jpg',
                            'type': 'photo'
                        }
                    ]
                }
            }
        }

        process_tweet_text_for_markdown_links(tweet)

        self.assertEqual(tweet['tweet']['full_text'], 'Check out this photo! [{attachment}]')
        self.assertIn('archive/data/tweets_media/12345-some_image.jpg', tweet['tweet']['media_files'][0])

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


if __name__ == '__main__':
    unittest.main()