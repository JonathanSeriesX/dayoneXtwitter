import os
import warnings

import config
import processing_utils
from processing_utils import (
    load_processed_tweet_ids,
    print_initial_status,
    load_and_prepare_threads,
    process_single_thread,
    load_debug_tweet_ids,
    write_reimport_report,
)
from thread_selection import (
    parse_date_range,
    partition_threads_by_date,
    count_tweets_before,
    format_reimport_report,
)

warnings.filterwarnings("ignore", message=".*NotOpenSSLWarning.*") # for Python 3.9 compatibility (default on Sonoma)


def main():
    if not print_initial_status():
        return

    debug_tweet_ids = load_debug_tweet_ids()
    if debug_tweet_ids:
        print(f"Debug mode: Processing {len(debug_tweet_ids)} specific tweets.")
        threads = load_and_prepare_threads(tweet_ids_to_debug=debug_tweet_ids)
        if os.path.isfile(processing_utils.STATUSES_FILE_PATH):
            os.remove(processing_utils.STATUSES_FILE_PATH)
    else:
        threads = load_and_prepare_threads()

    processed_tweet_ids = load_processed_tweet_ids()
    print(f"Loaded {len(processed_tweet_ids)} previously processed tweet IDs.")

    # Parse start and end dates from config
    try:
        start_date, end_date = parse_date_range(config.START_DATE, config.END_DATE)
    except ValueError:
        print("Error: Invalid date format in config.py. Please use 'DD Month YYYY'.")
        return

    # Filter threads based on date range, keeping older threads that were
    # extended within it separately — those need a full re-import.
    filtered_threads, extended_threads = partition_threads_by_date(
        threads, start_date, end_date
    )
    if not config.REIMPORT_EXTENDED_THREADS:
        extended_threads = []

    if len(threads) != len(filtered_threads):
        print(
            f"Filtered down to {len(filtered_threads)} threads within the specified date range."
        )

    if extended_threads:
        print(
            f"{len(extended_threads)} older thread(s) were extended within this date "
            "range and will be re-imported in full."
        )

    # Extended threads go first so a MAX_THREADS_TO_PROCESS limit can't starve them.
    threads_to_process = [(thread, True) for thread in extended_threads] + [
        (thread, False) for thread in filtered_threads
    ]

    reimported = []
    for i, (thread, is_reimport) in enumerate(threads_to_process):
        if (
            config.MAX_THREADS_TO_PROCESS is not None
            and i >= config.MAX_THREADS_TO_PROCESS
        ):
            print(f"Stopping after processing {config.MAX_THREADS_TO_PROCESS} threads.")
            break
        entry = process_single_thread(
            thread, processed_tweet_ids, force_reimport=is_reimport
        )
        if is_reimport and entry:
            entry["previous_tweet_count"] = count_tweets_before(thread, start_date)
            reimported.append(entry)

    if reimported:
        write_reimport_report(
            format_reimport_report(reimported, start_date, config.CURRENT_USERNAME)
        )

    if debug_tweet_ids:
        if os.path.isfile(processing_utils.STATUSES_FILE_PATH):
            os.remove(processing_utils.STATUSES_FILE_PATH)


if __name__ == "__main__":
    main()
