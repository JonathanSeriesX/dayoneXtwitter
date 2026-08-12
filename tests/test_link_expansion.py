import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from link_expansion import expand_links_in_tweet


class TestLinkExpansion(unittest.TestCase):

    def test_media_link_becomes_placeholder_and_file_path(self):
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

        expand_links_in_tweet(tweet, media_folder="/archive/data/tweets_media")

        self.assertEqual(tweet['tweet']['full_text'], 'Check out this photo! [{attachment}]')
        self.assertIn('/data/tweets_media/12345-some_image.jpg', tweet['tweet']['media_files'][0])


if __name__ == "__main__":
    unittest.main()
