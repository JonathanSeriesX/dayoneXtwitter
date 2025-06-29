import os

TWEET_ARCHIVE_PATH = "archive/data/tweets.js"
STATUSES_FILE_PATH = "statuses.txt"

JOURNAL_NAME = "Tweets"
REPLY_JOURNAL_NAME = "Twitter Replies"  # Set to a journal name (e.g., "Twitter Replies") to post replies there, or None to ignore replies altogether
CURRENT_USERNAME = "JonathanSeriesX"  # Set to yours, otherwise links will break
MAX_THREADS_TO_PROCESS = None  # Set to an integer to limit the number of threads processed, or None for no limit
SHUFFLE_MODE = True  # Otherwise, we start from the oldest one
IGNORE_RETWEETS = False

# Date range for processing tweets. Only threads started between these two dates will be processed.
# Format: "DD Month YYYY" (e.g., "21 March 2006")
START_DATE = "20 March 2006"
END_DATE = "20 April 2069"


# LLM Configuration for Ollama
PROCESS_TITLES_WITH_LLM = True  # Set to True to enable LLM-based title generation
OLLAMA_API_URL = os.getenv("OLLAMA_API_URL", "http://localhost:11434/api/generate")
OLLAMA_MODEL_NAME = os.getenv(
    "OLLAMA_MODEL_NAME", "llama3.1"
)
OLLAMA_PROMPT = (
    "Figure out, what subject this tweet is about. Deliver very short answer in lowercase, "
    'like "about weather" or "about Formula 1". '
    "Only output few lowercase words, nothing else."
)  # the tweet itself comes right afterwards
