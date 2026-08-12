import os

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


IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".gif", ".webp")


def _generate(prompt: str, images=None) -> str:
    """Runs one completion, retrying without the thinking flag if the model
    doesn't support it."""
    global _disable_thinking

    options = {
        "num_predict": 24,  # A title is a few words; don't let it ramble
        "temperature": 0.3,  # Keep it low for more deterministic output
        "num_ctx": 8192,  # Attached images consume context too
    }

    try:
        response = _get_client().generate(
            model=config.OLLAMA_MODEL_NAME,
            prompt=prompt,
            images=images or None,
            options=options,
            **({"think": False} if _disable_thinking else {}),
        )
    except ollama.ResponseError as e:
        if _disable_thinking and "does not support thinking" in str(e).lower():
            _disable_thinking = False
            return _generate(prompt, images)
        raise

    return response.response.strip()


def _pick_images(media_files) -> list:
    """Selects up to LLM_MAX_IMAGES existing image attachments (videos and
    missing files are skipped) to show the model alongside the tweet text."""
    limit = getattr(config, "LLM_MAX_IMAGES", 4)
    images = []
    for path in media_files or []:
        if len(images) >= limit:
            break
        if path.lower().endswith(IMAGE_EXTENSIONS) and os.path.exists(path):
            images.append(path)
    return images


def _normalize_title(raw: str):
    """Cleans up a model-produced title; returns None when the model declined
    ('Tweeted') or produced something that doesn't look like a title."""
    title = raw.strip().strip('"“”\'').rstrip(".").strip()
    title = title.splitlines()[0].strip() if title else ""

    if not title or title.lower() == "tweeted":
        return None
    # A real title is a short phrase; anything longer is the model rambling.
    if len(title) > 64 or len(title.split()) > 10:
        return None
    return title[0].upper() + title[1:]


def generate_llm_title(tweet_text: str, media_files=None):
    """
    Produces a journal-entry title for a tweet or thread using a local LLM via
    Ollama — an action phrase such as "Expressed frustration at airport
    security" or "Posted a meme about cats". Image attachments are shown to the
    model when it supports vision.

    Args:
        tweet_text: The aggregated text of the tweet or thread.
        media_files: Optional list of attachment paths; images among them add context.

    Returns:
        The title string, or None when no confident title could be produced
        (the model answered "Tweeted", returned junk, or Ollama failed).
    """
    prompt = f"{config.OLLAMA_TITLE_PROMPT}\n\nTweet: {tweet_text}\nTitle:"
    images = _pick_images(media_files)

    try:
        return _normalize_title(_generate(prompt, images))

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

    return None
