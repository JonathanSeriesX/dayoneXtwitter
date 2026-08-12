import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from thread_builder import adopt_orphan_self_replies, combine_threads
from thread_categorizer import get_thread_category


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


class TestCombineThreadsDepthFirst(unittest.TestCase):

    def test_forked_thread_keeps_branches_contiguous(self):
        # Shape of the blood-donation thread: a story spine with two asides.
        #   100 → 101 → 102 ─┬→ 105 → 106   (story continuation)
        #                    ├→ 103         (aside: cat photo)
        #                    └→ 104         (aside: payment)
        tweets = [
            _archive_tweet(100),
            _archive_tweet(101, parent_id=100),
            _archive_tweet(102, parent_id=101),
            _archive_tweet(103, parent_id=102),
            _archive_tweet(104, parent_id=102),
            _archive_tweet(105, parent_id=103),
            _archive_tweet(106, parent_id=105),
        ]
        threads = combine_threads(tweets)
        self.assertEqual(len(threads), 1)
        self.assertEqual(
            [t["tweet"]["id_str"] for t in threads[0]],
            # Depth-first: the whole 103-branch first (oldest child), then 104.
            ["100", "101", "102", "103", "105", "106", "104"],
        )

    def test_branches_ordered_by_id_at_each_fork(self):
        tweets = [
            _archive_tweet(200),
            _archive_tweet(202, parent_id=200),  # younger child
            _archive_tweet(201, parent_id=200),  # older child, listed second
            _archive_tweet(203, parent_id=201),
        ]
        threads = combine_threads(tweets)
        self.assertEqual(
            [t["tweet"]["id_str"] for t in threads[0]],
            ["200", "201", "203", "202"],
        )


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

    @patch("thread_builder.config")
    def test_username_fallback_without_account_id(self, mock_config):
        mock_config.CURRENT_USERNAME = "JonathanSeriesX"
        tweets = [self._reply(400, 399, self.OWN_ID, screen_name="jonathanseriesx")]
        adopted = adopt_orphan_self_replies(tweets, own_account_id=None)
        self.assertEqual(adopted, 1)


if __name__ == "__main__":
    unittest.main()
