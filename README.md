## LeavingwithaBang (naming in progress)

The **ultimate** tool to seamlessly import your Twitter archive into the [Day One diary app](https://dayoneapp.com)! 

<img src="pic_related.jpeg" alt="Intro" width="400"/>

---

### Caveats

- Day One’s free plan lets you add just one attachment per entry. Subscribe to Premium ¯\\_(ツ)\_/¯ (free trial available, feel free to cancel it right afterwards)
- This script only works on macOS Sonoma and newer, because it relies on [dayone2 CLI tool](https://dayoneapp.com/guides/day-one-for-mac/command-line-interface-cli/). If you don't have a Mac, find a friend who does or spin up the virtual machine.

---

### Usage

1. **Download your Twitter data**  
   Request your archive [here](https://x.com/settings/download_your_data).

2. **If you haven’t used Day One before:**  
   - Install Day One app from the [App Store](https://apps.apple.com/tr/app/day-one/id1055511498?mt=12).  
   - Open it and (optionally) sign in.

3. **Install the Day One CLI**  
   Follow the [instructions](https://dayoneapp.com/guides/day-one-for-mac/command-line-interface-cli/)

4. **Create a journal for tweets**  
   Go to [dayone://preferences](dayone://preferences), open **Journals**, and add one named `Tweets` (or see [config options](#config-options)).

5. **(Optional) Create a journal for replies**  
   If you want to include replies, add another journal called `Twitter Replies` (or see [config options](#config-options)).

6. **(Optional) Pause sync**  
   Day One will attempt to sync new posts into cloud automatically. If you're using unreliable or metered connection, you might want to visit Day One preferences → **Sync**, and click **Pause sync for 24 hours**.

7. **Extract your archive**  
   Place the `twitter~.zip` file in this project folder and unzip it.

8. **Important**  
   Set your device time zone to GMT+0 or UTC before launching the script; it's a known bug with dayone2 CLI tool. I've reached out to Automattic, maybe it will be fixed at some point.

9. **(Optional) enable naming of threads by LLM**
   ```bash
   brew install ollama
   ollama pull llama3.1
   ollama serve
   ```
   - Will produce results such as “a thread about Formula 1“ or “a thread about second-hand shopping“.
   - Should run fast if you have an M-series processor and 16 GB+ of RAM.
   - Downloads about 5 gb of data, so be mindful of metered connections.

10. Modify configuration and launch the script!

### Config options

Before launching the script, it's important to set `CURRENT_USERNAME` in `config.py` to your most recent Twitter username, or to None if you're going to delete your account forever.

Feel free to adjust other options as well, such as:

- Journal names
- Tweet processing date range
- Option to ignore retweets

Now execute the `launch.sh` and enjoy! (:

---

### Known issues

- Some links (e.g. `youtu.be`, `instagram.com`) are being un-Markdowned by Day One app. I've reached out to Automattic about this, too.
- Retweets of long tweets do not contain media; [see example](https://x.com/JonathanSeriesX/status/1436443683642122248). This is a limitation of Twitter Archive.
- Retweets longer than ~125 characters will be truncated with an ellipsis (`…`); this is also a limitation of archive itself.
- Media thumbnails in Day One app may appear blank at first; they’ll load once you switch to another window and then back.  

### Plans

- Better packaging
- Support for threads with more than 30 photos inside 
  - Day One limitation, but it can be avoided by splitting long threads with many attachments into multiple posts
