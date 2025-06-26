import os
import random
import re
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
from llm_analyzer import get_tweet_summary # For optional LLM-based title generation

def _load_processed_tweet_ids() -> set:
    """
    Loads tweet IDs that have already been processed from the statuses file.
    """
    processed_ids = set()
    if os.path.exists(config.STATUSES_FILE_PATH):
        with open(config.STATUSES_FILE_PATH, "r") as f:
            for line in f:
                processed_ids.add(line.strip())
    return processed_ids

def _save_processed_tweet_id(tweet_id: str):
    """
    Saves a tweet ID to the statuses file, indicating it has been processed.
    """
    # Ensure the directory exists before writing the file
    os.makedirs(os.path.dirname(config.STATUSES_FILE_PATH), exist_ok=True)
    with open(config.STATUSES_FILE_PATH, "a") as f:
        f.write(f"{tweet_id}\n")

def _print_initial_status():
    """Prints the initial journal names and checks for archive existence."""
    print(f"Journal for tweets: '{config.JOURNAL_NAME}'")
    if config.REPLY_JOURNAL_NAME is not None:
        print(f"Journal for replies: '{config.REPLY_JOURNAL_NAME}'")
    else:
        print(f"Ignoring replies")

    if not os.path.exists(config.TWEET_ARCHIVE_PATH):
        print(f"Error: The file {config.TWEET_ARCHIVE_PATH} does not exist.")
        return False
    return True

def _load_and_prepare_threads():
    """Loads tweets, expands links, combines threads, and shuffles them."""
    tweets = load_tweets(config.TWEET_ARCHIVE_PATH)
    print(f"Found {len(tweets)} tweets in the archive.")
    for tweet in tweets:
        process_tweet_text_for_markdown_links(tweet)
    print("Expanded t.co links inside of tweets.")
    threads = combine_threads(tweets)
    print(f"Converted those tweets into {len(threads)} threads.")
    random.shuffle(threads)
    return threads

def _display_thread_details(thread: list, category: str):
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

def _aggregate_thread_data(thread: list):
    """Aggregates text, tags, media files, date, and coordinates from a thread."""
    entry_text = ""
    entry_tags = []
    entry_media_files = []
    entry_date_time = None
    entry_coordinate = None

    for tweet_in_thread in thread:
        entry_text += tweet_in_thread['tweet']['full_text'] + "\n\n"

        if tweet_in_thread["tweet"]["entities"].get("hashtags"):
            for hashtag in tweet_in_thread["tweet"]["entities"]["hashtags"]:
                entry_tags.append(hashtag['text'])

        if tweet_in_thread["tweet"]["media_files"]:
            for media_file in tweet_in_thread["tweet"]["media_files"]:
                entry_media_files.append(media_file)

        if not entry_date_time:
            try:
                entry_date_time = datetime.strptime(tweet_in_thread['tweet']['created_at'], "%a %b %d %H:%M:%S %z %Y")
            except ValueError:
                print(f"Warning: Could not parse date {tweet_in_thread['tweet']['created_at']}")
                entry_date_time = None

        if not entry_coordinate and tweet_in_thread["tweet"].get("coordinates") and tweet_in_thread["tweet"]["coordinates"].get("coordinates"):
            longitude = tweet_in_thread["tweet"]["coordinates"]["coordinates"][0]
            latitude = tweet_in_thread["tweet"]["coordinates"]["coordinates"][1]
            entry_coordinate = (latitude, longitude)
    
    return entry_text, entry_tags, entry_media_files, entry_date_time, entry_coordinate

def _generate_entry_title(entry_text: str, category: str, thread_length: int):
    """Generates the title for the Day One entry, optionally using an LLM."""
    if config.PROCESS_TITLES_WITH_LLM and thread_length > 1:
        llm_summary = get_tweet_summary(entry_text).lower()
        if llm_summary != "Uncategorized":
            if category == "My tweet":
                title = f"A tweet about {llm_summary}"
            elif category == "My thread":
                title = f"A thread about {llm_summary}"
            else:
                title = f"{category} about {llm_summary}"
        else:
            title = f"{category}"
    else:
        title = f"{category}"
    return title

def _build_entry_content(entry_text: str, first_tweet: dict, category: str, title: str):
    """Constructs the final text content for the Day One entry."""
    entry_text = f"# {title}\n\n{entry_text}\n\n"
    tweet_url = f"https://twitter.com/{CURRENT_USERNAME}/status/{first_tweet['id_str']}"
    metrics = []
    likes = int(first_tweet["favorite_count"])
    rts = int(first_tweet["retweet_count"])

    if first_tweet.get("in_reply_to_status_id_str"):
        mentions = re.findall(r"@\w+", entry_text)
        rest = re.sub(r"(?:@\w+\s*)+", "", entry_text).strip()
        mentions_str = " ".join(mentions)
        entry_text = f"#{rest}\n\n"
        reply_to_tweet_id = first_tweet["in_reply_to_status_id_str"]
        reply_to_url = f"https://twitter.com/i/web/status/{reply_to_tweet_id}"
        entry_text += f"[In response to]({reply_to_url}) {mentions_str}\n"

    if likes > 0:
        metrics.append(f"[Likes: {likes}]({tweet_url}/likes) ⭐️")
    if rts > 0:
        metrics.append(f"[Retweets: {rts}]({tweet_url}/retweets) 🔁")

    if metrics:
        entry_text += "   ".join(metrics) + "\n"

        # Add a footer with a direct link to the tweet on twitter.com.
        entry_text += f"_______\n[Open on twitter.com]({tweet_url})\n"

    if entry_text.startswith("RT @"):
        mention, _, entry_text = entry_text[3:].partition(" ")
        username = mention.strip("@:")

    return entry_text

def _get_target_journal(category: str, tweet_id: str):
    """Determines the target journal for the Day One entry."""
    target_journal = config.JOURNAL_NAME
    if category.startswith("Replied to"):
        if config.REPLY_JOURNAL_NAME is not None:
            target_journal = config.REPLY_JOURNAL_NAME
        else:
            print(f"Skipping reply thread {tweet_id} as REPLY_JOURNAL_NAME is not set.")
            _save_processed_tweet_id(tweet_id)
            return None
    return target_journal

def _process_single_thread(thread: list, processed_tweet_ids: set):
    """Processes a single thread, prepares Day One entry data, and adds the post."""
    first_tweet_in_thread = thread[0]['tweet']
    tweet_id = first_tweet_in_thread['id_str']

    if tweet_id in processed_tweet_ids:
        print(f"Skipping already processed tweet ID: {tweet_id}")
        return

    category = get_thread_category(thread)
    _display_thread_details(thread, category)

    entry_text, entry_tags, entry_media_files, entry_date_time, entry_coordinate = _aggregate_thread_data(thread)
    
    title = _generate_entry_title(entry_text, category, len(thread))
    entry_text = _build_entry_content(entry_text, first_tweet_in_thread, category, title)

    target_journal = _get_target_journal(category, tweet_id)
    if target_journal is None:
        return

    if add_post(
        text=entry_text,
        journal=target_journal,
        tags=list(set(entry_tags)),
        date_time=entry_date_time,
        coordinate=entry_coordinate,
        attachments=entry_media_files
    ):
        _save_processed_tweet_id(tweet_id)

def main():
    if not _print_initial_status():
        return

    threads = _load_and_prepare_threads()
    processed_tweet_ids = _load_processed_tweet_ids()
    print(f"Loaded {len(processed_tweet_ids)} previously processed tweet IDs.")

    for i, thread in enumerate(threads):
        if config.MAX_THREADS_TO_PROCESS is not None and i >= config.MAX_THREADS_TO_PROCESS:
            print(f"Stopping after processing {config.MAX_THREADS_TO_PROCESS} threads.")
            break
        _process_single_thread(thread, processed_tweet_ids)


if __name__ == "__main__":
    main()
