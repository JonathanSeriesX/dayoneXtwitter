import Image from "next/image";

import repliesShot from "@/public/pics/replies.png";
import threadsShot from "@/public/pics/threads.png";
import twatterShot from "@/public/pics/twatter.jpg";

import { CopyButton } from "./copy-button";
import { CoffeeIcon, DownloadIcon, GitHubIcon } from "./icons";
import { ThemeSwitch } from "./theme-switch";

const repo = "https://github.com/JonathanSeriesX/dayoneXtwitter";
const releases = `${repo}/releases`;

/* One string, so the block you read is byte-for-byte the block you copy.
   Chained with a trailing && rather than left as three bare lines: the cask
   install can stop for a password, and a bare newline after it would be
   swallowed by that prompt instead of running the next command. The chain
   also stops the moment a step fails. */
const OLLAMA_SETUP = `brew install --cask ollama-app &&
  ollama pull qwen3.5:9b-mlx &&
  ollama serve`;

function A({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <a
      className="link"
      href={href}
      {...(href.startsWith("http")
        ? { target: "_blank", rel: "noreferrer" }
        : {})}
    >
      {children}
    </a>
  );
}

/* One collapsible glass section. Everything on this page is README.md,
   folded into these. */
function Dash({
  title,
  badge,
  open = false,
  children,
}: {
  title: React.ReactNode;
  badge?: string;
  open?: boolean;
  children: React.ReactNode;
}) {
  return (
    <details className="dash" open={open}>
      <summary>
        <span className="dash-title">{title}</span>
        {badge && <span className="badge">{badge}</span>}
        <span className="chevron" aria-hidden />
      </summary>
      <div className="dash-body">{children}</div>
    </details>
  );
}

export default function Page() {
  return (
    <div className="wrap stagger">
      <header className="hero flow-root">
        <div className="hero-shot">
          <Image
            src={twatterShot}
            alt="The bird, freed"
            fill
            sizes="216px"
            priority
            className="object-cover"
          />
        </div>
        <h1>Twixodus</h1>
        <p className="hero-tag">
          The <strong>ultimate</strong> tool to seamlessly import your Twitter
          archive into the{" "}
          <A href="https://dayoneapp.com">Day One journaling app</A>.
        </p>
        <div className="cta-row">
          <a className="cta" href={releases} target="_blank" rel="noreferrer">
            <DownloadIcon />
            Download Twixodus.zip
          </a>
          <a
            className="cta ghost"
            href={repo}
            target="_blank"
            rel="noreferrer"
          >
            <GitHubIcon />
            Source
          </a>
        </div>
        <p className="hero-meta">
          native macOS app · your data never leaves your Mac
        </p>
      </header>

      <Dash title="What for?">
        <p className="sub">
          By importing your Twitter archive into Day One, you can:
        </p>
        <ul className="prose-list">
          <li>
            Browse your entire tweet history offline with lightning-fast random
            access
          </li>
          <li>
            Rediscover what you posted “on this day“ in past years—like{" "}
            <A href="https://www.timehop.com">Timehop</A>, but nicer and with no
            limitations
          </li>
          <li>
            Browse all your tweeted photos and videos in a sleek, organized
            gallery
          </li>
          <li>
            Perform full-text searches that actually work
            <ul>
              <li>
                Easily purge any unwanted{" "}
                <A href="https://en.wikipedia.org/wiki/Kompromat">kompromat</A>{" "}
                from your old tweets
              </li>
            </ul>
          </li>
        </ul>
        <figure className="shot">
          <Image
            src={threadsShot}
            alt="A thread combined into a single Day One entry"
          />
        </figure>
      </Dash>

      <Dash title="What's so good about it?">
        <ul className="prose-list">
          <li>
            Beautifully classifies pure tweets, threads, retweets, quote-tweets,
            replies, etc., and acts accordingly
          </li>
          <li>
            Handles threads <em>gracefully</em> and combines them into single,
            cohesive Day One entries
          </li>
          <li>Supports media attachments, hashtags, locations</li>
          <li>Appends like/retweet count under each tweet</li>
          <li>
            Remembers what it already imported — run it again next year with a
            fresh archive and only the new tweets get imported
          </li>
          <li>
            Optionally titles your entries with a local LLM via{" "}
            <A href="https://ollama.com">Ollama</A> — “Wrote about Formula 1”,
            “Expressed frustration at airport security”, etc.
          </li>
        </ul>
        <figure className="shot">
          <Image
            src={repliesShot}
            alt="Twitter replies imported into Day One"
          />
        </figure>
      </Dash>

      <Dash title="Requirements">
        <ul className="prose-list">
          <li>
            macOS Sequoia or newer. If you don&apos;t have a Mac, find a friend
            who does or spin up a virtual machine.
          </li>
          <li>
            The{" "}
            <A href="https://apps.apple.com/tr/app/day-one/id1055511498?mt=12">
              Day One app
            </A>{" "}
            with its{" "}
            <A href="https://dayoneapp.com/guides/day-one-for-mac/command-line-interface-cli/">
              command-line tool
            </A>{" "}
            installed
          </li>
          <li>
            Day One Silver subscription for more than one attachment per entry
            (free trial available, feel free to cancel it right after the
            import)
          </li>
        </ul>
      </Dash>

      <Dash title="Usage" badge="9 steps">
        <ol className="steps">
          <li>
            <span className="step-num" aria-hidden>
              1
            </span>
            <p>
              <strong>Download your Twitter data</strong> — request your
              archive{" "}
              <A href="https://x.com/settings/download_your_data">here</A>.
            </p>
          </li>
          <li>
            <span className="step-num" aria-hidden>
              2
            </span>
            <p>
              <strong>Install Day One and its CLI</strong>, open the app, and
              (optionally) sign in.
            </p>
          </li>
          <li>
            <span className="step-num" aria-hidden>
              3
            </span>
            <p>
              <strong>Create the journals</strong>: go to{" "}
              <A href="dayone://preferences">
                <span className="mono">dayone://preferences</span>
              </A>{" "}
              → <strong>Journals</strong> and add{" "}
              <span className="mono">Tweets</span> (and{" "}
              <span className="mono">Twitter Replies</span> if you want replies
              too — don&apos;t forget to disable the &quot;Show in …&quot;
              options for that one).
            </p>
          </li>
          <li>
            <span className="step-num" aria-hidden>
              4
            </span>
            <p>
              (Optional) <strong>Pause sync</strong> in Day One preferences →{" "}
              <strong>Sync</strong> if you&apos;re on a metered connection.
            </p>
          </li>
          <li>
            <span className="step-num" aria-hidden>
              5
            </span>
            <p>
              (Optional) <strong>Setup Ollama</strong> on your Mac (see the
              next section for more details)
            </p>
          </li>
          <li>
            <span className="step-num" aria-hidden>
              6
            </span>
            <p>
              <strong>Download</strong> the latest{" "}
              <span className="mono">Twixodus.zip</span> from{" "}
              <A href={releases}>Releases</A>.
            </p>
          </li>
          <li>
            <span className="step-num" aria-hidden>
              7
            </span>
            <p>
              <strong>Launch Twixodus</strong> and drop your{" "}
              <span className="mono">twitter-….zip</span> (or the unpacked
              folder) onto the window.
            </p>
          </li>
          <li>
            <span className="step-num" aria-hidden>
              8
            </span>
            <p>
              Walk through the settings — journals, date range, whether your
              account still exists — and press <strong>Start Import</strong>.
              You can pause or cancel any time; the ledger remembers every
              imported thread, so the next run picks up where you left off.
            </p>
          </li>
          <li>
            <span className="step-num" aria-hidden>
              9
            </span>
            <p>
              Keep the Day One app running during the import: it&apos;s what
              moves the staged media into the entries.
            </p>
          </li>
        </ol>
      </Dash>

      <Dash title="AI titles" badge="optional">
        <p className="sub">Execute following commands in your terminal:</p>
        <div className="code-block">
          <pre className="code-card">
            <code>{OLLAMA_SETUP}</code>
          </pre>
          <CopyButton text={OLLAMA_SETUP} label="Copy commands" />
        </div>
        <p>
          Then flip on “Title entries with a local LLM” in the app.{" "}
          <span className="mono">qwen3.5:9b-mlx</span> runs quickly on Apple
          Silicon Macs with 16 GB+ of memory; on smaller Macs pull{" "}
          <span className="mono">qwen3.5:4b-mlx</span> instead and change the
          model name in the app. When the model can&apos;t tell what a tweet is
          about, the title stays a plain “Tweeted”. Delete the model afterwards
          with <span className="mono">ollama rm qwen3.5:9b-mlx</span> to
          reclaim the storage space.
        </p>
      </Dash>

      <Dash title="🥺👉👈">
        <p className="sub">
          If you found this useful, please consider supporting me:
        </p>
        <ul className="prose-list">
          <li>
            <A href="https://coff.ee/jonathunky">Buy me a coffee</A>
          </li>
          <li>
            USDT TRC20:{" "}
            <span className="mono select-all">
              TKa6wmqpLvMQwacU1wnPgFWZHFaDRV9jFs
            </span>
          </li>
        </ul>
      </Dash>

      {/* Parked, not deleted — the README still carries both lists, and this
          is where they go if the site ever wants them back. Uncomment to
          restore; they render below the support section, collapsed.

      <Dash title="Known issues" open={false}>
        <ul className="prose-list">
          <li>
            Recent Day One CLI versions are sandboxed and can only read
            attachment files from inside Day One&apos;s own container. The app
            handles this transparently by staging each entry&apos;s media there
            before import (and cleaning up after). Keep the Day One app running
            during the import: the app is what moves staged media into the
            entries, so with the app closed the images appear only after you
            next open it.
          </li>
          <li>
            Retweets of long tweets do not contain media;{" "}
            <A href="https://x.com/JonathanSeriesX/status/1436443683642122248">
              see example
            </A>
            . This is a limitation of Twitter Archive.
          </li>
          <li>
            Retweets longer than ~125 characters will be truncated with an
            ellipsis (<span className="mono">…</span>); this is also a
            limitation of the archive itself.
          </li>
          <li>
            Media thumbnails in Day One app may appear blank at first;
            they&apos;ll load once you switch to another window and then back.
          </li>
        </ul>
      </Dash>

      <Dash
        title="Plans"
        badge="if the project gains traction and/or I have lots of spare time"
        open={false}
      >
        <ul className="prose-list">
          <li>Signed &amp; notarized downloads</li>
          <li>Better LLM-based title generation</li>
          <li>
            Support for grouping relevant successive tweets into a single post
            (relevant for tweets posted before 2017, as there were no threads
            back then)
          </li>
        </ul>
      </Dash>

      */}

      <footer className="site-footer">
        <p>
          Twixodus is open source — the code, the issues and the releases all
          live in <A href={repo}>the repo</A>.
        </p>
        <div className="flex items-center gap-3">
          <nav className="seg" aria-label="Links">
            <a href={repo} aria-label="GitHub" title="GitHub" target="_blank" rel="noreferrer">
              <GitHubIcon />
            </a>
            <a href={releases} aria-label="Releases" title="Releases" target="_blank" rel="noreferrer">
              <DownloadIcon />
            </a>
            <a
              href="https://coff.ee/jonathunky"
              aria-label="Buy me a coffee"
              title="Buy me a coffee"
              target="_blank"
              rel="noreferrer"
            >
              <CoffeeIcon />
            </a>
          </nav>
          <ThemeSwitch />
        </div>
      </footer>
    </div>
  );
}
