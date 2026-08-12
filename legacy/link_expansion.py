"""Step 2 of the pipeline: clean up each tweet's text for Day One.

Twitter stores every link and media attachment in the text as an opaque
https://t.co/... URL. For each tweet, in place:

  * ordinary links become Markdown links to their real destination,
  * media links become Day One [{attachment}] placeholders, and the matching
    files from the archive's media folder are listed in tweet["media_files"],
  * truncated t.co links (from very old retweets) become "[link truncated]".
"""

from __future__ import annotations

import os
import re
from collections import defaultdict

from models import Tweet


def expand_links_in_tweet(tweet: Tweet, media_folder: str):
    """Rewrites one tweet's full_text as described above, in place.

    media_folder is the archive's tweets_media folder (see
    TwitterArchive.media_folder); the attachment paths point into it.
    """
    tweet_data = tweet.get("tweet")
    if not tweet_data:
        return

    full_text = tweet_data.get("full_text")
    entities = tweet_data.get("entities")
    tweet_id = tweet_data.get("id_str")

    if not all([full_text, entities, tweet_id]):
        return

    links_to_process = _collect_links(entities)
    media_by_tco = _collect_media(tweet_data, entities)

    processed_text = _replace_links_in_text(full_text, links_to_process, media_by_tco)
    processed_text, media_files = _replace_media_in_text(
        processed_text, media_by_tco, tweet_id, media_folder
    )

    tweet_data["full_text"] = processed_text.strip()
    tweet_data["media_files"] = media_files


def _collect_links(entities) -> list:
    """Pairs each non-media t.co URL with the Markdown link to replace it with."""
    links_to_process = []
    for url_entity in entities.get("urls", []):
        tco_url = url_entity.get("url")
        expanded_url = url_entity.get("expanded_url")
        display_url = url_entity.get("display_url")

        if tco_url and expanded_url:
            link_text = display_url if display_url else expanded_url
            links_to_process.append(
                {"tco_url": tco_url, "markdown_link": f"[{link_text}]({expanded_url})"}
            )
    return links_to_process


def _collect_media(tweet_data, entities) -> dict:
    """Maps each media t.co URL to its downloadable file(s): the direct image
    URL for photos, the highest-bitrate MP4 for videos and GIFs."""
    media_by_tco = defaultdict(list)
    media_entities = tweet_data.get("extended_entities", {}).get("media", [])
    if not media_entities:
        media_entities = entities.get("media", [])

    for media_entity in media_entities:
        tco_url = media_entity.get("url")
        media_type = media_entity.get("type")

        if tco_url:
            if media_type == "photo":
                media_url = media_entity.get("media_url_https")
                if media_url:
                    media_by_tco[tco_url].append(
                        {"media_url": media_url, "type": media_type}
                    )
            elif media_type in ("video", "animated_gif"):
                info = media_entity.get("video_info", {})
                variants = info.get("variants", [])
                mp4s = []
                for v in variants:
                    if v.get("content_type") == "video/mp4" and "bitrate" in v:
                        try:
                            v_bitrate = int(v["bitrate"])
                        except (TypeError, ValueError):
                            continue
                        mp4s.append((v_bitrate, v["url"]))
                if mp4s:
                    best_bitrate, best_url = max(mp4s, key=lambda x: x[0])
                    media_by_tco[tco_url].append(
                        {"media_url": best_url, "type": media_type}
                    )
    return media_by_tco


def _replace_links_in_text(text, links, media_map):
    processed_text = text
    # First, replace truncated t.co links with [link truncated]
    # This regex specifically targets t.co links followed by an ellipsis
    processed_text = re.sub(
        r"https?://t\.co/[A-Za-z0-9]+(?:\.\.\.|…)", "[link truncated]", processed_text
    )

    links.sort(key=lambda x: len(x["tco_url"]), reverse=True)
    for link_info in links:
        tco_url = link_info["tco_url"]
        if tco_url in media_map:
            continue
        markdown_link = link_info["markdown_link"]
        # Ensure we only replace the full, non-truncated t.co links here
        processed_text = re.sub(re.escape(tco_url), markdown_link, processed_text)
    return processed_text


def _replace_media_in_text(text, media_map, tweet_id, media_folder):
    processed_text = text
    media_files = []
    sorted_media_tco_urls = sorted(media_map.keys(), key=len, reverse=True)

    for tco_url in sorted_media_tco_urls:
        media_items = media_map[tco_url]
        attachment_placeholders = "".join(["[{attachment}]" for _ in media_items])
        processed_text = re.sub(
            re.escape(tco_url), attachment_placeholders, processed_text
        )

        for media_info in media_items:
            media_url = media_info["media_url"]
            media_filename = os.path.basename(media_url).split("?")[0]
            if media_info["type"] in ["video", "animated_gif"]:
                media_filename = os.path.splitext(media_filename)[0] + ".mp4"

            # Archived media files are named "<tweet id>-<original filename>".
            media_files.append(
                os.path.join(media_folder, f"{tweet_id}-{media_filename}")
            )

    return processed_text, media_files
