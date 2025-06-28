import os

import config
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

    else:
        threads = load_and_prepare_threads()

    processed_tweet_ids = load_processed_tweet_ids()
    print(f"Loaded {len(processed_tweet_ids)} previously processed tweet IDs.")

    for i, thread in enumerate(threads):
        if config.MAX_THREADS_TO_PROCESS is not None and i >= config.MAX_THREADS_TO_PROCESS:
            print(f"Stopping after processing {config.MAX_THREADS_TO_PROCESS} threads.")
            break
        process_single_thread(thread, processed_tweet_ids)

    if debug_tweet_ids:
        if os.path.isfile(config.STATUSES_FILE_PATH):
            os.remove(config.STATUSES_FILE_PATH)

if __name__ == "__main__":
    main()