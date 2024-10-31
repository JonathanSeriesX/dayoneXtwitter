# twitter_client.py
import os
import requests
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Get the Bearer Token from environment variables
BEARER_TOKEN = os.getenv("TWITTER_BEARER_TOKEN")


def get_tweets(query, max_results=10):
    """Retrieve tweets based on a search query."""
    url = "https://api.twitter.com/2/tweets/search/recent"
    headers = {
        "Authorization": f"Bearer {BEARER_TOKEN}"
    }
    params = {
        "query": query,
        "max_results": max_results
    }
    response = requests.get(url, headers=headers, params=params)

    if response.status_code == 200:
        return response.json()
    else:
        print("Error:", response.status_code, response.json())
        return None