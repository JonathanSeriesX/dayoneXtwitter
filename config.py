import os

"""
Configuration settings for the Day One Twitter integration.
Defines paths to the Twitter archive and Day One journal details.
"""

script_dir = os.path.dirname(os.path.abspath(__file__))
TWEET_ARCHIVE_PATH = os.path.join(script_dir, "archive", "data", "tweets.js")
STATUSES_FILE_PATH = os.path.join(script_dir, "statuses.txt") # Path to store processed tweet IDs


JOURNAL_NAME = "Twitter Test"
REPLY_JOURNAL_NAME = "Twitter Replies Test" # Set to a journal name (e.g., "Twitter Replies") to post replies there, or None to ignore them
CURRENT_USERNAME = "JonathanSeriesX" # Set to yours, otherwise links will break
MAX_THREADS_TO_PROCESS = 30 # Set to an integer to limit the number of threads processed, or None for no limit
SHUFFLE_MODE = True # Otherwise, we start with the oldest one
IGNORE_RETWEETS = False

# LLM Configuration for Ollama
PROCESS_TITLES_WITH_LLM = True # Set to True to enable LLM-based title generation
OLLAMA_API_URL = os.getenv("OLLAMA_API_URL", "http://localhost:11434/api/generate")
OLLAMA_MODEL_NAME = os.getenv("OLLAMA_MODEL_NAME", "llama3.1") # Default is llama3.1, can be configured
OLLAMA_PROMPT = ("Figure out, what subject this tweet is about. Deliver very short answer in lowercase, "
                 "like \"about weather\" or \"about Formula 1\". "
                 "Only output few lowercase words, nothing else.") # tweet itself comes right afterwards
