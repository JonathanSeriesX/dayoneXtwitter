import config
from processing_utils import (
    load_processed_tweet_ids,
    print_initial_status,
    load_and_prepare_threads,
    process_single_thread,
)

def main():
    if not print_initial_status():
        return

    threads = load_and_prepare_threads()
    processed_tweet_ids = load_processed_tweet_ids()
    print(f"Loaded {len(processed_tweet_ids)} previously processed tweet IDs.")

    for i, thread in enumerate(threads):
        if config.MAX_THREADS_TO_PROCESS is not None and i >= config.MAX_THREADS_TO_PROCESS:
            print(f"Stopping after processing {config.MAX_THREADS_TO_PROCESS} threads.")
            break
        process_single_thread(thread, processed_tweet_ids)


if __name__ == "__main__":
    main()