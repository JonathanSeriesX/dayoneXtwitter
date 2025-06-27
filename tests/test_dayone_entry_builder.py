import unittest
from unittest.mock import MagicMock
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from dayone_entry_builder import aggregate_thread_data, build_entry_content

class TestDayoneEntryBuilder(unittest.TestCase):

    def test_aggregate_thread_data(self):
        thread = [
            {
                'tweet': {
                    'id_str': '1',
                    'full_text': 'First tweet',
                    'favorite_count': '10',
                    'retweet_count': '5',
                    'created_at': 'Fri Jun 27 10:00:00 +0000 2025',
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
                    'created_at': 'Fri Jun 27 10:05:00 +0000 2025',
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

if __name__ == '__main__':
    unittest.main()