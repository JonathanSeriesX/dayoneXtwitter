import os

"""
Configuration settings for the Day One Twitter integration.
Defines paths to the Twitter archive and Day One journal details.
"""

script_dir = os.path.dirname(os.path.abspath(__file__))
TWEET_ARCHIVE_PATH = os.path.join(script_dir, "archive", "data", "tweets.js")
JOURNAL_NAME = "Twitter Replies Test"
CURRENT_USERNAME = "JonathanSeriesX"
STATUSES_FILE_PATH = os.path.join(script_dir, "statuses.txt") # Path to store processed tweet IDs
MAX_THREADS_TO_PROCESS = 35 # Set to an integer to limit the number of threads processed, or None for no limit

# LLM Configuration for Ollama
PROCESS_TITLES_WITH_LLM = True # Set to True to enable LLM-based title generation
OLLAMA_API_URL = os.getenv("OLLAMA_API_URL", "http://localhost:11434/api/generate")
OLLAMA_MODEL_NAME = os.getenv("OLLAMA_MODEL_NAME", "llama3.1") # Default to llama3.1, can be configured