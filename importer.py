"""Step 5 of the pipeline: turn one thread into one Day One entry.

For each planned thread: skip it if the ledger says it was already imported,
otherwise categorize it (step 5a), compose the entry (step 5b), pick the
target journal, hand the entry to the Day One CLI (step 6), and record the
success in the ledger.
"""

from __future__ import annotations

from typing import Optional, Set

from dayone_cli import add_post
from entry_composer import (
    aggregate_thread_data,
    build_entry_content,
    generate_entry_title,
    get_target_journal,
)
from import_ledger import extension_marker, remember_processed
from models import ImportedEntry, Thread
from thread_categorizer import get_thread_category


def import_single_thread(
    thread: Thread, processed_tweet_ids: Set[str], force_reimport: bool = False
) -> Optional[ImportedEntry]:
    """Imports one thread into Day One, unless the ledger says it's done.

    With force_reimport, the thread is imported even if it was imported before —
    used for threads that grew since their last import. Returns an
    ImportedEntry describing the created entry, or None if nothing was posted.
    """
    first_tweet_in_thread = thread[0]["tweet"]
    tweet_id = first_tweet_in_thread["id_str"]

    if tweet_id in processed_tweet_ids and not force_reimport:
        print(f"Skipping already processed tweet ID: {tweet_id}")
        return None

    # A re-imported thread is tracked by "<root id>+<last tweet id>", so running the
    # same date range twice doesn't import the same extension over and over.
    reimport_marker = extension_marker(thread) if force_reimport else None
    if reimport_marker:
        if reimport_marker in processed_tweet_ids:
            print(f"Skipping thread {tweet_id}: its extension was already imported.")
            return None
        print(f"\nRe-importing thread {tweet_id}: it was extended within the date range.")

    # Step 5a: name the thread — this also strips RT prefixes from the text.
    category = get_thread_category(thread)
    print_thread_preview(thread, category)

    # Step 5b: compose the entry.
    content = aggregate_thread_data(thread)
    title = generate_entry_title(content.text, category, len(thread), content.media_files)
    entry_text = build_entry_content(content.text, first_tweet_in_thread, category, title)

    target_journal = get_target_journal(category, tweet_id)
    if target_journal is None:
        # Mark as processed even if skipped
        remember_processed(tweet_id, reimport_marker, processed_tweet_ids)
        return None

    # Step 6: hand the entry to the Day One CLI.
    if add_post(
        text=entry_text,
        journal=target_journal,
        tags=list(set(content.tags)),
        date_time=content.date,
        coordinate=content.coordinate,
        attachments=content.media_files,
    ):
        remember_processed(tweet_id, reimport_marker, processed_tweet_ids)
        return ImportedEntry(
            tweet_id=tweet_id,
            title=title,
            category=category,
            journal=target_journal,
            date=content.date,
            tweet_count=len(thread),
        )

    return None


def print_thread_preview(thread: Thread, category: str):
    """Prints the thread being imported to the console, tweet by tweet."""
    if len(thread) > 1:
        header = f"--- {category} ({len(thread)} tweets) ---"
    else:
        header = f"--- {category} ---"
    print(f"\n{header}")

    for j, tweet_in_thread in enumerate(thread):
        indent = "  " if j > 0 else ""
        print(f"{indent} L {tweet_in_thread['tweet']['full_text']}")

        likes = int(tweet_in_thread["tweet"]["favorite_count"])
        rts = int(tweet_in_thread["tweet"]["retweet_count"])

        parts = []
        if likes > 0:
            parts.append(f"Likes: {likes}⭐️")
        if rts > 0:
            parts.append(f"Retweets: {rts}🔁")

        if parts:
            print(f"{indent}   " + "   ".join(parts))

        if tweet_in_thread["tweet"]["entities"].get("hashtags"):
            for hashtag in tweet_in_thread["tweet"]["entities"]["hashtags"]:
                print(f"{indent}   Hashtag: #{hashtag['text']}")

        if tweet_in_thread["tweet"].get("coordinates") and tweet_in_thread["tweet"]["coordinates"].get("coordinates"):
            longitude = tweet_in_thread["tweet"]["coordinates"]["coordinates"][0]
            latitude = tweet_in_thread["tweet"]["coordinates"]["coordinates"][1]
            print(f"{indent}   Location: Longitude {longitude}, Latitude {latitude}")

        if tweet_in_thread["tweet"]["media_files"]:
            for media_file in tweet_in_thread["tweet"]["media_files"]:
                print(f"{indent}   Media: {media_file}")
