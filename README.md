## LeavingWithaBang

The **ultimate** tool to seamlessly import your Twitter archive into the Day One diary app on macOS!

### Usage

1. **Download your Twitter data**  
   Request your archive from Twitter [here](https://x.com/settings/download_your_data).

2. **If you haven’t used Day One before:**  
   - Install Day One app from the [App Store](https://apps.apple.com/tr/app/day-one/id1055511498?mt=12).  
   - Open it and (optionally) sign in.

3. **Install the Day One CLI**  
   Follow the [instructions](https://dayoneapp.com/guides/day-one-for-mac/command-line-interface-cli/)

4. **Create a journal for tweets**  
   Go to `dayone://preferences`, open **Journals**, and add one named `Tweets` (or see p.8).

5. **(Optional) Create a journal for replies**  
   If you want to include replies, add another journal called `Twitter Replies` (or see p.8).

6. **Pause sync**  
   In Day One preferences → **Sync**, click **Pause Sync**.

7. **Extract your archive**  
   Place the `twitter~.zip` file in your project folder and unzip it.

8. **Configure**  
   Edit `config.py` to suit your needs.

Now launch the script and enjoy! (:

---

#### Notes

- The free version of Day One supports only one attachment per entry. Consider using the Premium trial for full media support.  
- This only works on macOS. If you don’t have a Mac, ask a friend or run a macOS VM.  
- Initial media thumbnails may appear blank; they’ll load once you switch windows or restart Day One.  
- Retweets longer than ~125 characters will be truncated with an ellipsis (`…`); this is a Day One CLI limitation.  
- The script tracks which tweets have been added to avoid duplicates.