"""The ledger of what was already imported, so re-runs never duplicate entries.

Every successfully imported thread leaves one line in processed_tweets.txt:

  * an ordinary thread is recorded by its root tweet's ID;
  * a re-imported (extended) thread is additionally recorded as
    "<root id>+<last tweet id>" (see extension_marker), so running the same
    date range twice doesn't import the same extension over and over — while
    a *further* extension later still will be picked up.

Delete the file to import everything from scratch.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Optional, Set

from models import Thread

LEDGER_PATH = str(Path(__file__).resolve().parent / "processed_tweets.txt")


def load_processed_tweet_ids() -> Set[str]:
    """Loads the IDs and markers of everything already imported."""
    processed_ids = set()
    if os.path.exists(LEDGER_PATH):
        with open(LEDGER_PATH, "r") as f:
            for line in f:
                processed_ids.add(line.strip())
    return processed_ids


def save_processed_tweet_id(tweet_id: str):
    """Appends one ID (or extension marker) to the ledger file."""
    os.makedirs(os.path.dirname(LEDGER_PATH), exist_ok=True)
    with open(LEDGER_PATH, "a") as f:
        f.write(f"{tweet_id}\n")


def remember_processed(
    tweet_id: str, reimport_marker: Optional[str], processed_tweet_ids: Set[str]
):
    """Records a thread as processed — in the file and in the in-memory set —
    without ever writing the same ID twice."""
    for entry_id in (tweet_id, reimport_marker):
        if entry_id and entry_id not in processed_tweet_ids:
            save_processed_tweet_id(entry_id)
            processed_tweet_ids.add(entry_id)


def extension_marker(thread: Thread) -> str:
    """Identifies a thread together with its current last tweet, so a thread
    that was imported once and extended later can be told apart from the copy
    already in Day One. The '+' keeps these markers distinct from plain tweet
    IDs."""
    return f"{thread[0]['tweet']['id_str']}+{thread[-1]['tweet']['id_str']}"


def delete_ledger():
    """Forgets everything — used by debug mode, which always re-imports its
    tweets and must not leave them recorded afterwards."""
    if os.path.isfile(LEDGER_PATH):
        os.remove(LEDGER_PATH)
