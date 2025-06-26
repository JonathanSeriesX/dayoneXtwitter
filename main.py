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
    print("Expanded t.co links inside of tweets.")
    threads = combine_threads(tweets)
    print(f"Converted those tweets into {len(threads)} threads.")

    random.shuffle(threads)

    # Limit the number of threads to process to avoid overwhelming Day One or for testing purposes.
    # This can be made configurable in config.py if needed.
    MAX_THREADS_TO_PROCESS = 60
    # Iterate through each thread, process it, and create a Day One entry.
    for i, thread in enumerate(threads):
        if i >= MAX_THREADS_TO_PROCESS:
            print(f"\nStopping after processing {MAX_THREADS_TO_PROCESS} threads.")
            break

        # Determine the category of the thread (e.g., "My thread", "My retweet").
        category = get_thread_category(thread)
        # Construct a header for the console output, indicating thread type and tweet count.
        if len(thread) > 1:
            header = f"--- {category} ({len(thread)} tweets) ---"
        else:
            header = f"--- {category} ---"

        print(f"\n{header}")

        # Display details for each tweet within the current thread.
        for j, tweet_in_thread in enumerate(thread):
            # Indent subsequent tweets in a thread for better readability in console output.
            indent = "  " if j > 0 else ""
            print(f"{indent} L {tweet_in_thread['tweet']['full_text']}")
            
            # Extract and display engagement metrics (likes, retweets).
            likes = int(tweet_in_thread["tweet"]["favorite_count"])
            rts = int(tweet_in_thread["tweet"]["retweet_count"])

            parts = []
            if likes > 0:
                parts.append(f"Likes: {likes}⭐️")
            if rts > 0:
                parts.append(f"Retweets: {rts}🔁")

            if parts:
                print(f"{indent}   " + "   ".join(parts))
            
            # Display hashtags associated with the tweet.
            if tweet_in_thread["tweet"]["entities"].get("hashtags"):
                for hashtag in tweet_in_thread["tweet"]["entities"]["hashtags"]:
                    print(f"{indent}   Hashtag: #{hashtag['text']}")
            
            # Display geographical coordinates if available.
            if tweet_in_thread["tweet"].get("coordinates") and tweet_in_thread["tweet"]["coordinates"].get("coordinates"):
                longitude = tweet_in_thread["tweet"]["coordinates"]["coordinates"][0]
                latitude = tweet_in_thread["tweet"]["coordinates"]["coordinates"][1]
                print(f"{indent}   Location: Longitude {longitude}, Latitude {latitude}")
            
            # Display paths to attached media files.
            if tweet_in_thread["tweet"]["media_files"]:
                for media_file in tweet_in_thread["tweet"]["media_files"]:
                    print(f"{indent}   Media: {media_file}")

        # --- Prepare data for Day One entry ---
        # Initialize variables to accumulate data for the Day One entry from all tweets in the thread.
        entry_text = ""
        entry_tags = []
        entry_media_files = []
        entry_date_time = None  # Date/time will be taken from the first tweet.
        entry_coordinate = None # Coordinate will be taken from the first tweet with coordinates.

        # Aggregate content from all tweets in the thread for the Day One entry.
        for tweet_in_thread in thread:
            # Concatenate full text of all tweets in the thread.
            entry_text += tweet_in_thread['tweet']['full_text'] + "\n\n"

            # Collect all unique hashtags from all tweets in the thread.
            if tweet_in_thread["tweet"]["entities"].get("hashtags"):
                for hashtag in tweet_in_thread["tweet"]["entities"]["hashtags"]:
                    entry_tags.append(hashtag['text'])

            # Collect all media file paths from all tweets in the thread.
            if tweet_in_thread["tweet"]["media_files"]:
                for media_file in tweet_in_thread["tweet"]["media_files"]:
                    entry_media_files.append(media_file)

            # Set the entry date/time using the 'created_at' timestamp of the first tweet in the thread.
            # This ensures the Day One entry reflects the original tweet's timestamp.
            if not entry_date_time:
                try:
                    entry_date_time = datetime.strptime(tweet_in_thread['tweet']['created_at'], "%a %b %d %H:%M:%S %z %Y")
                except ValueError:
                    print(f"Warning: Could not parse date {tweet_in_thread['tweet']['created_at']}")
                    entry_date_time = None

            # Set the entry coordinate using the first available coordinate from any tweet in the thread.
            if not entry_coordinate and tweet_in_thread["tweet"].get("coordinates") and tweet_in_thread["tweet"]["coordinates"].get("coordinates"):
                longitude = tweet_in_thread["tweet"]["coordinates"]["coordinates"][0]
                latitude = tweet_in_thread["tweet"]["coordinates"]["coordinates"][1]
                entry_coordinate = (latitude, longitude)

        # Get the first tweet object from the thread for specific details like URL and metrics.
        first_tweet_in_thread = thread[0]['tweet']

        # Get the first tweet object from the thread for specific details like URL and metrics.
        first_tweet_in_thread = thread[0]['tweet']

        # Determine the title for the Day One entry.
        if config.PROCESS_TITLES_WITH_LLM:
            # Generate a one-word summary using the local LLM.
            llm_summary = get_tweet_summary(first_tweet_in_thread['full_text'])
            # Add a title to the entry text, using the determined thread category and LLM summary.
            if category == "My tweet":
                title = f"A tweet about {llm_summary}"
            elif category == "My thread":
                title = f"A thread about {llm_summary}"
            else:
                title = f"{category} about {llm_summary}"
        else:
            # Use the original category-based title if LLM processing is disabled.
            title = f"{category}"
        entry_text = f"# {title}\n\n{entry_text}\n\n"

        # Construct the URL to the original tweet on twitter.com.
        tweet_url = f"https://twitter.com/{CURRENT_USERNAME}/status/{first_tweet_in_thread['id_str']}"
        metrics = []
        likes = int(first_tweet_in_thread["favorite_count"])
        rts = int(first_tweet_in_thread["retweet_count"])

        # Handle reply links: extract mentions and format the reply URL.
        if first_tweet_in_thread.get("in_reply_to_status_id_str"):
            # Extract all @mentions from the entry text.
            mentions = re.findall(r"@\w+", entry_text)
            # Remove mentions from the main text to avoid duplication if they are part of the reply context.
            rest = re.sub(r"(?:@\w+\s*)+", "", entry_text).strip()
            # Join mentions into a single string for display.
            mentions_str = " ".join(mentions)

            # Reconstruct entry text with the cleaned text and the reply link.
            entry_text = f"#{rest}\n\n"
            reply_to_tweet_id = first_tweet_in_thread["in_reply_to_status_id_str"]
            reply_to_url = f"https://twitter.com/i/web/status/{reply_to_tweet_id}"
            entry_text += f"[In response to]({reply_to_url}) {mentions_str}\n"

        # Add likes and retweets metrics with links to their respective Twitter pages.
        if likes > 0:
            metrics.append(f"[Likes: {likes}]({tweet_url}/likes) ⭐️")
        if rts > 0:
            metrics.append(f"[Retweets: {rts}]({tweet_url}/retweets) 🔁")

        # If metrics exist, join them and add to the entry text.
        if metrics:
            entry_text += "   ".join(metrics) + "\n"

        # Add a footer with a direct link to the tweet on twitter.com.
        entry_text += f"_______\n[Open on twitter.com]({tweet_url})\n"

        # Call add_post to create the Day One entry.
        # Tags are converted to a set first to ensure uniqueness before converting back to a list.
        add_post(
            text=entry_text,
            journal=config.JOURNAL_NAME,
            tags=list(set(entry_tags)),
            date_time=entry_date_time,
            coordinate=entry_coordinate,
            attachments=entry_media_files
        )


if __name__ == "__main__":
    main()
