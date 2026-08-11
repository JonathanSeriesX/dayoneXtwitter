import json
import os
import random
import re
from pathlib import Path

import config
from tweet_parser import (
    load_tweets,
    combine_threads,
    process_tweet_text_for_markdown_links,
    get_thread_category,
    adopt_orphan_self_replies,
)
from dayone_entry_builder import aggregate_thread_data, generate_entry_title, build_entry_content, get_target_journal
from dayone_entry import add_post


root = Path(__file__).resolve().parent
STATUSES_FILE_PATH = str(root / "processed_tweets.txt")
DUPLICATES_FILE_PATH = str(root / "threads_to_delete.txt")
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


def _tweets_part_number(path: Path) -> int:
    """Sort key for archive parts: tweets.js is part 0, tweets-part<N>.js is part N."""
    m = re.fullmatch(r"tweets-part(\d+)\.js", path.name)
    return int(m.group(1)) if m else 0


# Large archives are split into tweets.js, tweets-part1.js, tweets-part2.js, … —
# all in the same data folder. Threads regularly span the split, so every part
# has to be loaded, in order, for parent-tweet lookups to work.
TWEETS_JS_PATHS = [
    str(p)
    for p in sorted(
        (
            p
            for p in js.parent.glob("tweets*.js")
            if p.name == "tweets.js" or re.fullmatch(r"tweets-part\d+\.js", p.name)
        ),
        key=_tweets_part_number,
    )
]

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


def load_own_account_id():
    """
    Reads the account ID from the archive's account.js. The ID is stable across
    username changes, unlike CURRENT_USERNAME. Returns None if unavailable.
    """
    account_js = os.path.join(TWEET_ARCHIVE_PATH, "account.js")
    if not os.path.exists(account_js):
        return None
    try:
        with open(account_js, "r", encoding="utf-8") as f:
            content = f.read()
        accounts = json.loads(content[content.find("["):])
        return accounts[0]["account"]["accountId"]
    except (json.JSONDecodeError, LookupError, ValueError):
        return None


def load_and_prepare_threads(tweet_ids_to_debug=None):
    """Loads tweets, expands links, combines threads, and shuffles them."""
    tweets = load_tweets(TWEETS_JS_PATHS)
    print(f"Using archive folder {TWEET_ARCHIVE_PATH}")
    part_count_str = f" across {len(TWEETS_JS_PATHS)} files" if len(TWEETS_JS_PATHS) > 1 else ""
    print(f"Found {len(tweets)} tweets in the archive{part_count_str}.")

    adopted = adopt_orphan_self_replies(tweets, load_own_account_id())
    if adopted:
        print(
            f"Adopted {adopted} self-repl(ies) whose parent tweet is gone from the "
            "archive; they will be published as ordinary tweets."
        )
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


def extension_marker(thread: list) -> str:
    """Identifies a thread together with its current last tweet, so a thread that
    was imported once and extended later can be told apart from the copy already
    in Day One. The '+' keeps these markers distinct from plain tweet IDs."""
    return f"{thread[0]['tweet']['id_str']}+{thread[-1]['tweet']['id_str']}"


def _remember_processed(tweet_id: str, reimport_marker, processed_tweet_ids: set):
    """Records the thread as processed, without writing an ID twice."""
    for entry_id in (tweet_id, reimport_marker):
        if entry_id and entry_id not in processed_tweet_ids:
            save_processed_tweet_id(entry_id)
            processed_tweet_ids.add(entry_id)


def process_single_thread(thread: list, processed_tweet_ids: set, force_reimport: bool = False):
    """Processes a single thread, prepares Day One entry data, and adds the post.

    With force_reimport, the thread is imported even if it was imported before —
    used for threads that grew since their last import. Returns a dict describing
    the created entry, or None if nothing was posted.
    """
    first_tweet_in_thread = thread[0]['tweet']
    tweet_id = first_tweet_in_thread['id_str']

    if tweet_id in processed_tweet_ids and not force_reimport:
        print(f"Skipping already processed tweet ID: {tweet_id}")
        return None

    # A re-imported thread is tracked by "<root id>+<last tweet id>", so running the
    # same date range twice doesn't import the same extension over and over.
    reimport_marker = extension_marker(thread) if force_reimport else None
    if reimport_marker:
        if reimport_marker in processed_tweet_ids:
            print(f"Skipping thread {tweet_id}: its extension was already imported.")
            return None
        print(f"\nRe-importing thread {tweet_id}: it was extended within the date range.")

    category = get_thread_category(thread)
    display_thread_details(thread, category)

    entry_text, entry_tags, entry_media_files, entry_date_time, entry_coordinate = aggregate_thread_data(thread)
    
    title = generate_entry_title(entry_text, category, len(thread), entry_media_files)
    entry_text = build_entry_content(entry_text, first_tweet_in_thread, category, title)

    target_journal = get_target_journal(category, tweet_id)
    if target_journal is None:
        _remember_processed(tweet_id, reimport_marker, processed_tweet_ids) # Mark as processed even if skipped
        return None

    if add_post(
        text=entry_text,
        journal=target_journal,
        tags=list(set(entry_tags)),
        date_time=entry_date_time,
        coordinate=entry_coordinate,
        attachments=entry_media_files
    ):
        _remember_processed(tweet_id, reimport_marker, processed_tweet_ids)
        return {
            "tweet_id": tweet_id,
            "title": title,
            "category": category,
            "journal": target_journal,
            "date": entry_date_time,
            "tweet_count": len(thread),
        }

    return None


def write_reimport_report(report: str):
    """Prints the delete-the-duplicates reminder and saves it for later reference."""
    print("\n" + report)
    with open(DUPLICATES_FILE_PATH, "w") as f:
        f.write(report)
    print(f"Saved this reminder to {DUPLICATES_FILE_PATH}")
