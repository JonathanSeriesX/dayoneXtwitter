## LeavingWithaBang

The **ultimate** tool that perfectly moves your Twitter Archive → Day One diary app on macOS!

#TODO I don't care what the billionaire think

How to:

1. Download your data from Twitter [here](https://x.com/settings/download_your_data?lang=en)

If you never used Day One:

* Install Day One from [the App Store](https://apps.apple.com/tr/app/day-one/id1055511498?mt=12)
* Open Day One app and initialise it (sign in to your account, etc.)

2. Install Day One CLI https://dayoneapp.com/guides/day-one-for-mac/command-line-interface-cli/
3. Visit [dayone://preferences](dayone://preferences) and create a new journal called “Tweets”.
4. If you want to also have replies, create new journal called “Twitter Replies”.
5. While at it, in preferences, go to Sync tab and PAUSE SYNC!
6. Put your twitter~.zip file in the project folder, extract zip file.
7. Adjust config.py as desired.

Notes:

* If you're using a free version of Day One, it only supports one attachment per post. I've tried to handle this situation as gracefully as possible.
* Day One does not accept some videos and gifs (which are actually videos). No idea why. I'll reach out to the team about this at some point.
* This is only possible on macOS. If you don't have it, find a friend who does or spin up the virtual machine.
* Media uploads in Day One app are not instant. It's normal to see blank thumbnails at first. They will resolve quickly into actual media.
* Retweets of long tweets (longer than ~125 symbols) will be cut and will end up with …. I can't do anything about it. For now.
