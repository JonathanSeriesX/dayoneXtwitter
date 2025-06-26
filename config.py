import os

"""
Configuration settings for the Day One Twitter integration.
Defines paths to the Twitter archive and Day One journal details.
"""

script_dir = os.path.dirname(os.path.abspath(__file__))
TWEET_ARCHIVE_PATH = os.path.join(script_dir, "archive", "data", "tweets.js")
JOURNAL_NAME = "Twitter Replies Test"
CURRENT_USERNAME = "JonathanSeriesX"
PROCESS_TITLES_WITH_LLM = True # Set to True to enable LLM-based title generation
STATUSES_FILE_PATH = os.path.join(script_dir, "statuses.txt") # Path to store processed tweet IDs
MAX_THREADS_TO_PROCESS = 120 # Set to an integer to limit the number of threads processed, or None for no limit
