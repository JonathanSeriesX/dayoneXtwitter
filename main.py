import os

from tweet_parser import (
    load_tweets,
    combine_threads,
    process_tweet_text_for_markdown_links,
)
import config


def main():
    print(f"Using journal: '{config.JOURNAL_NAME}'")
    if not os.path.exists(config.TWEET_ARCHIVE_PATH):
        print(f"Error: The file {config.TWEET_ARCHIVE_PATH} does not exist.")
        return

    # Load tweets
    tweets = load_tweets(config.TWEET_ARCHIVE_PATH)
    print(f"Found {len(tweets)} tweets in the archive.")
    for tweet in tweets:
        process_tweet_text_for_markdown_links(tweet)
    print("Processed tweet texts for Markdown links.")
    threads = combine_threads(tweets)
    print(f"Converted it into {len(threads)} threads.")

    for i, thread in enumerate(threads):
        if i > 20:
            break
        print(f"\n--- Thread {i + 1} ({len(thread)} tweet(s)) ---")
        for i, tweet_in_thread in enumerate(thread):
            # Indent replies for readability
            indent = "  " if i > 0 else ""
            print(f"{indent} L {tweet_in_thread['tweet']['full_text']}")
            if tweet_in_thread['tweet']['media_files']:
                print(f"{indent}   Media: {tweet_in_thread['tweet']['media_files']}")


if __name__ == "__main__":
    main()