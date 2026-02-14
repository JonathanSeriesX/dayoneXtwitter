import Image from "next/image";
import styles from "./page.module.css";

const features = [
  {
    title: "Thread-aware parsing",
    description:
      "Twixodus intelligently merges multi-post threads into a single Day One entry so ideas stay in context.",
  },
  {
    title: "Media and metadata",
    description:
      "Photos, videos, hashtags, quote tweets, and engagement numbers are preserved in clean journal entries.",
  },
  {
    title: "Offline by default",
    description:
      "Browse and search your full timeline locally in Day One, including old posts that are hard to find online.",
  },
  {
    title: "Built for edge cases",
    description:
      "The parser handles replies, retweets, and odd archive structures to minimize manual cleanup.",
  },
];

const steps = [
  "Request and download your Twitter archive from X.",
  "Install Day One CLI, then create journals for tweets and optional replies.",
  "Run Twixodus and let it build polished Day One entries from your archive.",
];

export default function Home() {
  return (
    <main className={styles.page}>
      <div className={styles.orbA} aria-hidden />
      <div className={styles.orbB} aria-hidden />

      <section className={styles.hero}>
        <div className={styles.heroCopy}>
          <p className={styles.kicker}>Twitter archive importer for Day One</p>
          <h1 className={styles.title}>Make your tweet history useful again.</h1>
          <p className={styles.summary}>
            Twixodus turns your Twitter archive into a structured, searchable journal in Day One. Keep your posts,
            threads, replies, and media in one private timeline you fully control.
          </p>

          <div className={styles.ctaRow}>
            <a
              className={styles.primaryCta}
              href="https://github.com/JonathanSeriesX/dayoneXtwitter"
              target="_blank"
              rel="noopener noreferrer"
            >
              Download on GitHub
            </a>
            <a className={styles.secondaryCta} href="#how-it-works">
              See workflow
            </a>
          </div>

          <div className={styles.badges}>
            <span>macOS Sonoma+</span>
            <span>Day One CLI</span>
            <span>Media support</span>
          </div>
        </div>

        <aside className={styles.previewCard}>
          <p className={styles.previewLabel}>What it unlocks</p>
          <ul>
            <li>Find old tweets instantly with real full-text search.</li>
            <li>Relive threads as coherent stories, not fragmented posts.</li>
            <li>Keep your photos and context even if your account changes.</li>
          </ul>
        </aside>
      </section>

      <section className={styles.section}>
        <div className={styles.sectionHeader}>
          <p className={styles.sectionEyebrow}>Why Twixodus</p>
          <h2>Built for migration quality, not just raw export.</h2>
        </div>

        <div className={styles.featureGrid}>
          {features.map((feature) => (
            <article className={styles.featureCard} key={feature.title}>
              <h3>{feature.title}</h3>
              <p>{feature.description}</p>
            </article>
          ))}
        </div>
      </section>

      <section className={styles.section}>
        <div className={styles.sectionHeader}>
          <p className={styles.sectionEyebrow}>Live interface preview</p>
          <h2>See how imported tweets look inside Day One.</h2>
        </div>

        <div className={styles.gallery}>
          <figure className={styles.galleryCard}>
            <Image
              src="/showcase/twatter.jpg"
              alt="Twixodus overview screenshot"
              width={1000}
              height={625}
              sizes="(max-width: 768px) 100vw, 33vw"
            />
            <figcaption>Overview and setup guidance</figcaption>
          </figure>

          <figure className={styles.galleryCard}>
            <Image
              src="/showcase/threads.png"
              alt="Imported thread example"
              width={1000}
              height={625}
              sizes="(max-width: 768px) 100vw, 33vw"
            />
            <figcaption>Threads merged into readable entries</figcaption>
          </figure>

          <figure className={styles.galleryCard}>
            <Image
              src="/showcase/replies.png"
              alt="Reply and media import example"
              width={1000}
              height={625}
              sizes="(max-width: 768px) 100vw, 33vw"
            />
            <figcaption>Replies and media preserved cleanly</figcaption>
          </figure>
        </div>
      </section>

      <section className={styles.section} id="how-it-works">
        <div className={styles.sectionHeader}>
          <p className={styles.sectionEyebrow}>How it works</p>
          <h2>From archive zip to journal in minutes.</h2>
        </div>

        <ol className={styles.steps}>
          {steps.map((step, index) => (
            <li key={step}>
              <span className={styles.stepIndex}>{index + 1}</span>
              <p>{step}</p>
            </li>
          ))}
        </ol>
      </section>

      <section className={styles.footerCta}>
        <h2>Start the import whenever you are ready.</h2>
        <p>
          Clone the repository, follow the setup instructions, and move your Twitter history into a place that is
          searchable and future-proof.
        </p>
        <a
          className={styles.primaryCta}
          href="https://github.com/JonathanSeriesX/dayoneXtwitter"
          target="_blank"
          rel="noopener noreferrer"
        >
          Get Twixodus from GitHub
        </a>
      </section>
    </main>
  );
}
