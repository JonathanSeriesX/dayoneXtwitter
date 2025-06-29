import os

JOURNAL_NAME = "Tweets"
REPLY_JOURNAL_NAME = "Twitter Replies"  # Journal for replies, or None to skip replies altogether
CURRENT_USERNAME = "JonathanSeriesX"  # Set to your current username. Or set to None if you've deleted your Twitter account forever.
MAX_THREADS_TO_PROCESS = None  # Max threads to process, or None for no limit
SHUFFLE_MODE = True  # True to shuffle threads; False to start from oldest
IGNORE_RETWEETS = False # True to skip retweets entirely

# Date range for processing tweets. Only threads started between these two dates will be processed.
# Format: "DD Month YYYY" (e.g., "21 March 2006")
START_DATE = "20 March 2006"
END_DATE = "20 April 2069"

# LLM Configuration for Ollama
PROCESS_TITLES_WITH_LLM = True  # Enable LLM-generated titles
OLLAMA_API_URL = os.getenv("OLLAMA_API_URL", "http://localhost:11434/api/generate")
OLLAMA_MODEL_NAME = os.getenv(
    "OLLAMA_MODEL_NAME", "llama3.1"
)
OLLAMA_PROMPT = (
    "Figure out, what subject this tweet is about. Deliver very short answer, "
    "like 'about weather' or 'about Formula 1'. "
    "First word must be in lowercase. No period in the end."
)  # Tweet content follows afterwards
