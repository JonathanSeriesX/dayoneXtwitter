import os
from datetime import datetime

import config
import processing_utils
from processing_utils import (
    load_processed_tweet_ids,
    print_initial_status,
    load_and_prepare_threads,
    process_single_thread,
    load_debug_tweet_ids,
)

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
    start_date_str = config.START_DATE
    end_date_str = config.END_DATE

    try:
        start_date = datetime.strptime(start_date_str, "%d %B %Y")
        end_date = datetime.strptime(end_date_str, "%d %B %Y")
    except ValueError:
        print("Error: Invalid date format in config.py. Please use 'DD Month YYYY'.")
        return

    # Filter threads based on date range
    filtered_threads = []
    for thread in threads:
        # Assuming the first tweet in the thread determines the thread's creation date
        if thread and 'tweet' in thread[0] and 'created_at' in thread[0]['tweet']:
            thread_date = thread[0]['tweet']['created_at'].replace(tzinfo=None) # Remove timezone for comparison
            if start_date <= thread_date <= end_date:
                filtered_threads.append(thread)

    if len(threads) != len(filtered_threads):
        print(f"Filtered down to {len(filtered_threads)} threads within the specified date range.")

    for i, thread in enumerate(filtered_threads):
        if config.MAX_THREADS_TO_PROCESS is not None and i >= config.MAX_THREADS_TO_PROCESS:
            print(f"Stopping after processing {config.MAX_THREADS_TO_PROCESS} threads.")
            break
        process_single_thread(thread, processed_tweet_ids)

    if debug_tweet_ids:
        if os.path.isfile(processing_utils.STATUSES_FILE_PATH):
            os.remove(processing_utils.STATUSES_FILE_PATH)

if __name__ == "__main__":
    main()