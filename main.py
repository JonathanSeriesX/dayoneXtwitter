import json
import os
from collections import defaultdict

import functions
from dayone_agent import DayOneEntryCreator

script_dir = os.path.dirname(os.path.abspath(__file__))
TWEET_ARCHIVE_PATH = os.path.join(script_dir, "archive", "data", "tweets.js")

# SO this loads ALL tweets from big JSON file
# And then combines some tweets into threads
# Then for each thread it calls either of DayOneEntryCreator functions... sounds stupid?


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
            DayOneEntryCreator.create_reply(thread[0])
        else:
            DayOneEntryCreator.create_thread(thread)


if __name__ == "__main__":
    main()
