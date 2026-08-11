JOURNAL_NAME = "Tweets Test"
REPLY_JOURNAL_NAME = (
    "Twitter Replies Test"  # Journal for replies, or None to skip replies altogether
)
CURRENT_USERNAME = "JonathanSeriesX"  # Set to your current username. Or set to None if you've deleted your Twitter account forever.
MAX_THREADS_TO_PROCESS = None  # Max threads to process, or None for no limit
SHUFFLE_MODE = True  # True to go over threads during import in a random order; False to start from oldest
IGNORE_RETWEETS = False  # True to skip retweets entirely

# Date range for processing tweets. Only threads started between these two dates will be processed.
# Format: "DD Month YYYY" (e.g., "21 March 2006")
START_DATE = "29 June 2025"
END_DATE = "20 April 2069"

# True to also re-import, in full, threads that started before START_DATE but were
# extended within the date range. Day One can't extend an existing entry, so you'll
# be asked to delete the older, shorter copy of each such thread by hand.
REIMPORT_EXTENDED_THREADS = True

# LLM Configuration for Ollama
PROCESS_TITLES_WITH_LLM = True  # Enable LLM-generated titles
OLLAMA_HOST = "http://localhost:11434"  # Base URL of the Ollama server
OLLAMA_MODEL_NAME = "qwen3.5:9b-mlx"  # Or "qwen3.5:4b-mlx" on Macs with less memory
OLLAMA_TIMEOUT = 60  # Seconds to wait for a title; the first request also loads the model

OLLAMA_PROMPT = (
    "Figure out, what subject this tweet is about. Deliver very short answer, "
    "like 'about weather' or 'about Formula 1'. "
    "First word must be in lowercase. No period in the end."
)  # Tweet content follows afterwards
