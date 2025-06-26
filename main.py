import os
import random


from tweet_parser import (
    load_tweets,
    combine_threads,
    process_tweet_text_for_markdown_links,
    get_thread_category,
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

    random.shuffle(threads)

    for i, thread in enumerate(threads):
        if i > 30:
            break

        category = get_thread_category(thread)
        if len(thread) > 1:
            header = f"--- {category} ({len(thread)} tweets) ---"
        else:
            header = f"--- {category} ---"

        print(f"\n{header}")

        for j, tweet_in_thread in enumerate(thread):
            indent = "  " if j > 0 else ""
            print(f"{indent} L {tweet_in_thread['tweet']['full_text']}")
            if tweet_in_thread["tweet"]["media_files"]:
                for media_file in tweet_in_thread["tweet"]["media_files"]:
                    print(f"{indent}   Media: {media_file}")


if __name__ == "__main__":
    main()
