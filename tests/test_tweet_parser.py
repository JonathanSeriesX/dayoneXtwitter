import unittest
from unittest.mock import patch, MagicMock
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from tweet_parser import process_tweet_text_for_markdown_links

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

if __name__ == '__main__':
    unittest.main()