/**
 * Copy `text` to the clipboard; resolves to whether it actually landed
 * (false where the Clipboard API is unavailable or the write was refused).
 * Callers flash their success state off the result and stay quiet on failure.
 */
export async function copyToClipboard(text: string): Promise<boolean> {
  if (typeof navigator === "undefined" || !navigator.clipboard?.writeText) {
    return false;
  }
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}
