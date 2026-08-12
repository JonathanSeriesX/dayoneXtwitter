"""Step 4 of the pipeline: pick which threads to import for the date range.

A thread whose first tweet falls inside the configured range is imported as
usual. Threads that *started* before the range but were extended with new
tweets inside it are a special case: Day One can't update an existing entry,
so the whole thread has to be imported again and the older, shorter copy
deleted by hand. This module finds those threads, and formats + saves the
reminder to delete the duplicates.
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import List, Optional, Tuple

from models import ImportedEntry, Thread

REPORT_PATH = str(Path(__file__).resolve().parent / "threads_to_delete.txt")


def parse_date_range(start_date_str: str, end_date_str: str):
    """Parses the "DD Month YYYY" dates from config. Raises ValueError if malformed."""
    start_date = datetime.strptime(start_date_str, "%d %B %Y")
    end_date = datetime.strptime(end_date_str, "%d %B %Y")
    return start_date, end_date


def _thread_dates(thread: Thread) -> list:
    """Returns the naive creation dates of every tweet in a thread, in thread order."""
    dates = []
    for tweet_in_thread in thread:
        tweet_data = tweet_in_thread.get("tweet", {})
        created_at = tweet_data.get("created_at")
        if isinstance(created_at, datetime):
            dates.append(created_at.replace(tzinfo=None))
    return dates


def partition_threads_by_date(
    threads: List[Thread], start_date: datetime, end_date: datetime
) -> Tuple[List[Thread], List[Thread]]:
    """Splits threads into the ones to import normally and the ones to re-import.

    Returns a tuple of (in_range, extended):
      - in_range: threads whose first tweet was posted within the date range.
      - extended: threads that began before the range but gained at least one
        tweet inside it. Those already live in Day One as a shorter entry, so
        they get imported again in full and reported to the user.

    Threads that started after the range, or that ended before it, are dropped.
    """
    in_range = []
    extended = []

    for thread in threads:
        dates = _thread_dates(thread)
        if not dates:
            continue

        root_date = dates[0]
        if start_date <= root_date <= end_date:
            in_range.append(thread)
        elif root_date < start_date and any(
            start_date <= date <= end_date for date in dates[1:]
        ):
            extended.append(thread)

    return in_range, extended


def count_tweets_before(thread: Thread, start_date: datetime) -> int:
    """Counts the tweets of a thread posted before the range — i.e. how big the
    already-imported copy of this thread is expected to be."""
    return sum(1 for date in _thread_dates(thread) if date < start_date)


def tweet_url(tweet_id: str, username) -> str:
    """Builds a link to a tweet, falling back to the account-agnostic URL."""
    if username:
        return f"https://twitter.com/{username}/status/{tweet_id}"
    return f"https://twitter.com/i/web/status/{tweet_id}"


def format_reimport_report(
    reimported: List[ImportedEntry], start_date: datetime, username=None
) -> str:
    """Formats the list of re-imported threads into a reminder to delete the
    older duplicates."""
    line = "=" * 72
    header = (
        f"{line}\n"
        f"⚠️  ACTION REQUIRED — {len(reimported)} thread(s) were re-imported in full\n"
        f"{line}\n"
        "These threads were started before the current date range, but you added\n"
        "more tweets to them within it. Day One can't extend an existing entry, so\n"
        "each one was imported again as a complete thread — which leaves an older,\n"
        "shorter copy in your journal. Delete the older copy of each:\n"
    )

    blocks = []
    for i, entry in enumerate(reimported, start=1):
        date_str = entry.date.strftime("%d %B %Y, %H:%M")
        old_entry_str = (
            f"≈{entry.previous_tweet_count} tweets (those posted before "
            f"{start_date.strftime('%d %B %Y')})"
            if entry.previous_tweet_count
            else "the shorter, previously imported copy"
        )
        blocks.append(
            f"\n{i}. {date_str} — “{entry.title}”\n"
            f"   Journal: {entry.journal}\n"
            f"   Old entry to delete: {old_entry_str}\n"
            f"   New entry: {entry.tweet_count} tweets\n"
            f"   First tweet: {tweet_url(entry.tweet_id, username)}\n"
        )

    footer = (
        "\nBoth copies share the same entry date, so searching that date in Day One\n"
        "will show them side by side — keep the longer one.\n"
    )

    return header + "".join(blocks) + footer


def write_reimport_report(report: str):
    """Prints the delete-the-duplicates reminder and saves it for later reference."""
    print("\n" + report)
    with open(REPORT_PATH, "w") as f:
        f.write(report)
    print(f"Saved this reminder to {REPORT_PATH}")
