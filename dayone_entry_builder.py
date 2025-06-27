import re
from datetime import datetime

import config
from llm_analyzer import get_tweet_summary

def escape_md(text: str) -> str:
    # 1) Handle line-start markers
    lines = []
    for line in text.splitlines():
        if line.startswith("# "):
            # escape real Markdown heading, not hashtags like "#AI"
            line = "\\" + line
        elif line and line[0] in ("-", "+", ">"):
            # escape lists & blockquotes
            line = "\\" + line
        lines.append(line)
    escaped = "\n".join(lines)

    # 2) Escape inline markdown chars
    for ch in ("*", "`", "|", "!"):
        escaped = escaped.replace(ch, "\\" + ch)

    return escaped

def aggregate_thread_data(thread: list):
    """Aggregates text, tags, media files, date, and coordinates from a thread."""
    entry_text = ""
    entry_tags = []
    entry_media_files = []
    entry_date_time = None
    entry_coordinate = None

    for tweet_in_thread in thread:
        tweet_data = tweet_in_thread['tweet']
        entry_text += tweet_data['full_text'] + "\n\n"

        tweet_url = f"https://twitter.com/{config.CURRENT_USERNAME}/status/{tweet_data['id_str']}"
        metrics = []
        likes = int(tweet_data["favorite_count"])
        rts = int(tweet_data["retweet_count"])

        if likes > 0:
            metrics.append(f"[Likes: {likes}]({tweet_url}/likes) ⭐️")
        if rts > 0:
            metrics.append(f"[Retweets: {rts}]({tweet_url}/retweets) 🔁")
        
        metrics.append(f"[Open on twitter.com]({tweet_url})")

        entry_text += "   ".join(metrics) + "\n"
        entry_text += "___\n"

        if tweet_data["entities"].get("hashtags"):
            for hashtag in tweet_data["entities"]["hashtags"]:
                entry_tags.append(hashtag['text'])

        if tweet_data.get("media_files"):
            for media_file in tweet_data["media_files"]:
                entry_media_files.append(media_file)

        if not entry_date_time:
            try:
                entry_date_time = datetime.strptime(tweet_data['created_at'], "%a %b %d %H:%M:%S %z %Y")
            except ValueError:
                print(f"Warning: Could not parse date {tweet_data['created_at']}")
                entry_date_time = None

        if not entry_coordinate and tweet_data.get("coordinates") and tweet_data["coordinates"].get("coordinates"):
            longitude = tweet_data["coordinates"]["coordinates"][0]
            latitude = tweet_data["coordinates"]["coordinates"][1]
            entry_coordinate = (latitude, longitude)
    
    return entry_text, entry_tags, entry_media_files, entry_date_time, entry_coordinate



def generate_entry_title(entry_text: str, category: str, thread_length: int):
    """Generates the title for the Day One entry, optionally using an LLM."""
    if config.PROCESS_TITLES_WITH_LLM and thread_length > 1: # we only process threads
        llm_summary = get_tweet_summary(entry_text)
        # TODO debug
        print("Summary: " + llm_summary)
        if llm_summary != "Uncategorized" and llm_summary != "About":
            return f"A thread {llm_summary}"
    return category


def build_entry_content(entry_text: str, first_tweet: dict, category: str, title: str):
    """Constructs the final text content for the Day One entry."""
    if first_tweet.get("in_reply_to_status_id_str"):
        mentions = re.findall(r"@\w+", entry_text)
        rest = re.sub(r"(?:@\w+\s*)+", "", entry_text).strip()
        mentions_str = " ".join(mentions)
        entry_text = f"{rest}\n\n"
        reply_to_tweet_id = first_tweet["in_reply_to_status_id_str"]
        reply_to_url = f"https://twitter.com/i/web/status/{reply_to_tweet_id}"
        entry_text += f"In [response]({reply_to_url}) to {mentions_str}\n"

    entry_text = escape_md(entry_text) # anti-Markdown pass
    entry_text = f"# {title}\n\n{entry_text}\n\n"

    return entry_text


def get_target_journal(category: str, tweet_id: str):
    """Determines the target journal for the Day One entry."""
    target_journal = config.JOURNAL_NAME
    if category.startswith("Replied to"):
        if config.REPLY_JOURNAL_NAME is not None:
            target_journal = config.REPLY_JOURNAL_NAME
        else:
            print(f"Skipping reply thread {tweet_id} as REPLY_JOURNAL_NAME is not set.")
            return None
    if category.startswith("Retweet"):
        if config.IGNORE_RETWEETS:
            print(f"Skipping retweet {tweet_id} as IGNORE_RETWEETS is enabled.")
            return None
    return target_journal
