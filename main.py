import os
import random
from datetime import datetime

from config import CURRENT_USERNAME
from tweet_parser import (
    load_tweets,
    combine_threads,
    process_tweet_text_for_markdown_links,
    get_thread_category,
)
import config
from dayone_entry import add_post


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
        if i > 60:
            break

        has_interesting_content = False
        for tweet_in_thread in thread:
            if (
                int(tweet_in_thread["tweet"]["favorite_count"]) > 0
                or int(tweet_in_thread["tweet"]["retweet_count"]) > 0
                or tweet_in_thread["tweet"]["entities"].get("hashtags")
                or tweet_in_thread["tweet"]["media_files"]
            ):
                has_interesting_content = True
                break  # No need to check further tweets in this thread

        if has_interesting_content:
            category = get_thread_category(thread)
            if len(thread) > 1:
                header = f"--- {category} ({len(thread)} tweets) ---"
            else:
                header = f"--- {category} ---"

            print(f"\n{header}")

            for j, tweet_in_thread in enumerate(thread):
                indent = "  " if j > 0 else ""
                print(f"{indent} L {tweet_in_thread['tweet']['full_text']}")
                if int(tweet_in_thread["tweet"]["favorite_count"]) > 0:
                    print(f"{indent}   Likes: {tweet_in_thread['tweet']['favorite_count']}")
                if int(tweet_in_thread["tweet"]["retweet_count"]) > 0:
                    print(f"{indent}   Retweets: {tweet_in_thread['tweet']['retweet_count']}")
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

            # Prepare data for Day One entry
            entry_text = ""
            entry_tags = []
            entry_media_files = []
            entry_date_time = None
            entry_coordinate = None

            # Combine all tweet texts in the thread for the entry body
            for tweet_in_thread in thread:
                entry_text += tweet_in_thread['tweet']['full_text'] + "\n\n"

                # Collect hashtags
                if tweet_in_thread["tweet"]["entities"].get("hashtags"):
                    for hashtag in tweet_in_thread["tweet"]["entities"]["hashtags"]:
                        entry_tags.append(hashtag['text'])

                # Collect media files
                if tweet_in_thread["tweet"]["media_files"]:
                    for media_file in tweet_in_thread["tweet"]["media_files"]:
                        entry_media_files.append(media_file)

                # Get date/time from the first tweet in the thread
                if not entry_date_time:
                    # Assuming 'created_at' is in a format that datetime.strptime can parse
                    # Example: "Wed Oct 10 20:19:24 +0000 2018"
                    try:
                        entry_date_time = datetime.strptime(tweet_in_thread['tweet']['created_at'], "%a %b %d %H:%M:%S %z %Y")
                    except ValueError:
                        print(f"Warning: Could not parse date {tweet_in_thread['tweet']['created_at']}")
                        entry_date_time = None

                # Get coordinates from the first tweet in the thread that has them
                if not entry_coordinate and tweet_in_thread["tweet"].get("coordinates") and tweet_in_thread["tweet"]["coordinates"].get("coordinates"):
                    longitude = tweet_in_thread["tweet"]["coordinates"]["coordinates"][0]
                    latitude = tweet_in_thread["tweet"]["coordinates"]["coordinates"][1]
                    entry_coordinate = (latitude, longitude)

            # Add a title to the entry text
            title = f"{category}"
            entry_text = f"# {title}\n\n{entry_text}"

            # Add likes, retweets, and original tweet link
            first_tweet_in_thread = thread[0]['tweet']
            tweet_url = f"https://twitter.com/{CURRENT_USERNAME}/status/{first_tweet_in_thread['id_str']}"
            if int(first_tweet_in_thread["favorite_count"]) > 0:
                entry_text += f"[Likes: {first_tweet_in_thread['favorite_count']}]({tweet_url}/likes)\n"
            if int(first_tweet_in_thread["retweet_count"]) > 0:
                entry_text += f"[Retweets: {first_tweet_in_thread['retweet_count']}]({tweet_url}/retweets)\n"
            entry_text += f"[Original Tweet]({tweet_url})\n"

            # Call add_post to create the Day One entry
            add_post(
                text=entry_text,
                journal=config.JOURNAL_NAME,
                tags=list(set(entry_tags)),  # Remove duplicate tags
                date_time=entry_date_time,
                coordinate=entry_coordinate,
                attachments=entry_media_files
            )


if __name__ == "__main__":
    main()
