"""Twixodus — imports a Twitter archive into Day One, one entry per thread.

main() below IS the whole pipeline; read it top to bottom:

    Step 1  twitter_archive     find the newest archive, read every tweet
    Step 2  link_expansion      clean up each tweet's text (t.co links, media)
    Step 3  thread_builder      stitch the tweets into threads
    Step 4  thread_selection    pick the threads in the configured date range
    Step 5  importer            one thread → one Day One entry (5a categorize,
                                5b compose — both called inside importer)
    Step 6  dayone_cli          hand each entry to the Day One CLI
    Step 7  thread_selection    remind the user to delete re-imported duplicates

The shapes the data takes between the steps are all defined in models.py.
"""

import os
import random
import warnings
from typing import List, Set

import config
import import_ledger
import link_expansion
import thread_builder
import thread_selection
import twitter_archive
from importer import import_single_thread
from models import PlannedImport

warnings.filterwarnings("ignore", message=".*NotOpenSSLWarning.*")  # for Python 3.9 compatibility (default on Sonoma)


def main():
    # ---- Step 1: find the Twitter archive and read every tweet -----------
    print_configured_journals()
    try:
        archive = twitter_archive.find_newest_archive()
    except FileNotFoundError as error:
        print(f"Error: {error}")
        return
    tweets = twitter_archive.load_tweets(archive.tweets_js_paths)
    print(f"Using archive folder {archive.data_folder}")
    part_count_str = (
        f" across {len(archive.tweets_js_paths)} files"
        if len(archive.tweets_js_paths) > 1
        else ""
    )
    print(f"Found {len(tweets)} tweets in the archive{part_count_str}.")

    # ---- Step 2: clean up each tweet's text ------------------------------
    adopted = thread_builder.adopt_orphan_self_replies(
        tweets, twitter_archive.load_own_account_id(archive)
    )
    if adopted:
        print(
            f"Adopted {adopted} self-repl(ies) whose parent tweet is gone from the "
            "archive; they will be published as ordinary tweets."
        )
    for tweet in tweets:
        link_expansion.expand_links_in_tweet(tweet, archive.media_folder)
    print("Expanded t.co links inside of tweets.")

    # ---- Step 3: stitch the tweets into threads --------------------------
    threads = thread_builder.combine_threads(tweets)
    print(f"Converted those tweets into {len(threads)} threads.")

    # ---- Step 4: pick which threads to import, and in what order ---------
    debug_tweet_ids = load_debug_tweet_ids()
    if debug_tweet_ids:
        # Debug mode: import only the listed threads, ignoring the ledger.
        print(f"Debug mode: Processing {len(debug_tweet_ids)} specific tweets.")
        threads = [
            thread for thread in threads
            if thread[0]["tweet"]["id_str"] in debug_tweet_ids
        ]
        print(f"Found {len(threads)} threads to debug.")
        import_ledger.delete_ledger()
    elif config.SHUFFLE_MODE:
        random.shuffle(threads)

    processed_tweet_ids = import_ledger.load_processed_tweet_ids()
    print(f"Loaded {len(processed_tweet_ids)} previously processed tweet IDs.")

    try:
        start_date, end_date = thread_selection.parse_date_range(
            config.START_DATE, config.END_DATE
        )
    except ValueError:
        print("Error: Invalid date format in config.py. Please use 'DD Month YYYY'.")
        return

    # Threads that started inside the range are imported normally; older
    # threads that were extended within it need a full re-import.
    in_range, extended = thread_selection.partition_threads_by_date(
        threads, start_date, end_date
    )
    if len(threads) != len(in_range):
        print(
            f"Filtered down to {len(in_range)} threads within the specified date range."
        )
    if extended:
        print(
            f"{len(extended)} older thread(s) were extended within this date "
            "range and will be re-imported in full."
        )

    # Re-imports go first so a MAX_THREADS_TO_PROCESS limit can't starve them.
    plan = [PlannedImport(thread, is_reimport=True) for thread in extended] + [
        PlannedImport(thread, is_reimport=False) for thread in in_range
    ]

    # ---- Steps 5 & 6: import the planned threads, one entry each ---------
    total_pending = count_pending_imports(plan, processed_tweet_ids)
    reimported = []
    imported_count = 0
    for i, planned in enumerate(plan):
        if (
            config.MAX_THREADS_TO_PROCESS is not None
            and i >= config.MAX_THREADS_TO_PROCESS
        ):
            print(f"Stopping after processing {config.MAX_THREADS_TO_PROCESS} threads.")
            break

        entry = import_single_thread(
            planned.thread, processed_tweet_ids, force_reimport=planned.is_reimport
        )
        if entry:
            imported_count += 1
            print(f"Progress: {imported_count}/{total_pending}")
        if planned.is_reimport and entry:
            entry.previous_tweet_count = thread_selection.count_tweets_before(
                planned.thread, start_date
            )
            reimported.append(entry)

    # ---- Step 7: remind the user to delete re-imported duplicates --------
    if reimported:
        thread_selection.write_reimport_report(
            thread_selection.format_reimport_report(
                reimported, start_date, config.CURRENT_USERNAME
            )
        )

    if debug_tweet_ids:
        # Debug runs must not leave their tweets recorded as processed.
        import_ledger.delete_ledger()


def print_configured_journals():
    """Prints which journals the entries will go to."""
    print(f"Journal for tweets: '{config.JOURNAL_NAME}'")
    if config.REPLY_JOURNAL_NAME is not None:
        print(f"Journal for replies: '{config.REPLY_JOURNAL_NAME}'")
    else:
        print("Ignoring replies")


def load_debug_tweet_ids() -> List[str]:
    """Loads root tweet IDs from the optional tweets_to_debug file. When that
    file exists, the run imports only those threads (see Step 4)."""
    if not os.path.exists("tweets_to_debug"):
        return []
    with open("tweets_to_debug", "r") as f:
        return [line.strip() for line in f if line.strip()]


def count_pending_imports(plan: List[PlannedImport], processed_tweet_ids: Set[str]) -> int:
    """How many planned threads this run still has to import: a re-imported
    thread is pending until its extension marker is in the ledger, an ordinary
    one until its root tweet ID is."""
    pending = 0
    for planned in plan:
        if planned.is_reimport:
            ledger_key = import_ledger.extension_marker(planned.thread)
        else:
            ledger_key = planned.thread[0]["tweet"]["id_str"]
        if ledger_key not in processed_tweet_ids:
            pending += 1
    return pending


if __name__ == "__main__":
    main()
