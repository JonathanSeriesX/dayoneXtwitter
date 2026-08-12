JOURNAL_NAME = "Tweets Test"
REPLY_JOURNAL_NAME = (
    "Twitter Replies Test"  # Journal for replies, or None to skip replies altogether
)
CURRENT_USERNAME = "JonathanSeriesX"  # Set to your current username. Or set to None if you've deleted your Twitter account forever.
MAX_THREADS_TO_PROCESS = None  # Max threads to process, or None for no limit
SHUFFLE_MODE = True  # True to go over threads during import in a random order; False to start from oldest
IGNORE_RETWEETS = False  # True to skip retweets entirely
SHOW_TWEET_SOURCE = (
    True  # True to end entries with "Sent from <client>" (Twitter for Android, etc.)
)

# Date range for processing tweets. Only threads started between these two dates will be processed.
# Format: "DD Month YYYY" (e.g., "21 March 2006")
START_DATE = "29 June 2025"
END_DATE = "20 April 2069"

# LLM Configuration for Ollama
PROCESS_TITLES_WITH_LLM = True  # Enable LLM-generated titles
LLM_TITLES_FOR_SINGLE_TWEETS = True  # Also title standalone tweets, not just threads
LLM_MAX_IMAGES = (
    26  # How many attached images to show the LLM per entry (0 to disable vision)
)
OLLAMA_HOST = "http://localhost:11434"  # Base URL of the Ollama server
OLLAMA_MODEL_NAME = "qwen3.5:9b-mlx"  # Or "qwen3.5:4b-mlx" on Macs with less memory
OLLAMA_TIMEOUT = (
    60  # Seconds to wait for a title; the first request also loads the model
)

OLLAMA_TITLE_PROMPT = """You are titling entries in a personal journal built from the author's old tweets.
Write a title for the tweet below: one short action phrase, 3 to 8 words, past tense, describing what the author did or felt. Examples of good titles:
Wrote about Formula 1
Expressed frustration at airport security
Posted a meme about cats
Shared photos from a music festival
Complained about the weather
Rules: start with a past-tense verb, no period at the end, no quotes, no emoji.
You don't care if the tweet's language is different. 
Deliver answer in a beautiful natural British English.
Only state what you can actually see in the text or attached images; strive not to invent specifics.
If the tweet is too short, vague, or unclear to title honestly, reply with exactly: Tweeted
Here is the tweet:
"""  # Tweet content follows afterwards
