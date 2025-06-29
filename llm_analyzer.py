import requests
import json
from config import OLLAMA_API_URL, OLLAMA_MODEL_NAME, OLLAMA_PROMPT

def get_tweet_summary(tweet_text: str) -> str:
    """
    Generates a one-word summary of the tweet text using a local LLM via Ollama.

    Args:
        tweet_text (str): The full text of the tweet to summarize.

    Returns:
        str: A one-word summary of the tweet, or "Uncategorized" if summarization fails.
    """

    ollama_url = OLLAMA_API_URL
    model_name = OLLAMA_MODEL_NAME

    prompt = f"{OLLAMA_PROMPT}\n\nTweet: {tweet_text}\nSummary:"

    headers = {"Content-Type": "application/json"}
    data = {
        "model": model_name,
        "prompt": prompt,
        "stream": False, # We want the full response at once
        "options": {
            "num_predict": 10, # Limit output to a few tokens for a single word
            "temperature": 0.3 # Keep it low for more deterministic output
        }
    }

    try:
        response = requests.post(ollama_url, headers=headers, data=json.dumps(data), timeout=30)
        response.raise_for_status() # Raise an HTTPError for bad responses (4xx or 5xx)
        
        result = response.json()
        summary = result.get("response", "").strip()

        if summary:
            return summary#.capitalize() # Capitalize for better titles
        
    except requests.exceptions.ConnectionError:
        print(f"Warning: Could not connect to Ollama at {ollama_url}. Is the Ollama server running?")
    except requests.exceptions.Timeout:
        print("Warning: Ollama request timed out.")
    except requests.exceptions.RequestException as e:
        print(f"Warning: An error occurred during Ollama request: {e}")
    except json.JSONDecodeError:
        print("Warning: Failed to decode JSON response from Ollama.")
    except Exception as e:
        print(f"An unexpected error occurred during LLM summarization: {e}")

    return "Uncategorized" # Fallback summary