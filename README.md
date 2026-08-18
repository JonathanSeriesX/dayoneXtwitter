# Twixodus

The **ultimate** tool to seamlessly import your Twitter archive into the [Day One journaling app](https://dayoneapp.com).

Works on macOS Sequoia or newer.

## 🥺👉👈

If you found this useful, please consider supporting me:

- [Buy me a nice latte](https://ko-fi.com/jonathanx64)
- USDT TRC20: `TNhgaQw2n9WxsddLhaXnx1HvEEYsScmsrW`
- [Revolut](https://revolut.me/evgenii69)

## Known issues

- Recent Day One CLI versions are sandboxed and can only read attachment files from inside Day One's own container. The app handles this transparently by staging each entry's media there before import (and cleaning up after). Keep the Day One app running during the import: the app is what moves staged media into the entries, so with the app closed the images appear only after you next open it.
- Retweets of long tweets do not contain media; [see example](https://x.com/JonathanSeriesX/status/1436443683642122248). This is a limitation of Twitter Archive.
- Retweets longer than ~125 characters will be truncated with an ellipsis (`…`); this is also a limitation of the archive itself.
- Media thumbnails in Day One app may appear blank at first; they’ll load once you switch to another window and then back.

## Plans (if the project gains traction and/or I have lots of spare time)

- Online retrieval of missing tweets (the ones you quoted or replied to)
- Better LLM-based title generation
- Support for grouping relevant successive single tweets into a singular post, which sounds impossible tbh (relevant for tweets posted before 2017, as there were no threads back then)
