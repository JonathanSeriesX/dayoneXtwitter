import os
import glob
import re
import json


def replace_links_and_attach_media(tweet, media_directory="archive/data/tweets_media"):
    tweet_content = tweet["tweet"]["full_text"]

    # Extract URLs and media from the tweet entities
    urls = tweet["tweet"].get("entities", {}).get("urls", [])
    media = tweet["tweet"].get("extended_entities", {}).get("media", [])
    media_files = []

    # Process each URL
    for url_info in urls:
        tco_url = url_info["url"]
        expanded_url = url_info["expanded_url"]

        # Replace the t.co link with expanded URL if it’s a standard link
        tweet_content = tweet_content.replace(tco_url, expanded_url)

    # Process each media item (remove t.co links for media, attach local files)
    for media_info in media:
        tco_url = media_info["url"]
        media_url = media_info["media_url"]
        media_id = media_info["id_str"]

        # Replace the t.co link with an empty string for media
        tweet_content = tweet_content.replace(tco_url, "")

        # Find the local media file that starts with the tweet ID
        pattern_jpg = os.path.join(
            media_directory, f"{tweet['tweet']['id']}-{media_id}*.jpg"
        )
        pattern_png = os.path.join(
            media_directory, f"{tweet['tweet']['id']}-{media_id}*.png"
        )

        jpg_files = glob.glob(pattern_jpg)
        png_files = glob.glob(pattern_png)

        # Add found files to media_files list
        media_files.extend(jpg_files + png_files)

    # Clean up any remaining whitespace
    tweet_content = re.sub(r"\s+", " ", tweet_content).strip()

    # tweet

    return tweet_content, media_files


def save_tweet_to_json(tweet, output_directory="tweets_json"):
    """Saves tweet data to a JSON file named <tweet_id>.json."""
    # Ensure the output directory exists
    os.makedirs(output_directory, exist_ok=True)

    # Extract tweet_id and construct the file path
    tweet_id = tweet["tweet"]["id_str"]  # Assumes 'id_str' is always present
    file_path = os.path.join(output_directory, f"{tweet_id}.json")

    # Write tweet data to JSON file
    with open(file_path, "w", encoding="utf-8") as json_file:
        json.dump(tweet, json_file, ensure_ascii=False, indent=4)

    print(f"Tweet saved to {file_path}")
