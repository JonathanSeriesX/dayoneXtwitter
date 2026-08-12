"""Step 1 of the pipeline: find the Twitter archive and read every tweet.

An unpacked Twitter archive is a folder named twitter-<YYYY-MM-DD>-<hash>
sitting next to this script. The tweets live in <archive>/data/ — in a single
tweets.js, or split into tweets.js, tweets-part1.js, tweets-part2.js, ... when
the archive is large. Threads regularly span that split, so every part is
always loaded before threads are assembled.
"""

from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path
from typing import List, Optional

from models import Tweet, TwitterArchive

# IDs of every tweet in the loaded archive, i.e. the user's own tweets.
# Populated by load_tweets(). Quoting one of these is quoting yourself, no
# matter which username the account had at the time — thread_categorizer
# reads this set to say "Quoted myself".
OWN_TWEET_IDS = set()


def find_newest_archive() -> TwitterArchive:
    """Finds the newest twitter-*/data folder next to this script.

    Raises FileNotFoundError when no unpacked archive is there.
    """
    root = Path(__file__).resolve().parent
    try:
        # The folder name embeds the export date, so the lexically largest
        # folder name is the newest export.
        newest_tweets_js = max(
            root.glob("twitter-*/data/tweets.js"),
            key=lambda p: p.parent.parent.name,
        )
    except ValueError:
        raise FileNotFoundError(
            "Couldn't find twitter-*/data/tweets.js in the project folder. "
            "Unpack your Twitter archive next to main.py first."
        )

    data_folder = newest_tweets_js.parent
    parts = sorted(
        (
            p
            for p in data_folder.glob("tweets*.js")
            if p.name == "tweets.js" or re.fullmatch(r"tweets-part\d+\.js", p.name)
        ),
        key=_part_number,
    )
    return TwitterArchive(
        data_folder=str(data_folder),
        tweets_js_paths=[str(p) for p in parts],
    )


def _part_number(path: Path) -> int:
    """Sort key for archive parts: tweets.js is part 0, tweets-part<N>.js is part N."""
    m = re.fullmatch(r"tweets-part(\d+)\.js", path.name)
    return int(m.group(1)) if m else 0


def load_tweets(tweet_archive_paths) -> List[Tweet]:
    """Loads and combines tweets from one or more tweets*.js files.

    Accepts a single path or a list of paths (normally
    TwitterArchive.tweets_js_paths). Also remembers the IDs of the user's own
    tweets in OWN_TWEET_IDS (see above).
    """
    if isinstance(tweet_archive_paths, (str, Path)):
        tweet_archive_paths = [tweet_archive_paths]

    tweets = []
    for path in tweet_archive_paths:
        tweets.extend(_load_tweets_from_file(path))

    OWN_TWEET_IDS.clear()
    OWN_TWEET_IDS.update(t["tweet"]["id_str"] for t in tweets)

    return tweets


def _load_tweets_from_file(tweets_js_path) -> List[Tweet]:
    """Loads the tweets from one tweets*.js file.

    The file is JavaScript, not JSON: a `window.YTD.tweets.partN = ` prefix
    followed by a JSON array. Everything before the first '[' is cut off.
    Each tweet's "created_at" string is parsed into a naive datetime.
    """
    with open(tweets_js_path, "r", encoding="utf-8") as file:
        content = file.read()

        start_index = content.find("[")
        if start_index != -1:
            json_content = content[start_index:].strip()
            try:
                tweets = json.loads(json_content)
            except json.JSONDecodeError as e:
                print("JSON decoding failed:", e)
                print("Content preview for debugging:", json_content[:500])
                tweets = []
        else:
            print("Error: JSON data could not be located in file.")
            tweets = []

    for tweet_data in tweets:
        # Example format: "Fri Mar 21 04:40:00 +0000 2006"
        created_at_str = tweet_data["tweet"]["created_at"]
        tweet_data["tweet"]["created_at"] = datetime.strptime(
            created_at_str, "%a %b %d %H:%M:%S %z %Y"
        ).replace(tzinfo=None)

    return tweets


def load_own_account_id(archive: TwitterArchive) -> Optional[str]:
    """Reads the account ID from the archive's account.js. The ID is stable
    across username changes, unlike config.CURRENT_USERNAME. Returns None if
    unavailable."""
    account_js = Path(archive.account_js_path)
    if not account_js.exists():
        return None
    try:
        content = account_js.read_text(encoding="utf-8")
        accounts = json.loads(content[content.find("["):])
        return accounts[0]["account"]["accountId"]
    except (json.JSONDecodeError, LookupError, ValueError):
        return None
