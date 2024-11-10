import os
import time

import requests

BEARER_TOKEN = os.getenv("TWITTER_BEARER_TOKEN")
API_URL = "https://api.twitter.com/2/tweets"
IMAGE_DIR = "downloaded_images"

# Ensure the directory for images exists
os.makedirs(IMAGE_DIR, exist_ok=True)


def fetch_tweet_content_and_images(tweet_id):
    """Fetches tweet content and downloads images if available."""
    url = f"{API_URL}/{tweet_id}"
    headers = {"Authorization": f"Bearer {BEARER_TOKEN}"}
    params = {"expansions": "attachments.media_keys", "media.fields": "url"}
    response = requests.get(url, headers=headers, params=params)

    if response.status_code == 200:
        tweet_data = response.json()
        tweet_text = tweet_data["data"]["text"]
        print(f"Tweet content: {tweet_text}")

        # Handle media if present
        media_urls = []
        if "includes" in tweet_data and "media" in tweet_data["includes"]:
            for media in tweet_data["includes"]["media"]:
                if media["type"] == "photo":
                    media_urls.append(media["url"])

        # Download each image
        for i, media_url in enumerate(media_urls, start=1):
            download_image(media_url, f"{tweet_id}_{i}.jpg")

        return tweet_text
    elif response.status_code == 429:  # Rate limit hit
        print("Rate limit exceeded. Sleeping for 15 minutes...")
        time.sleep(15 * 60)
        return fetch_tweet_content_and_images(tweet_id)
    else:
        print(
            f"Failed to fetch tweet {tweet_id}: {response.status_code} - {response.text}"
        )
        return None


def download_image(url, filename):
    """Downloads an image from a URL."""
    response = requests.get(url)
    if response.status_code == 200:
        file_path = os.path.join(IMAGE_DIR, filename)
        with open(file_path, "wb") as f:
            f.write(response.content)
        print(f"Downloaded image: {file_path}")
    else:
        print(f"Failed to download image: {url}")
