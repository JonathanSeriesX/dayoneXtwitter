"""Step 5a of the pipeline: name what kind of tweet a thread is.

Every thread gets a human-readable category derived from its first tweet:
"Wrote a thread", "Tweeted", "Replied to <names>", "Retweeted <name>",
"Quoted <name or myself>", or "Callout to <names>". The category becomes the
entry's fallback title, and decides which journal the entry lands in (replies
go to their own journal, see entry_composer.get_target_journal).

Heads-up for maintainers: categorization also cleans the tweet's text in
place — a retweet's "RT @user:" prefix is stripped while the retweeted user
is extracted. So get_thread_category() must run before the entry text is
composed, exactly once per thread.
"""

from __future__ import annotations

import re

import config
import twitter_archive
from models import Thread


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
    If full_text contains "RT @handle: ..." (or variations with quotes),
    strips the text to just the content after that prefix and returns the
    retweeted user's name (or @handle if not in entities). The first
    such match is used. Returns None if no RT found.
    """
    tweet = first_tweet.get("tweet", first_tweet)
    text = tweet.get("full_text", "")

    # Use re.search() to find the pattern anywhere in the string.
    # Add a word boundary (\b) before RT to ensure we don't match it as
    # part of another word (e.g., "DIRT"). The required space (\s+)
    # after RT prevents matching "RT."
    m = re.search(r'\bRT\s+["]?\@([A-Za-z0-9_]+)["]?:\s*(.*)', text, re.DOTALL)
    if not m:
        return None

    handle, remainder = m.group(1), m.group(2)
    tweet["full_text"] = remainder  # mutate in place

    # Use the helper to create the map and perform a case-insensitive lookup
    name_map = _build_case_insensitive_name_map(first_tweet)
    return name_map.get(handle.lower()) or f"@{handle}"


def extract_quote_target(first_tweet):
    """
    If the tweet is a quote-tweet, finds the quoted status URL in entities.urls
    and returns a (handle, status_id) tuple, e.g. ("@somebody", "12345").
    Returns (None, None) if no quote URL is found.
    """
    tweet = first_tweet.get("tweet", first_tweet)
    for url_obj in tweet.get("entities", {}).get("urls", []):
        expanded = url_obj.get("expanded_url", "")
        m = re.match(
            r"https?://(?:www\.)?(?:twitter\.com|x\.com)/([^/]+)/status/(\d+)", expanded
        )
        if m:
            return f"@{m.group(1)}", m.group(2)
    return None, None


def _describe_quote_target(first_tweet):
    """
    Names whoever the tweet quotes: "myself" for one's own tweets, otherwise
    the @handle from the quoted status URL.

    A quote is "myself" if the quoted tweet ID is in the loaded archive — which
    also covers tweets quoted under an old, since-changed username — or if the
    handle matches CURRENT_USERNAME (covers own tweets deleted from the archive).
    """
    handle, status_id = extract_quote_target(first_tweet)
    if status_id and status_id in twitter_archive.OWN_TWEET_IDS:
        return "myself"
    if (
        handle
        and config.CURRENT_USERNAME
        and handle.lower() == f"@{config.CURRENT_USERNAME}".lower()
    ):
        return "myself"
    return handle


def _get_reply_category(first_tweet):
    """
    Categorizes a reply tweet by extracting all @handles from full_text
    in order, then mapping each to its real name if present in entities,
    or falling back to the @nickname.
    """
    tweet_data = first_tweet.get("tweet", first_tweet)
    if not tweet_data.get("in_reply_to_status_id_str"):
        return "Not a reply"

    text = tweet_data.get("full_text", "")
    name_map = _build_case_insensitive_name_map(first_tweet)

    # Extract handles in the order they appear from the full_text
    # and then map them to their real names.
    # This ensures the order of names in the "Replied to" string matches the tweet.
    extracted_handles_in_order = []
    for match in re.finditer(r"@([A-Za-z0-9_]+)", text):
        handle = match.group(1)
        extracted_handles_in_order.append(handle)

    # Remove duplicates while preserving order
    seen = set()
    unique_handles_in_order = []
    for h in extracted_handles_in_order:
        if h not in seen:
            unique_handles_in_order.append(h)
            seen.add(h)

    # If no handles found in text, fall back to in_reply_to_screen_name
    if not unique_handles_in_order and tweet_data.get("in_reply_to_screen_name"):
        unique_handles_in_order = [tweet_data["in_reply_to_screen_name"]]

    if not unique_handles_in_order:
        return "Not a reply"

    # Look up names case-insensitively using the name_map
    display_names = [
        name_map.get(h.lower()) or f"@{h}" for h in unique_handles_in_order
    ]

    # Use the natural language join helper
    joined_names = _join_names_natural_language(display_names)
    return f"Replied to {joined_names}"


def get_thread_category(thread: Thread) -> str:
    """
    Categorizes a tweet thread based on the characteristics of its first tweet.

    This function determines if a thread is a 'Wrote a thread' (multiple
    tweets), 'Retweeted ...', 'Quoted ...', 'Replied to ...', 'Callout to ...',
    or a plain 'Tweeted' (standalone).
    """
    if not thread:
        return "Empty threat"  # again, we should just segfault at this point

    # The first tweet in the thread is used to determine its category.
    first_tweet_obj = thread[0]
    first_tweet = first_tweet_obj["tweet"]

    # Determine if the tweet is a direct retweet (starts with "RT @")
    is_retweet = first_tweet["full_text"].startswith("RT @") or first_tweet[
        "full_text"
    ].startswith('RT "@')

    # Determine if the tweet is a reply to another tweet
    is_reply = first_tweet.get("in_reply_to_status_id_str") is not None
    is_callout = (
        not is_reply
        and first_tweet["full_text"].startswith("@")
        or first_tweet["full_text"].startswith(".@")
    )

    # Check for Twitter/X links in urls entities that are NOT media URLs.
    # This helps identify quote tweets that are not explicitly marked with 'quoted_status_id_str'.
    has_non_media_twitter_link = False
    # Collect t.co URLs from media entities to exclude them from general URL checks.
    # This prevents media links from being incorrectly identified as quote tweets.
    media_urls_tco = {
        m.get("url") for m in first_tweet.get("extended_entities", {}).get("media", [])
    }
    if not media_urls_tco:
        media_urls_tco = {
            m.get("url") for m in first_tweet.get("entities", {}).get("media", [])
        }

    for url_entity in first_tweet.get("entities", {}).get("urls", []):
        expanded_url = url_entity.get("expanded_url")
        tco_url = url_entity.get("url")
        # A link is considered a non-media Twitter link if it points to twitter.com or x.com
        # and its t.co URL is not found among the media t.co URLs.
        if (
            expanded_url
            and (
                "https://twitter.com" in expanded_url or "https://x.com" in expanded_url
            )
            and tco_url not in media_urls_tco
        ):
            has_non_media_twitter_link = True
            break

    # Categorize based on tweet properties, with more specific categories first.

    # A single tweet starting with "RT @", and not part of a larger thread, is a retweet.
    if is_retweet:
        name = extract_retweet_inplace(first_tweet)
        return f"Retweeted {name}"

    # A tweet with a non-media Twitter/X link and not a reply is a quote tweet.
    # This handles cases where 'quoted_status_id_str' might be missing but a quote link exists.
    if has_non_media_twitter_link and not is_reply:
        name = _describe_quote_target(first_tweet)
        return f"Quoted {name}"

    if " RT @" in first_tweet["full_text"]:
        name = _describe_quote_target(first_tweet)
        return f"Quoted {name}"

    # If it's a reply, determine the specific reply category using the helper function.
    if is_reply:
        return _get_reply_category(first_tweet)

    if is_callout:
        return f"Callout to {extract_callouts_inplace(first_tweet)}"

    # A thread with more than one tweet is always a thread of one's own.
    if len(thread) > 1:
        return "Wrote a thread"

    # If none of the above conditions are met, it's a standalone tweet.
    return "Tweeted"
