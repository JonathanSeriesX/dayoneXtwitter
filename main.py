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

    for i, thread in enumerate(threads):
        if i > 60:
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
        entry_text = f"# {title}\n\n{entry_text}\n\n"

        first_tweet_in_thread = thread[0]['tweet'] # Define first_tweet_in_thread here

        # Add likes, retweets, and original tweet link
        tweet_url = f"https://twitter.com/{CURRENT_USERNAME}/status/{first_tweet_in_thread['id_str']}"
        metrics = []
        likes = int(first_tweet_in_thread["favorite_count"])
        rts = int(first_tweet_in_thread["retweet_count"])

        # Add reply link if applicable
        if first_tweet_in_thread.get("in_reply_to_status_id_str"):
            mentions = re.findall(r"@\w+", entry_text)
            # mentions example == ['@ZephyrionVortex', '@TheOmenXXX', '@Dachsjaeger']

            # 2. Remove them from the original text
            rest = re.sub(r"(?:@\w+\s*)+", "", entry_text).strip()

            # 3. If you need them as a single string
            mentions_str = " ".join(mentions)
            # mentions_str == "@ZephyrionVortex @TheOmenXXX @Dachsjaeger"

            entry_text = f"#{rest}\n\n"
            reply_to_tweet_id = first_tweet_in_thread["in_reply_to_status_id_str"]
            reply_to_url = f"https://twitter.com/i/web/status/{reply_to_tweet_id}"
            entry_text += f"[In response to]({reply_to_url}) {mentions_str}\n"

        if likes > 0:
            metrics.append(f"[Likes: {likes}]({tweet_url}/likes) ⭐️")
        if rts > 0:
            metrics.append(f"[Retweets: {rts}]({tweet_url}/retweets) 🔁")

        # if we have at least one, join on a space (or two) and add a single newline
        if metrics:
            entry_text += "   ".join(metrics) + "\n"


        entry_text += f"_______\n[Open on twitter.com]({tweet_url})\n"

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
