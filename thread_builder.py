"""Step 3 of the pipeline: stitch the flat list of tweets into threads.

A thread is a tweet plus every reply-to-self hanging off it (see
models.Thread). Two jobs live here:

  * adopt_orphan_self_replies() first repairs replies whose parent tweet was
    deleted before the archive was exported, so they don't end up as broken
    "Replied to myself" entries;
  * combine_threads() then groups the tweets into threads, in reading order,
    splitting a thread that carries more media files than one Day One entry
    can hold.
"""

from __future__ import annotations

from collections import defaultdict
from typing import List

import config
from models import Thread, Tweet


def adopt_orphan_self_replies(tweets: List[Tweet], own_account_id=None) -> int:
    """Turns replies-to-self whose parent tweet is missing from the archive
    into plain tweets, by stripping their reply markers in place.

    Normally a reply to one's own tweet is threaded under its parent. But if
    that parent was deleted before the archive was generated, the reply would
    be published as "Replied to <myself>" with a dead conversation link.
    Publishing the leftovers as an ordinary tweet (or thread root) is better.

    Detection uses in_reply_to_user_id_str against the archive's account ID,
    which is stable across username changes; if no account ID is available,
    falls back to comparing in_reply_to_screen_name with CURRENT_USERNAME.

    Returns the number of tweets adopted.
    """
    archive_ids = {t["tweet"]["id_str"] for t in tweets}
    adopted = 0

    for tweet in tweets:
        tweet_data = tweet["tweet"]
        parent_id = tweet_data.get("in_reply_to_status_id_str")
        if not parent_id or parent_id in archive_ids:
            continue

        if own_account_id:
            is_self_reply = tweet_data.get("in_reply_to_user_id_str") == own_account_id
        else:
            reply_screen_name = tweet_data.get("in_reply_to_screen_name", "")
            is_self_reply = bool(config.CURRENT_USERNAME) and (
                reply_screen_name.lower() == config.CURRENT_USERNAME.lower()
            )

        if is_self_reply:
            for key in (
                "in_reply_to_status_id_str",
                "in_reply_to_status_id",
                "in_reply_to_user_id_str",
                "in_reply_to_user_id",
                "in_reply_to_screen_name",
            ):
                tweet_data.pop(key, None)
            adopted += 1

    return adopted


def _count_media(tweet: Tweet) -> int:
    """Counts the number of media items in a single tweet."""
    # 'extended_entities' is preferred as it includes all media, even in quote
    # tweets. Fall back to 'entities' if it's not present.
    entities = tweet["tweet"].get(
        "extended_entities", tweet["tweet"].get("entities", {})
    )
    return len(entities.get("media", []))


def combine_threads(tweets: List[Tweet], media_limit: int = 26) -> List[Thread]:
    """Groups tweets into chronological threads, splitting a thread if its
    cumulative media count exceeds media_limit.

    When a thread is split, the tweet that would have exceeded the limit
    becomes the starting tweet of the next thread segment.

    Returns the threads (see models.Thread): each one holds its tweets in
    reading order — the root first, then the replies, depth-first, so that
    when a thread forks, each branch is emitted contiguously.
    """
    # --- Step 1: map every tweet's ID to its replies found in the archive ---
    tweet_by_id = {tweet["tweet"]["id_str"]: tweet for tweet in tweets}
    children_map = defaultdict(list)
    all_child_ids = set()

    for tweet in tweets:
        parent_id = tweet["tweet"].get("in_reply_to_status_id_str")
        if parent_id and parent_id in tweet_by_id:
            # Only consider replies where the parent tweet is also in our archive
            children_map[parent_id].append(tweet)
            all_child_ids.add(tweet["tweet"]["id_str"])

    # --- Step 2: identify and sort the root tweets (oldest ID first) ---
    root_tweets = [t for t in tweets if t["tweet"]["id_str"] not in all_child_ids]
    sorted_roots = sorted(root_tweets, key=lambda t: int(t["tweet"]["id_str"]))

    # --- Step 3: build the threads, splitting on the media limit ---
    final_threads = []
    # Keep track of tweets already assigned to a thread to avoid reprocessing.
    processed_ids = set()

    for root in sorted_roots:
        # If this "root" was already processed as part of another thread that
        # got split, skip it.
        if root["tweet"]["id_str"] in processed_ids:
            continue

        # This stack holds all tweets in the conversation chain starting from
        # the root, visited depth-first so that when a thread forks, each
        # branch is emitted contiguously (the full first branch, then the
        # next) instead of interleaving branches level by level.
        # Chronologically-first branches come first. We drain the stack,
        # starting a new thread segment whenever the media limit is hit.
        super_thread_stack = [root]

        while super_thread_stack:
            # Start a new thread segment
            current_segment = []
            media_count_in_segment = 0

            # Build the segment until the stack is empty or the media limit is reached
            while super_thread_stack:
                next_tweet = super_thread_stack[-1]  # Peek at the next tweet
                media_in_next_tweet = _count_media(next_tweet)

                # SPLIT CONDITION:
                # If the segment is not empty and adding the next tweet would
                # exceed the limit. A non-empty check is vital so a tweet with
                # many media files can still start its own thread.
                if current_segment and (
                    media_count_in_segment + media_in_next_tweet > media_limit
                ):
                    # Stop building this segment. The `next_tweet` will become
                    # the start of the next segment in the next outer loop
                    # iteration.
                    break

                # If we're here, the tweet fits. Pop it from the stack and process it.
                current_tweet = super_thread_stack.pop()

                current_segment.append(current_tweet)
                processed_ids.add(current_tweet["tweet"]["id_str"])
                media_count_in_segment += _count_media(current_tweet)

                # Find its children and push them onto the stack in reverse ID
                # order, so the oldest child is popped (and emitted) first.
                children = children_map.get(current_tweet["tweet"]["id_str"], [])
                sorted_children = sorted(
                    children, key=lambda t: int(t["tweet"]["id_str"]), reverse=True
                )
                super_thread_stack.extend(sorted_children)

            # Add the completed segment to our final list of threads.
            if current_segment:
                final_threads.append(current_segment)

    return final_threads
