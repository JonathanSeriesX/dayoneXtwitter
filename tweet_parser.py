import json
import re
import os
from collections import defaultdict
from datetime import datetime

def _build_case_insensitive_name_map(tweet):
    """
    Creates a case-insensitive lookup map from screen_name (handle) to real name.
    Keys are lowercased for matching.
    """
    # Allow both {"tweet": {...}} wrappers and raw tweet dicts
    tweet_data = tweet.get("tweet", tweet)
    mentions = tweet_data.get("entities", {}).get("user_mentions", [])
    # Create the map with lowercased screen names as keys
    return {m["screen_name"].lower(): m.get("name") for m in mentions}

def _join_names_natural_language(names_list):
    """
    Joins a list of names into a natural-language string.
    e.g., ["A", "B", "C"] -> "A, B, and C"
    """
    if not names_list:
        return ""
    if len(names_list) == 1:
        return names_list[0]
    if len(names_list) == 2:
        return f"{names_list[0]} and {names_list[1]}"
    return f"{', '.join(names_list[:-1])}, and {names_list[-1]}"


def extract_callouts_inplace(first_tweet):
    """
    If a tweet (not a reply) begins with one or more @handles (callouts),
    this will:
      1. Extract each handle in order.
      2. Strip those leading handles (and any surrounding quotes) from full_text in-place.
      3. Return a natural-language string of display names: real name if found,
         otherwise "@handle".
    If no leading callouts are found, returns an empty list and leaves full_text untouched.
    """
    tweet = first_tweet.get("tweet", first_tweet)
    text = tweet.get("full_text", "")
    name_map = _build_case_insensitive_name_map(first_tweet)

    handles = []
    offset = 0
    # Repeatedly match a leading @handle (with optional surrounding quotes/spaces)
    while True:
        m = re.match(r'\s*["]?\.?@([A-Za-z0-9_]+)["]?\s*', text[offset:])
        if not m:
            break
        handles.append(m.group(1))
        offset += m.end()

    if not handles:
        return []

    # Mutate full_text to remove the callouts
    # tweet["full_text"] = text[offset:].lstrip()

    # Look up names case-insensitively and fall back to @handle
    display_names = [name_map.get(h.lower()) or f"@{h}" for h in handles]

    return _join_names_natural_language(display_names)


def extract_retweet_inplace(first_tweet):
    """
    If full_text starts with RT @handle: or RT "@handle: (or even RT @handle":),
    strips that prefix off full_text in-place and returns the retweeted user's
    name (or @handle if not in entities). Returns None if no RT found.
    """
    tweet = first_tweet.get("tweet", first_tweet)
    text = tweet.get("full_text", "")
    # Match RT, optional quote before/after handle, then colon
    m = re.match(r'^RT\s+["]?\@([A-Za-z0-9_]+)["]?:\s*(.*)', text, re.DOTALL)
    if not m:
        return None

    handle, remainder = m.group(1), m.group(2)
    tweet["full_text"] = remainder  # mutate in place

    # Use the helper to create the map and perform a case-insensitive lookup
    name_map = _build_case_insensitive_name_map(first_tweet)
    return name_map.get(handle.lower()) or f"@{handle}"


def extract_quote_handle(first_tweet):
    """
    If the tweet is a quote-tweet, finds the quoted status URL in entities.urls,
    extracts the username, and returns it as @username.
    Returns None if no quote URL is found.
    """
    # This function did not need refactoring as it doesn't look up names.
    tweet = first_tweet.get("tweet", first_tweet)
    for url_obj in tweet.get("entities", {}).get("urls", []):
        expanded = url_obj.get("expanded_url", "")
        m = re.match(r'https?://(?:www\.)?twitter\.com/([^/]+)/status/\d+', expanded)
        if m:
            return f"@{m.group(1)}"
    return None


def _get_reply_category(first_tweet):
    """
    Categorizes a reply tweet by extracting all @handles from full_text
    in order, then mapping each to its real name if present in entities,
    or falling back to the @nickname.
    """
    tweet_data = first_tweet.get('tweet', first_tweet)
    if not tweet_data.get('in_reply_to_status_id_str'):
        return "Not a reply"

    text = tweet_data.get("full_text", "")
    name_map = _build_case_insensitive_name_map(first_tweet)

    # Extract handles in the order they appear, remove duplicates
    handles = []
    for h in re.findall(r"@([A-Za-z0-9_]+)", text):
        if h not in handles:
            handles.append(h)

    # If no handles found, try the in_reply_to_screen_name
    if not handles and tweet_data.get("in_reply_to_screen_name"):
        handles = [tweet_data["in_reply_to_screen_name"]]

    if not handles:
        return "Not a reply"  # literally impossible, we should segfault if it happens lol

    # Look up names case-insensitively
    display_names = [name_map.get(h.lower()) or f"@{h}" for h in handles]

    # Use the natural language join helper
    joined_names = _join_names_natural_language(display_names)
    return f"Replied to {joined_names}"


def get_thread_category(thread):
    """
    Categorizes a tweet thread based on the characteristics of its first tweet.

    This function determines if a thread is a 'My thread' (multiple tweets),
    'My retweet', 'My quote tweet', 'My reply to', or a 'My tweet' (standalone).

    Args:
        thread (list): A list of tweet objects, where each object contains a 'tweet' key.

    Returns:
        str: A string describing the category of the thread.
    """
    if not thread:
        return "Empty threat" # again, we should just segfault at this point

    # The first tweet in the thread is used to determine its category.
    first_tweet_obj = thread[0]
    first_tweet = first_tweet_obj["tweet"]

    # Determine if the tweet is a direct retweet (starts with "RT @")
    is_retweet = first_tweet["full_text"].startswith("RT @") or first_tweet["full_text"].startswith("RT \"@")

    # Determine if the tweet is a reply to another tweet
    is_reply = first_tweet.get("in_reply_to_status_id_str") is not None
    is_callout = not is_reply and first_tweet["full_text"].startswith("@") or first_tweet["full_text"].startswith(".@")

    # Check for Twitter/X links in urls entities that are NOT media URLs.
    # This helps identify quote tweets that are not explicitly marked with 'quoted_status_id_str'.
    has_non_media_twitter_link = False
    # Collect t.co URLs from media entities to exclude them from general URL checks.
    # This prevents media links from being incorrectly identified as quote tweets.
    media_urls_tco = {m.get('url') for m in first_tweet.get('extended_entities', {}).get('media', [])}
    if not media_urls_tco:
        media_urls_tco = {m.get('url') for m in first_tweet.get('entities', {}).get('media', [])}

    for url_entity in first_tweet.get("entities", {}).get("urls", []):
        expanded_url = url_entity.get("expanded_url")
        tco_url = url_entity.get("url")
        # A link is considered a non-media Twitter link if it points to twitter.com or x.com
        # and its t.co URL is not found among the media t.co URLs.
        if expanded_url and ("https://twitter.com" in expanded_url or "https://x.com" in expanded_url) and tco_url not in media_urls_tco:
            has_non_media_twitter_link = True
            break

    # Categorize based on tweet properties, with more specific categories first.

    # A single tweet starting with "RT @", and not part of a larger thread, is a 'My retweet'.
    if is_retweet:
        name = extract_retweet_inplace(first_tweet)
        return f"Retweeted {name}"

    # A single tweet with a non-media Twitter/X link and not a reply is a 'My quote tweet'.
    # This handles cases where 'quoted_status_id_str' might be missing but a quote link exists.
    if has_non_media_twitter_link and not is_reply:
        name = extract_quote_handle(first_tweet)
        return f"Quoted {name}"

    if " RT @" in first_tweet["full_text"]:
        return f"Old-style quote tweet" #TODO

    # If it's a reply, determine the specific reply category using the helper function.
    if is_reply:
        return _get_reply_category(first_tweet)

    if is_callout:
        return f"Callout to {extract_callouts_inplace(first_tweet)}"

    # A thread with more than one tweet is always a 'My thread'.
    if len(thread) > 1:
        return "Wrote a thread"

    # If none of the above conditions are met, it's a standalone tweet.
    return "Tweeted"

def load_tweets(tweet_archive_path):
    """
    Loads tweets from the Twitter archive JSON file.

    The Twitter archive JSON file often contains a JavaScript variable declaration
    before the actual JSON array. This function extracts the JSON array.

    Args:
        tweet_archive_path (str): The absolute path to the Twitter archive JSON file.

    Returns:
        list: A list of tweet dictionaries.
    """
    with open(tweet_archive_path, "r", encoding="utf-8") as file:
        content = file.read()

        # Locate the first occurrence of '[' to find the start of the JSON array
        start_index = content.find("[")
        if start_index != -1:
            json_content = content[
                start_index:
            ].strip()  # Extract and strip whitespace
            try:
                tweets = json.loads(json_content)
            except json.JSONDecodeError as e:
                print("JSON decoding failed:", e)
                print(
                    "Content preview for debugging:", json_content[:500]
                )  # Print up to 500 chars for debugging
                tweets = []
        else:
            print("Error: JSON data could not be located in file.")
            tweets = []

    for tweet_data in tweets:
        # Parse the created_at string into a datetime object
        # Example format: "Fri Mar 21 04:40:00 +0000 2006"
        created_at_str = tweet_data['tweet']['created_at']
        tweet_data['tweet']['created_at'] = datetime.strptime(created_at_str, '%a %b %d %H:%M:%S %z %Y').replace(tzinfo=None)

    return tweets


def combine_threads(tweets):
    """
    Groups tweets into conversational threads by following reply chains.

    Args:
        tweets (list): A list of tweet dictionaries.

    Returns:
        list: A list of lists, where each inner list represents a thread
              of chronologically ordered tweets.
    """
    # Create a quick-access map of tweets by their ID for efficient lookup
    tweet_by_id = {tweet['tweet']['id_str']: tweet for tweet in tweets}

    # Map parent tweet IDs to a list of their direct children (replies)
    children_map = defaultdict(list)
    # Keep track of all tweet IDs that are replies to something within the archive
    all_child_ids = set()

    for tweet in tweets:
        parent_id = tweet['tweet'].get('in_reply_to_status_id_str')
        if parent_id:
            # Only consider replies where the parent tweet is also in our archive
            if parent_id in tweet_by_id:
                children_map[parent_id].append(tweet)
                all_child_ids.add(tweet['tweet']['id_str'])

    # Identify "root" tweets: those that are not replies to any other tweet in the archive
    root_tweets = [t for t in tweets if t['tweet']['id_str'] not in all_child_ids]

    # Sort root tweets chronologically by converting their ID strings to integers.
    # This ensures threads are processed and built in a consistent order.
    sorted_roots = sorted(root_tweets, key=lambda t: int(t['tweet']['id_str']))

    # Build the final list of threads using a breadth-first traversal from each root
    final_threads = []
    for root in sorted_roots:
        thread = []
        queue = [root]
        while queue:
            current_tweet = queue.pop(0)
            thread.append(current_tweet)

            # Get children (replies) of the current tweet, sort them chronologically,
            # and add them to the queue for further processing.
            children = children_map.get(current_tweet['tweet']['id_str'], [])
            sorted_children = sorted(children, key=lambda t: int(t['tweet']['id_str']))
            queue.extend(sorted_children)
        
        # Add the completed thread to the final list if it's not empty
        if len(thread) > 0:
            final_threads.append(thread)

    return final_threads

def _process_url_entities(entities):
    links_to_process = []
    for url_entity in entities.get('urls', []):
        tco_url = url_entity.get('url')
        expanded_url = url_entity.get('expanded_url')
        display_url = url_entity.get('display_url')

        if tco_url and expanded_url:
            link_text = display_url if display_url else expanded_url
            links_to_process.append({
                'tco_url': tco_url,
                'markdown_link': f"[{link_text}]({expanded_url})"
            })
    return links_to_process


def _process_media_entities(tweet_data, entities):
    media_by_tco = defaultdict(list)
    media_entities = tweet_data.get('extended_entities', {}).get('media', [])
    if not media_entities:
        media_entities = entities.get('media', [])

    for media_entity in media_entities:
        tco_url = media_entity.get('url')
        media_type = media_entity.get('type')

        if tco_url:
            if media_type == 'photo':
                media_url = media_entity.get('media_url_https')
                if media_url:
                    media_by_tco[tco_url].append({
                        'media_url': media_url,
                        'type': media_type
                    })
            elif media_type in ('video', 'animated_gif'):
                info = media_entity.get('video_info', {})
                variants = info.get('variants', [])
                mp4s = []
                for v in variants:
                    if v.get('content_type') == 'video/mp4' and 'bitrate' in v:
                        try:
                            v_bitrate = int(v['bitrate'])
                        except (TypeError, ValueError):
                            continue
                        mp4s.append((v_bitrate, v['url']))
                if mp4s:
                    best_bitrate, best_url = max(mp4s, key=lambda x: x[0])
                    media_by_tco[tco_url].append({
                        'media_url': best_url,
                        'type': media_type
                    })
    return media_by_tco


def _replace_links_in_text(text, links, media_map):
    processed_text = text
    links.sort(key=lambda x: len(x['tco_url']), reverse=True)
    for link_info in links:
        tco_url = link_info['tco_url']
        if tco_url in media_map:
            continue
        markdown_link = link_info['markdown_link']
        processed_text = re.sub(re.escape(tco_url), markdown_link, processed_text)
    return processed_text


def _replace_media_in_text(text, media_map, tweet_id):
    processed_text = text
    media_files = []
    sorted_media_tco_urls = sorted(media_map.keys(), key=len, reverse=True)

    for tco_url in sorted_media_tco_urls:
        media_items = media_map[tco_url]
        attachment_placeholders = ''.join(['[{attachment}]' for _ in media_items])
        processed_text = re.sub(re.escape(tco_url), attachment_placeholders, processed_text)

        for media_info in media_items:
            media_url = media_info['media_url']
            media_filename = os.path.basename(media_url).split('?')[0]
            if media_info['type'] in ['video', 'animated_gif']:
                media_filename = os.path.splitext(media_filename)[0] + '.mp4'
            
            # Construct the absolute path to the media file within the local archive structure.
            media_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'archive', 'data', 'tweets_media', f"{tweet_id}-{media_filename}")
            media_files.append(media_path)
            
    return processed_text, media_files


def process_tweet_text_for_markdown_links(tweet):
    """
    Converts t.co links in a tweet's full_text to Markdown format using expanded URLs.
    Also extracts media file paths and stores them.
    Modifies the tweet object in place.

    Args:
        tweet (dict): The tweet object to process.
    """
    tweet_data = tweet.get('tweet')
    if not tweet_data:
        return

    full_text = tweet_data.get('full_text')
    entities = tweet_data.get('entities')
    tweet_id = tweet_data.get('id_str')

    if not all([full_text, entities, tweet_id]):
        return

    links_to_process = _process_url_entities(entities)
    media_by_tco = _process_media_entities(tweet_data, entities)

    processed_text = _replace_links_in_text(full_text, links_to_process, media_by_tco)
    processed_text, media_files = _replace_media_in_text(processed_text, media_by_tco, tweet_id)

    tweet_data['full_text'] = processed_text.strip()
    tweet_data['media_files'] = media_files



