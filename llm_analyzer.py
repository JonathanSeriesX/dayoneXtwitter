import ollama

import config

# The client keeps a connection pool around, so it's built once and reused for
# every tweet instead of opening a fresh connection per summary.
_client = None

# Thinking models spend the whole token budget on the thought and return an empty
# answer, so thinking is switched off. Models that don't know the flag reject it
# outright; the first rejection flips this off and the summary is retried.
_disable_thinking = True


def _resolve_host() -> str:
    """
    Returns the base URL of the Ollama server.

    Configs written for the old requests-based code point at the /api/generate
    endpoint, which the client would append its own path to, so that suffix is
    trimmed off.
    """
    host = getattr(config, "OLLAMA_HOST", None) or getattr(config, "OLLAMA_API_URL", "")
    return host.split("/api/")[0]


def _get_client() -> ollama.Client:
    global _client
    if _client is None:
        _client = ollama.Client(
            host=_resolve_host() or None,  # None lets ollama use its own default host
            timeout=getattr(config, "OLLAMA_TIMEOUT", 60),
        )
    return _client


def _generate(prompt: str) -> str:
    """Runs one completion, retrying without the thinking flag if the model
    doesn't support it."""
    global _disable_thinking

    options = {
        "num_predict": 10,  # Limit output to a few tokens for a single word
        "temperature": 0.3,  # Keep it low for more deterministic output
        "num_ctx": 2048,  # To reduce RAM usage
    }

    try:
        response = _get_client().generate(
            model=config.OLLAMA_MODEL_NAME,
            prompt=prompt,
            options=options,
            **({"think": False} if _disable_thinking else {}),
        )
    except ollama.ResponseError as e:
        if _disable_thinking and "does not support thinking" in str(e).lower():
            _disable_thinking = False
            return _generate(prompt)
        raise

    return response.response.strip()


def get_tweet_summary(tweet_text: str) -> str:
    """
    Generates a one-word summary of the tweet text using a local LLM via Ollama.

    Args:
        tweet_text (str): The full text of the tweet to summarize.

    Returns:
        str: A one-word summary of the tweet, or "Uncategorized" if summarization fails.
    """

    prompt = f"{config.OLLAMA_PROMPT}\n\nTweet: {tweet_text}\nSummary:"

    try:
        summary = _generate(prompt)
        if summary:
            return summary  # .capitalize() # Capitalize for better titles
        print("Warning: Ollama returned an empty summary.")

    except ConnectionError:
        # Raised by the ollama client when the server can't be reached at all.
        print(
            f"Warning: Could not connect to Ollama at {_resolve_host()}. Is the Ollama server running?"
        )
    except ollama.ResponseError as e:
        print(
            f"Warning: Ollama refused the request: {e}. "
            f"Is the '{config.OLLAMA_MODEL_NAME}' model pulled?"
        )
    except ollama.RequestError as e:
        print(f"Warning: Malformed Ollama request: {e}")
    except Exception as e:
        # Covers read timeouts and anything else httpx may raise mid-request.
        print(f"An unexpected error occurred during LLM summarization: {e}")

    return "Uncategorized"  # Fallback summary
