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
        elif line and line[0] in ("-", "+", "*", ">"):
            # escape lists & blockquotes
            line = "\\" + line
        lines.append(line)
    escaped = "\n".join(lines)

    # 2) Escape inline markdown chars
    for ch in ("*", "_", "`", "|", "!", "[", "]", "(", ")"):
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
        entry_text += tweet_in_thread['tweet']['full_text'] + "\n\n"

        if tweet_in_thread["tweet"]["entities"].get("hashtags"):
            for hashtag in tweet_in_thread["tweet"]["entities"]["hashtags"]:
                entry_tags.append(hashtag['text'])

        if tweet_in_thread["tweet"]["media_files"]:
            for media_file in tweet_in_thread["tweet"]["media_files"]:
                entry_media_files.append(media_file)

        if not entry_date_time:
            try:
                entry_date_time = datetime.strptime(tweet_in_thread['tweet']['created_at'], "%a %b %d %H:%M:%S %z %Y")
            except ValueError:
                print(f"Warning: Could not parse date {tweet_in_thread['tweet']['created_at']}")
                entry_date_time = None

        if not entry_coordinate and tweet_in_thread["tweet"].get("coordinates") and tweet_in_thread["tweet"]["coordinates"].get("coordinates"):
            longitude = tweet_in_thread["tweet"]["coordinates"]["coordinates"][0]
            latitude = tweet_in_thread["tweet"]["coordinates"]["coordinates"][1]
            entry_coordinate = (latitude, longitude)
    
    return entry_text, entry_tags, entry_media_files, entry_date_time, entry_coordinate


def generate_entry_title(entry_text: str, category: str, thread_length: int):
    """Generates the title for the Day One entry, optionally using an LLM."""
    if config.PROCESS_TITLES_WITH_LLM and thread_length > 1:
        llm_summary = get_tweet_summary(entry_text).lower()
        if llm_summary != "Uncategorized":
            if category == "My tweet":
                title = f"A tweet about {llm_summary}"
            elif category == "My thread":
                title = f"A thread about {llm_summary}"
            else:
                title = f"{category} about {llm_summary}"
        else:
            title = f"{category}"
    else:
        title = f"{category}"
    return title


def build_entry_content(entry_text: str, first_tweet: dict, category: str, title: str):
    """Constructs the final text content for the Day One entry."""
    tweet_url = f"https://twitter.com/{config.CURRENT_USERNAME}/status/{first_tweet['id_str']}"
    metrics = []
    likes = int(first_tweet["favorite_count"])
    rts = int(first_tweet["retweet_count"])

    if first_tweet.get("in_reply_to_status_id_str"):
        mentions = re.findall(r"@\w+", entry_text)
        rest = re.sub(r"(?:@\w+\s*)+", "", entry_text).strip()
        mentions_str = " ".join(mentions)
        rest = escape_md(rest)
        entry_text = f"{rest}\n\n"
        reply_to_tweet_id = first_tweet["in_reply_to_status_id_str"]
        reply_to_url = f"https://twitter.com/i/web/status/{reply_to_tweet_id}"
        entry_text += f"In [response]({reply_to_url}) to {mentions_str}\n"

    if likes > 0:
        metrics.append(f"[Likes: {likes}]({tweet_url}/likes) ⭐️")
    if rts > 0:
        metrics.append(f"[Retweets: {rts}]({tweet_url}/retweets) 🔁")

    if metrics:
        entry_text += "   ".join(metrics) + "\n"

    # Add a footer with a direct link to the tweet on twitter.com.
    entry_text += f"___\nOpen on [twitter.com]({tweet_url})\n"

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
        if not config.IGNORE_RETWEETS:
            print(f"Skipping retweet {tweet_id} as IGNORE_RETWEETS is enabled.")
            return None
    return target_journal
