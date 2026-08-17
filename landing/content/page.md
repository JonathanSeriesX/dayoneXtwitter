Everything the site says lives in this file. Plain Markdown, no JSX — see
`app/markdown.tsx` for how each construct is dressed up:

    text before the first `##`   the hero tagline
    ## Heading {badge}           one collapsible glass section; the braces are optional
    - bullet                     dash-in-the-margin list, nests one level
    1. step                      numbered circle beside the text
    `code`                       monospace span
    ```fenced```                 terminal card with a copy button
    > quote                      dashed callout box
    ### Heading                  a named block inside a section, with a rule above it
    ![alt](pics/shot.png)        screenshot; the file must be registered in app/markdown.tsx

---

The **ultimate** tool to seamlessly import your Twitter archive into the
[Day One](https://dayoneapp.com) journaling app.

## What for?

By importing your Twitter archive into Day One, you can:

- Browse your entire tweet history offline with lightning-fast random access
- Rediscover what you posted “on this day“ in past years—like
  [Timehop](https://www.timehop.com), but nicer and with no limitations
- Browse all your tweeted photos and videos in a sleek, organized gallery
- Perform full-text searches that actually work
  - Easily purge any unwanted
    [kompromat](https://en.wikipedia.org/wiki/Kompromat) from your old tweets

![A thread combined into a single Day One entry](pics/threads.png)

## What's so good about it?

- Beautifully classifies pure tweets, threads, retweets, quote-tweets, replies,
  etc., and acts accordingly
- Handles threads _gracefully_ and combines them into single, cohesive Day One
  entries
- Supports media attachments, hashtags, locations
- Appends like/retweet count under each tweet
- Remembers what it already imported — run it again next year with a fresh
  archive and only the new tweets get imported
- Titles your entries with a local LLM via [Ollama](https://ollama.com) —
  “Wrote about Formula 1”, “Expressed frustration at airport security”, etc.

![Twitter replies imported into Day One](pics/replies.png)

## Preparation {one-time}

Requirements:

- macOS Sequoia or newer. If you don't have a Mac, find a friend who does or
  spin up a virtual machine.
- [Day One Silver](https://dayoneapp.com/plans/) subscription for more than one
  attachment per entry (free trial available, feel free to cancel it right after
  the import)

Then:

1. **Download** your **[Twitter data](https://x.com/settings/download_your_data)**. It will be delivered to your email within 24 hours.
2. **Install** the **[Day One app](https://apps.apple.com/tr/app/day-one/id1055511498?mt=12)** and its
   **[command-line tool](https://dayoneapp.com/guides/day-one-for-mac/command-line-interface-cli/)**, open the app, and (optionally) sign in.
3. Go to [dayone://preferences](dayone://preferences)
   → Journals, and **create two journals**: `Tweets` and `Twitter Replies`.
4. (Optional) **Pause sync** in Day One preferences if you're on a
   metered connection. You can turn it back on once the import is done.
5. **Install Ollama** on your Mac by executing following command in your terminal:

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

6. **Install an LLM model** to process titles for your threads.

```bash
## For ~16gb Macs:
ollama pull qwen3.5:9b-mlx &&
ollama serve
```

```bash
## For ~32gb Macs:
ollama pull qwen3.5:27b-mlx &&
ollama serve
```

Note: when the model can't tell what a tweet is about, the title stays a plain
“Tweeted”. Delete the model afterwards with `ollama rm qwen3.5:9b-mlx` to
reclaim the storage space.

## Usage {4 steps}

1. **Download** the latest `Twixodus.zip` from
   [Releases](https://github.com/JonathanSeriesX/twixodus/releases).
2. **Launch Twixodus** and drop your `twitter-….zip` (or the unpacked folder)
   onto the window.
3. **Walk through the settings** — journals, date range, whether your account
   still exists — and press **Start Import**. You can pause or cancel any time;
   the ledger remembers every imported thread, so the next run picks up where you
   left off.
4. **Keep the Day One app running** during the import: it's what moves the staged
   media into the entries.

> The build isn't notarized yet, so the very first launch needs one trip to
> System Settings → **Privacy & Security** → **Open Anyway**. After that it opens
> like any other app.

## 🥺👉👈

If you found this useful, please consider supporting me:

- [Buy me a coffee](https://coff.ee/jonathunky)
- USDT TRC20: `TKa6wmqpLvMQwacU1wnPgFWZHFaDRV9jFs`

<!-- Parked, not deleted — the README still carries both lists. Move either
     heading above this comment to put it back on the page.

## Known issues

- Recent Day One CLI versions are sandboxed and can only read attachment files
  from inside Day One's own container. The app handles this transparently by
  staging each entry's media there before import (and cleaning up after). Keep
  the Day One app running during the import: the app is what moves staged media
  into the entries, so with the app closed the images appear only after you next
  open it.
- Retweets of long tweets do not contain media;
  [see example](https://x.com/JonathanSeriesX/status/1436443683642122248). This
  is a limitation of Twitter Archive.
- Retweets longer than ~125 characters will be truncated with an ellipsis (`…`);
  this is also a limitation of the archive itself.
- Media thumbnails in Day One app may appear blank at first; they'll load once
  you switch to another window and then back.

## Plans {if the project gains traction and/or I have lots of spare time}

- Signed & notarized downloads
- Better LLM-based title generation
- Support for grouping relevant successive tweets into a single post (relevant
  for tweets posted before 2017, as there were no threads back then)

-->
