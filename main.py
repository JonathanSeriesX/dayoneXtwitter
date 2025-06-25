import json
import os
import re
from collections import defaultdict
from datetime import datetime, timedelta

from dayone import add_post

script_dir = os.path.dirname(os.path.abspath(__file__))
TWEET_ARCHIVE_PATH = os.path.join(script_dir, "archive", "data", "tweets.js")

# SO this loads ALL tweets from big JSON file
# And then combines some tweets into threads
# Then for each thread it calls either of DayOneEntryCreator functions... sounds stupid?

# This is a dummy static function that adds a post to the Day One app.
def create_my_first_post():
    """
    Creates a sample post in Day One using our CLI helper.
    """
    print("Attempting to create a new Day One entry...")

    entry_text = "This is a test entry from my Python application! It's pretty cool."
    entry_tags = ["python", "automation", "testing"]

    # Call the function from our helper module
    success = add_post(
        text=entry_text,
        journal="Python Journal",
        tags=entry_tags,
        starred=True,
        date_time=datetime.now() - timedelta(days=1)  # Set the entry for yesterday
    )

    if success:
        print("\nDummy function completed successfully!")
    else:
        print("\nDummy function failed to create the post.")


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
    # Create a quick-access map of tweets by their ID
    tweet_by_id = {tweet['tweet']['id_str']: tweet for tweet in tweets}

    # Map parent tweet IDs to a list of their direct children (replies)
    children_map = defaultdict(list)
    # Keep track of all tweets that are replies to something
    all_child_ids = set()

    for tweet in tweets:
        parent_id = tweet['tweet'].get('in_reply_to_status_id_str')
        if parent_id:
            # Only add if the parent is actually in our archive
            if parent_id in tweet_by_id:
                children_map[parent_id].append(tweet)
                all_child_ids.add(tweet['tweet']['id_str'])

    # A "root" tweet is one that is not a reply to any other tweet in the archive
    root_tweets = [t for t in tweets if t['tweet']['id_str'] not in all_child_ids]

    # Sort roots to process them in a predictable, chronological order
    sorted_roots = sorted(root_tweets, key=lambda t: t['tweet']['id_str'])

    # Build the final list of threads using the relationships we've mapped
    final_threads = []
    for root in sorted_roots:
        thread = []
        # Use a queue for a breadth-first traversal to build the thread
        queue = [root]
        while queue:
            current_tweet = queue.pop(0)
            thread.append(current_tweet)

            # Get children, sort them chronologically, and add to the queue
            children = children_map.get(current_tweet['tweet']['id_str'], [])
            sorted_children = sorted(children, key=lambda t: t['tweet']['id_str'])
            queue.extend(sorted_children)

        final_threads.append(thread)

    return final_threads


def process_tweet_text_for_markdown_links(tweet):
    """
    Converts t.co links in a tweet's full_text to Markdown format using expanded URLs.
    Modifies the tweet object in place.
    """
    tweet_data = tweet.get('tweet')
    if not tweet_data:
        return

    full_text = tweet_data.get('full_text')
    entities = tweet_data.get('entities')

    if not full_text or not entities:
        return

    links_to_process = []

    # Process 'urls' entities (standard links)
    for url_entity in entities.get('urls', []):
        tco_url = url_entity.get('url')
        expanded_url = url_entity.get('expanded_url')
        display_url = url_entity.get('display_url')

        if tco_url and expanded_url:
            # Prefer display_url for link text, fallback to expanded_url
            link_text = display_url if display_url else expanded_url
            links_to_process.append({
                'tco_url': tco_url,
                'markdown_link': f"[{link_text}]({expanded_url})"
            })

    # Process 'media' entities (links to attached media like photos/videos)
    for media_entity in entities.get('media', []):
        tco_url = media_entity.get('url')
        expanded_url = media_entity.get('expanded_url')
        display_url = media_entity.get('display_url')

        if tco_url and expanded_url:
            # For media, the t.co link often represents the media itself.
            # The display_url might be something like "pic.twitter.com/XYZ".
            # We want to link to the expanded_url (e.g., the direct image link or Twitter's media page).
            link_text = display_url if display_url else expanded_url
            links_to_process.append({
                'tco_url': tco_url,
                'markdown_link': f"[{link_text}]({expanded_url})"
            })

    # Sort by length of t.co_url in descending order. This is crucial
    # to prevent issues where a shorter t.co URL might be a substring
    # of a longer one, ensuring the longest matches are replaced first.
    links_to_process.sort(key=lambda x: len(x['tco_url']), reverse=True)

    processed_text = full_text
    for link_info in links_to_process:
        tco_url = link_info['tco_url']
        markdown_link = link_info['markdown_link']

        # Use re.sub with re.escape to ensure any special characters in the t.co URL
        # itself are treated literally by the regex, preventing errors.
        # This will replace all occurrences of the t.co_url in the text.
        processed_text = re.sub(re.escape(tco_url), markdown_link, processed_text)

    tweet_data['full_text'] = processed_text


def main():
    if not os.path.exists(TWEET_ARCHIVE_PATH):
        print(f"Error: The file {TWEET_ARCHIVE_PATH} does not exist.")
        return

    # Load tweets
    tweets = load_tweets(TWEET_ARCHIVE_PATH)
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
            indent = "  " if i>0 else ""
            print(f"{indent} L {tweet_in_thread['tweet']['full_text']}")


if __name__ == "__main__":
    main()
