# Twixodus

The **ultimate** tool to seamlessly import your Twitter archive into the [Day One journaling app](https://dayoneapp.com).

Works on macOS Sequoia or newer.

## 🥺👉👈

If you found this useful, please consider supporting me:

- [Buy me a nice latte](https://ko-fi.com/jonathanx64)
- USDT TRC20: `TNhgaQw2n9WxsddLhaXnx1HvEEYsScmsrW`
- [Revolut](https://revolut.me/evgenii69)

I have to notarise this application under my friend's Apple ID, because I don't have access to Apple Developer Program; your donations could change that!

## Known limitations

- This app does not know how to process tweets longer than 280 characters, because I never used that feature. I need to get my hands on someone else's archive with a non-empty `note-tweet.js` file…
- In an archive, retweets of long tweets do not contain media; [see example](https://x.com/JonathanSeriesX/status/1436443683642122248). Twixodus will try to retrieve them online.
- In an archive, retweets longer than ~125 characters are truncated with an ellipsis (`…`). Twixodus will try to retrieve them online.
- Recent Day One CLI versions are sandboxed and can only read attachment files from inside Day One's own container. The app handles this transparently by staging each entry's media there before import (and cleaning up after). Keep the Day One app running during the import: the app is what moves staged media into the entries.
- Media thumbnails in Day One app may appear blank at first; they’ll load up once you switch to another window and then back.

## Plans

- Support for processing long tweets
- More precise LLM-based title generation
