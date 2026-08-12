import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import twitter_archive
from thread_builder import combine_threads
from twitter_archive import load_tweets


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
        self.assertEqual(twitter_archive.OWN_TWEET_IDS, {"100", "101"})

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


if __name__ == "__main__":
    unittest.main()
