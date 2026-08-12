"""The data types that flow through Twixodus.

The importer is a straight pipeline. Data changes shape a few times on its
way from the Twitter archive to Day One, and every shape is defined here:

    tweets.js files ──(1 twitter_archive)──▶  list of Tweet
    list of Tweet   ──(2 link_expansion)───▶  the same Tweets, text cleaned up
    list of Tweet   ──(3 thread_builder)───▶  list of Thread
    list of Thread  ──(4 thread_selection)─▶  list of PlannedImport
    PlannedImport   ──(5 importer)─────────▶  EntryContent ─▶ entry in Day One
    each success    ───────────────────────▶  ImportedEntry (for the report)

main() reads top to bottom in exactly this order; each numbered step lives in
the module named in the parentheses.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# The raw material: tweets exactly as Twitter's archive stores them.
# ---------------------------------------------------------------------------

# One tweet from tweets.js. Twitter wraps every tweet in an extra dict:
#
#     {"tweet": {"id_str": ..., "full_text": ..., "created_at": ..., ...}}
#
# We keep that shape untouched (it's what the archive files contain) and
# mutate it in place as the pipeline runs:
#   * twitter_archive parses "created_at" from a string into a datetime,
#   * link_expansion rewrites "full_text" and adds a "media_files" list,
#   * thread_builder strips the reply markers off orphaned self-replies,
#   * thread_categorizer strips "RT @user:" prefixes and leading @callouts.
Tweet = Dict[str, Any]

# A thread is its tweets in reading order: the root tweet first, then the
# replies, depth-first (a whole side branch before the next one starts).
# A standalone tweet is simply a thread of length one.
Thread = List[Tweet]


# ---------------------------------------------------------------------------
# The shapes the pipeline itself produces.
# ---------------------------------------------------------------------------

@dataclass
class TwitterArchive:
    """Where the unpacked Twitter archive lives on disk."""

    data_folder: str  # .../twitter-<date>-<hash>/data
    tweets_js_paths: List[str]  # tweets.js, tweets-part1.js, ... in order

    @property
    def media_folder(self) -> str:
        """The folder holding the archived photo and video files."""
        return os.path.join(self.data_folder, "tweets_media")

    @property
    def account_js_path(self) -> str:
        """The file holding the account metadata (username, account ID)."""
        return os.path.join(self.data_folder, "account.js")


@dataclass
class PlannedImport:
    """One thread that made it through selection, and how to import it."""

    thread: Thread
    # True means the thread already sits in Day One in a shorter form (it
    # gained new tweets inside the configured date range), so it is imported
    # again in full and the user is reminded to delete the old copy.
    is_reimport: bool


@dataclass
class EntryContent:
    """Everything that goes into one Day One entry."""

    text: str  # the entry body, in Markdown
    tags: List[str]  # from the tweets' hashtags
    media_files: List[str]  # absolute paths of photos/videos to attach
    date: Optional[datetime]  # when the thread's first tweet was posted
    coordinate: Optional[Tuple[float, float]]  # (latitude, longitude), if geotagged


@dataclass
class ImportedEntry:
    """A receipt for one successfully created Day One entry."""

    tweet_id: str  # ID of the thread's root tweet
    title: str
    category: str  # "Wrote a thread", "Replied to ...", etc.
    journal: str
    date: datetime
    tweet_count: int
    # Only set for re-imported threads: how many tweets the old, shorter copy
    # in Day One should have — it helps the user find and delete that copy.
    previous_tweet_count: Optional[int] = None
