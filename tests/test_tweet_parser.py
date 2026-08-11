import json
import tempfile
import unittest
from unittest.mock import patch, MagicMock
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import tweet_parser
from tweet_parser import (
    process_tweet_text_for_markdown_links,
    _get_reply_category,
    get_thread_category,
    load_tweets,
    combine_threads,
    adopt_orphan_self_replies,
)

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
        self.assertIn('/data/tweets_media/12345-some_image.jpg', tweet['tweet']['media_files'][0])

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


def _archive_tweet(tweet_id, text="hello", parent_id=None):
    tweet = {
        "id_str": str(tweet_id),
        "created_at": "Wed Aug 20 09:00:00 +0000 2025",
        "full_text": text,
        "favorite_count": "0",
        "retweet_count": "0",
        "entities": {"hashtags": [], "urls": [], "user_mentions": []},
    }
    if parent_id:
        tweet["in_reply_to_status_id_str"] = str(parent_id)
    return {"tweet": tweet}


class TestLoadTweetsMultipart(unittest.TestCase):

    def test_combines_all_archive_parts(self):
        # A thread whose root lives in tweets.js and whose replies live in
        # tweets-part1.js — they must end up in one thread.
        with tempfile.TemporaryDirectory() as tmp:
            part0 = os.path.join(tmp, "tweets.js")
            part1 = os.path.join(tmp, "tweets-part1.js")
            with open(part0, "w") as f:
                f.write("window.YTD.tweets.part0 = " + json.dumps([_archive_tweet(100)]))
            with open(part1, "w") as f:
                f.write(
                    "window.YTD.tweets.part1 = "
                    + json.dumps([_archive_tweet(101, parent_id=100)])
                )

            tweets = load_tweets([part0, part1])

        self.assertEqual(len(tweets), 2)
        self.assertEqual(tweet_parser.OWN_TWEET_IDS, {"100", "101"})

        threads = combine_threads(tweets)
        self.assertEqual(len(threads), 1)
        self.assertEqual(
            [t["tweet"]["id_str"] for t in threads[0]], ["100", "101"]
        )

    def test_accepts_single_path_for_compatibility(self):
        with tempfile.TemporaryDirectory() as tmp:
            part0 = os.path.join(tmp, "tweets.js")
            with open(part0, "w") as f:
                f.write("window.YTD.tweets.part0 = " + json.dumps([_archive_tweet(100)]))
            tweets = load_tweets(part0)
        self.assertEqual(len(tweets), 1)


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
        tweet_parser.OWN_TWEET_IDS.clear()
        tweet_parser.OWN_TWEET_IDS.update({"100", "200"})

    def tearDown(self):
        tweet_parser.OWN_TWEET_IDS.clear()

    def test_quote_of_own_tweet_under_old_username(self):
        # Tweet 100 is in the archive even though it was posted as @Jonathan_x64
        thread = self._quote_tweet("https://twitter.com/Jonathan_x64/status/100")
        self.assertEqual(get_thread_category(thread), "Quoted myself")

    @patch("tweet_parser.config")
    def test_quote_of_current_username_not_in_archive(self, mock_config):
        # Own tweet deleted from the archive, but the handle matches
        mock_config.CURRENT_USERNAME = "JonathanSeriesX"
        thread = self._quote_tweet("https://twitter.com/jonathanseriesx/status/999")
        self.assertEqual(get_thread_category(thread), "Quoted myself")

    @patch("tweet_parser.config")
    def test_quote_of_someone_else(self, mock_config):
        mock_config.CURRENT_USERNAME = "JonathanSeriesX"
        thread = self._quote_tweet("https://twitter.com/lewishamilton/status/999")
        self.assertEqual(get_thread_category(thread), "Quoted @lewishamilton")


class TestAdoptOrphanSelfReplies(unittest.TestCase):

    OWN_ID = "381554576"

    @staticmethod
    def _reply(tweet_id, parent_id, reply_user_id, screen_name="JonathanSeriesX"):
        t = _archive_tweet(tweet_id, parent_id=parent_id)
        t["tweet"]["in_reply_to_user_id_str"] = reply_user_id
        t["tweet"]["in_reply_to_screen_name"] = screen_name
        return t

    def test_orphan_self_reply_becomes_plain_tweet(self):
        tweets = [self._reply(200, 199, self.OWN_ID)]  # parent 199 not in archive
        adopted = adopt_orphan_self_replies(tweets, self.OWN_ID)
        self.assertEqual(adopted, 1)
        self.assertNotIn("in_reply_to_status_id_str", tweets[0]["tweet"])
        self.assertEqual(get_thread_category([tweets[0]]), "Tweeted")

    def test_self_reply_with_parent_present_stays_threaded(self):
        tweets = [
            _archive_tweet(100),
            self._reply(101, 100, self.OWN_ID),
        ]
        adopted = adopt_orphan_self_replies(tweets, self.OWN_ID)
        self.assertEqual(adopted, 0)
        self.assertEqual(len(combine_threads(tweets)), 1)

    def test_orphan_reply_to_someone_else_stays_a_reply(self):
        tweets = [self._reply(300, 299, "42", screen_name="mik0e1")]
        adopted = adopt_orphan_self_replies(tweets, self.OWN_ID)
        self.assertEqual(adopted, 0)
        self.assertIn("in_reply_to_status_id_str", tweets[0]["tweet"])

    @patch("tweet_parser.config")
    def test_username_fallback_without_account_id(self, mock_config):
        mock_config.CURRENT_USERNAME = "JonathanSeriesX"
        tweets = [self._reply(400, 399, self.OWN_ID, screen_name="jonathanseriesx")]
        adopted = adopt_orphan_self_replies(tweets, own_account_id=None)
        self.assertEqual(adopted, 1)


if __name__ == '__main__':
    unittest.main()