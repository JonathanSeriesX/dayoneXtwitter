import os
import random
from pathlib import Path

import config
from tweet_parser import load_tweets, combine_threads, process_tweet_text_for_markdown_links, get_thread_category
from dayone_entry_builder import aggregate_thread_data, generate_entry_title, build_entry_content, get_target_journal
from dayone_entry import add_post


root = Path(__file__).resolve().parent
STATUSES_FILE_PATH = str(root / "processed_tweets.txt")
# find all tweets.js under twitter-*/data/, then pick the one in the folder
# with the lexically largest name (i.e. newest YYYY-MM-DD)
try:
    js = max(
        root.glob("twitter-*/data/tweets.js"),
        key=lambda p: p.parent.parent.name
    )
except ValueError:
    raise FileNotFoundError("Couldn't find twitter-*/data/tweets.js in project folder")
TWEETS_JS_PATH = str(js)
TWEET_ARCHIVE_PATH = str(js.parent)  # -> …/twitter-…/data

def load_processed_tweet_ids() -> set:
    """
    Loads tweet IDs that have already been processed from the statuses file.
    """
    processed_ids = set()
    if os.path.exists(STATUSES_FILE_PATH):
        with open(STATUSES_FILE_PATH, "r") as f:
            for line in f:
                processed_ids.add(line.strip())
    return processed_ids


def save_processed_tweet_id(tweet_id: str):
    """
    Saves a tweet ID to the statuses file, indicating it has been processed.
    """
    # Ensure the directory exists before writing the file
    os.makedirs(os.path.dirname(STATUSES_FILE_PATH), exist_ok=True)
    with open(STATUSES_FILE_PATH, "a") as f:
        f.write(f"{tweet_id}\n")


def print_initial_status():
    """Prints the initial journal names and checks for archive existence."""
    print(f"Journal for tweets: '{config.JOURNAL_NAME}'")
    if config.REPLY_JOURNAL_NAME is not None:
        print(f"Journal for replies: '{config.REPLY_JOURNAL_NAME}'")
    else:
        print("Ignoring replies")

    if not os.path.exists(TWEETS_JS_PATH):
        print(f"Error: The file {TWEETS_JS_PATH} does not exist.")
        return False
    return True


def load_debug_tweet_ids() -> list[str]:
    """
    Loads tweet IDs from the tweets_to_debug file.
    """
    if not os.path.exists("tweets_to_debug"):
        return []
    with open("tweets_to_debug", "r") as f:
        return [line.strip() for line in f if line.strip()]


def load_and_prepare_threads(tweet_ids_to_debug=None):
    """Loads tweets, expands links, combines threads, and shuffles them."""
    tweets = load_tweets(TWEETS_JS_PATH)
    print(f"Using archive folder {TWEET_ARCHIVE_PATH}")
    print(f"Found {len(tweets)} tweets in the archive.")
    for tweet in tweets:
        process_tweet_text_for_markdown_links(tweet)
    print("Expanded t.co links inside of tweets.")
    threads = combine_threads(tweets)
    print(f"Converted those tweets into {len(threads)} threads.")

    if tweet_ids_to_debug:
        threads = [
            thread for thread in threads
            if thread[0]['tweet']['id_str'] in tweet_ids_to_debug
        ]
        print(f"Found {len(threads)} threads to debug.")
    else:
        random.shuffle(threads)

    return threads


def display_thread_details(thread: list, category: str):
    """Displays details for each tweet within a thread to the console."""
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


def process_single_thread(thread: list, processed_tweet_ids: set):
    """Processes a single thread, prepares Day One entry data, and adds the post."""
    first_tweet_in_thread = thread[0]['tweet']
    tweet_id = first_tweet_in_thread['id_str']

    if tweet_id in processed_tweet_ids:
        print(f"Skipping already processed tweet ID: {tweet_id}")
        return

    category = get_thread_category(thread)
    display_thread_details(thread, category)

    entry_text, entry_tags, entry_media_files, entry_date_time, entry_coordinate = aggregate_thread_data(thread)
    
    title = generate_entry_title(entry_text, category, len(thread))
    entry_text = build_entry_content(entry_text, first_tweet_in_thread, category, title)

    target_journal = get_target_journal(category, tweet_id)
    if target_journal is None:
        save_processed_tweet_id(tweet_id) # Mark as processed even if skipped
        return

    if add_post(
        text=entry_text,
        journal=target_journal,
        tags=list(set(entry_tags)),
        date_time=entry_date_time,
        coordinate=entry_coordinate,
        attachments=entry_media_files
    ):
        save_processed_tweet_id(tweet_id)
