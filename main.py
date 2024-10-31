import json
import os
import subprocess
from collections import defaultdict
from datetime import datetime

# Paths to files and Day One CLI
script_dir = os.path.dirname(os.path.abspath(__file__))
TWEET_ARCHIVE_PATH = os.path.join(script_dir, "archive", "data", "tweets.js")
DAYONE_PATH = "/usr/local/bin/dayone2"

# Journals
REPLY_JOURNAL = "Twitter Replies"
TWEET_JOURNAL = "Tweets"


def load_tweets(tweet_archive_path):
    """Loads tweets from the Twitter archive JSON."""
    with open(tweet_archive_path, "r", encoding="utf-8") as file:
        content = file.read()

        # Locate the first occurrence of '[' and slice content from that point
        start_index = content.find("[")
        if start_index != -1:
            json_content = content[
                start_index:
            ].strip()  # Removes whitespace after slicing
            try:
                tweets = json.loads(json_content)
            except json.JSONDecodeError as e:
                print("JSON decoding failed:", e)
                print(
                    "Content preview for debugging:", json_content[:500]
                )  # Print up to 500 chars
                tweets = []
        else:
            print("Error: JSON data could not be located in file.")
            tweets = []

    return tweets


def create_dayone_entry(tweet, journal_name):
    """Formats and adds a tweet as a Day One entry in the specified journal."""
    # Extract relevant tweet data
    tweet_content = tweet["tweet"].get("full_text", "")
    timestamp = tweet["tweet"].get("created_at", "")
    tweet_date = datetime.strptime(timestamp, "%a %b %d %H:%M:%S %z %Y")

    # Day One entry command
    dayone_cmd = [
        DAYONE_PATH,
        "new",
        "--date",
        tweet_date.isoformat(),
        "--entry",
        tweet_content,
        "--journal",
        journal_name,
    ]

    try:
        # Run the command to create a new entry
        # subprocess.run(dayone_cmd, check=True)
        # print(f"Added tweet from {tweet_date} to {journal_name} journal")
        print(tweet_content)
    except subprocess.CalledProcessError as e:
        print(f"Error adding tweet from {tweet_date}: {e}")


def create_dayone_entry_for_thread(thread, journal_name):
    """Combines tweets in a thread and creates a Day One entry."""
    combined_text = "\n\n".join(
        f"{tweet['tweet']['full_text']} - {tweet['tweet']['created_at']}"
        for tweet in thread
    )

    # Use the date of the first tweet in the thread for Day One entry
    first_tweet_date = datetime.strptime(
        thread[0]["tweet"]["created_at"], "%a %b %d %H:%M:%S %z %Y"
    )

    dayone_cmd = [
        DAYONE_PATH,
        "new",
        "--date",
        first_tweet_date.isoformat(),
        "--entry",
        combined_text,
        "--journal",
        journal_name,
    ]

    try:
        # subprocess.run(dayone_cmd, check=True)
        # print(f"Added thread starting from {first_tweet_date} to {journal_name} journal")
        print(combined_text + "\n" + "_______" + "\n")
    except subprocess.CalledProcessError as e:
        print(f"Error adding thread from {first_tweet_date}: {e}")


def combine_threads(tweets):
    """Groups tweets into threads by following reply chains."""
    # Dictionary to quickly access tweets by their id
    tweet_by_id = {tweet["tweet"]["id"]: tweet for tweet in tweets}

    # Dictionary to store threads, where each thread is a list of tweets
    threads = defaultdict(list)
    processed_tweets = set()

    for tweet in tweets:
        tweet_id = tweet["tweet"]["id"]

        # Skip if already processed as part of another thread
        if tweet_id in processed_tweets:
            continue

        # Initialize a new thread
        current_thread = []
        current_tweet = tweet

        # Follow the reply chain backward to find the start of the thread
        while current_tweet:
            current_thread.append(current_tweet)
            processed_tweets.add(current_tweet["tweet"]["id"])

            # Move to the previous tweet in the reply chain
            in_reply_to_id = current_tweet["tweet"].get("in_reply_to_status_id")
            current_tweet = tweet_by_id.get(in_reply_to_id) if in_reply_to_id else None

        # Reverse the thread to have tweets in chronological order
        current_thread.reverse()

        # Use the first tweet’s ID as the key for this thread
        threads[current_thread[0]["tweet"]["id"]] = current_thread

    return threads


def main():
    if not os.path.exists(TWEET_ARCHIVE_PATH):
        print(f"Error: The file {TWEET_ARCHIVE_PATH} does not exist.")
        return

    # Load tweets
    tweets = load_tweets(TWEET_ARCHIVE_PATH)
    print(f"Found {len(tweets)} tweets in the archive.")
    threads = combine_threads(tweets)
    print(f"Converted it into {len(threads)} threads.")

    i = 0
    for thread_id, thread in threads.items():
        i = i + 1
        if i > 10:
            break

        tweet_content = thread[0]["tweet"]["full_text"]
        if tweet_content.startswith("@"):
            create_dayone_entry_for_thread(thread, REPLY_JOURNAL)
        else:
            create_dayone_entry_for_thread(thread, TWEET_JOURNAL)


if __name__ == "__main__":
    main()
