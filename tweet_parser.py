import json
import re
import os
from collections import defaultdict

def get_thread_category(thread):
    """
    Categorizes a thread based on its properties.

    Args:
        thread: A list of tweet objects representing a thread.

    Returns:
        A string describing the category of the thread.
    """
    if not thread:
        return "Empty threat"

    # The first tweet determines the category for single-tweet threads.
    first_tweet_obj = thread[0]
    first_tweet = first_tweet_obj["tweet"]

    is_retweet = first_tweet["full_text"].startswith("RT @")
    is_reply = first_tweet.get("in_reply_to_status_id_str") is not None

    # Check for Twitter/X links in urls entities that are NOT media URLs
    has_non_media_twitter_link = False
    media_urls_tco = {m.get('url') for m in first_tweet.get('extended_entities', {}).get('media', [])}
    if not media_urls_tco:
        media_urls_tco = {m.get('url') for m in first_tweet.get('entities', {}).get('media', [])}

    for url_entity in first_tweet.get("entities", {}).get("urls", []):
        expanded_url = url_entity.get("expanded_url")
        tco_url = url_entity.get("url")
        if expanded_url and ("twitter.com" in expanded_url or "x.com" in expanded_url) and tco_url not in media_urls_tco:
            has_non_media_twitter_link = True
            break

    # A list of more than one tweet is always a thread you created.
    if len(thread) > 1:
        return "My thread"

    # For single-tweet "threads":
    if is_retweet:
        return "My retweet"

    if has_non_media_twitter_link and not is_reply:
        return "My quote tweet"

    if is_reply:
        # If it's a reply and a single tweet, it's a reply to someone else.
        # Self-replies would have been grouped into a thread.
        mentions = first_tweet.get("entities", {}).get("user_mentions", [])
        reply_to_user = first_tweet.get("in_reply_to_screen_name", "user")

        if len(mentions) > 1:
            if len(mentions) == 2:
                return f"My reply to {mentions[0]["name"]} and {mentions[1]["name"]}"
            return (
                    "My reply to "
                    + ", ".join(f"{m['name']}" for m in mentions[:-1])
                    + f", and {mentions[-1]['name']}"
            )
        # Find the name of the user being replied to
        reply_to_name = reply_to_user # Default to screen_name if name not found
        for mention in mentions:
            if mention['screen_name'] == reply_to_user:
                reply_to_name = mention['name']
                break
        return f"My reply to {reply_to_name}"

    # If it's not a thread, retweet, or reply, it's a standalone tweet.
    return "My tweet"

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
    sorted_roots = sorted(root_tweets, key=lambda t: int(t['tweet']['id_str']))

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
            sorted_children = sorted(children, key=lambda t: int(t['tweet']['id_str']))
            queue.extend(sorted_children)
        if len(thread) > 0:
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
    media_to_process = []

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
    # Prioritize extended_entities for comprehensive media handling
    media_entities = tweet_data.get('extended_entities', {}).get('media', [])
    if not media_entities:
        media_entities = entities.get('media', []) # Fallback to entities if extended_entities is not present

    for media_entity in media_entities:
        tco_url = media_entity.get('url')
        media_type = media_entity.get('type')

        if tco_url:
            if media_type == 'photo':
                media_url = media_entity.get('media_url_https')
                if media_url:
                    media_to_process.append({
                        'tco_url': tco_url,
                        'media_url': media_url,
                        'type': media_type
                    })
            elif media_type in ['video', 'animated_gif']:
                video_info = media_entity.get('video_info')
                if video_info and 'variants' in video_info:
                    # Find the video variant with the highest bitrate
                    best_variant = None
                    for variant in video_info['variants']:
                        if 'bitrate' in variant and variant['content_type'] == 'video/mp4':
                            if not best_variant or variant['bitrate'] > best_variant['bitrate']:
                                best_variant = variant
                    if best_variant and best_variant.get('url'):
                        media_to_process.append({
                            'tco_url': tco_url,
                            'media_url': best_variant['url'],
                            'type': media_type
                        })


    # Sort by length of t.co_url in descending order. This is crucial
    # to prevent issues where a shorter t.co URL might be a substring
    # of a longer one, ensuring the longest matches are replaced first.
    links_to_process.sort(key=lambda x: len(x['tco_url']), reverse=True)
    media_to_process.sort(key=lambda x: len(x['tco_url']), reverse=True)


    processed_text = full_text
    for link_info in links_to_process:
        tco_url = link_info['tco_url']
        markdown_link = link_info['markdown_link']

        # Use re.sub with re.escape to ensure any special characters in the t.co URL
        # itself are treated literally by the regex, preventing errors.
        # This will replace all occurrences of the t.co_url in the text.
        processed_text = re.sub(re.escape(tco_url), markdown_link, processed_text)

    tweet_data['media_files'] = []
    for media_info in media_to_process:
        tco_url = media_info['tco_url']
        media_url = media_info['media_url']
        processed_text = re.sub(re.escape(tco_url), '', processed_text)
        # Construct the path to the media file in the archive
        media_filename = os.path.basename(media_url).split('?')[0] # Remove query parameters
        if media_info['type'] in ['video', 'animated_gif']:
            media_filename = os.path.splitext(media_filename)[0] + '.mp4'
        media_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'archive', 'data', 'tweets_media', f"{tweet_data['id_str']}-{media_filename}")
        tweet_data['media_files'].append(media_path)


    tweet_data['full_text'] = processed_text.strip()



