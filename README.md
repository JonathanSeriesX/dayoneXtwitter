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

9. **Important**  
   Set your device time zone to GMT+0 or UTC before launching the script. It's a known bug with dayone2 CLI tool. I've reached out to Automattic, maybe it will be fixed at some point.  


Now launch the script and enjoy! (:

---

#### Notes

- The free version of Day One supports only one attachment per entry. Subscribe for a Premium ¯\\_(ツ)_/¯ (there is a free trial option)
- This only works on macOS. If you don't have a Mac, find a friend who does or spin up the virtual machine. 
- Media thumbnails in Day One app may appear blank at first; they’ll load once you switch to another window and then back.  
- Retweets longer than ~125 characters will be truncated with an ellipsis (`…`); this is a limitation of Twitter Archive.  
- The script tracks which tweets have been added to avoid duplicate posts in Day One.

TODO I don't care what the billionaire thinks

TODO LLM summaries

TODO loicensing

TODO GMT bug

#### Known issues:
- Short links to media sites such as youtu.be are being un-Markdowned by Day One app. I've reached out to the team in hopes they'll fix this.
- Retweets of long tweets do not contain media; [see example](https://x.com/JonathanSeriesX/status/1436443683642122248). There is no way around it.
