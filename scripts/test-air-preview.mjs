/** Hold the product screenshot response and check its reserved height in both themes.
 * Run against a built SITE_URL with CHROME_PATH and PUPPETEER_MODULE as needed. */
import assert from "node:assert/strict";

const { default: puppeteer } = await import(process.env.PUPPETEER_MODULE || "puppeteer-core");
const base = process.env.SITE_URL || "http://127.0.0.1:8180";
const browser = await puppeteer.launch({
  executablePath:
    process.env.CHROME_PATH || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: true,
});

async function checkPreviewSize(theme) {
  const preview = await browser.newPage();
  const releaseImage = Promise.withResolvers();
  try {
    await preview.setViewport({ width: 390, height: 844 });
    await preview.emulateMediaFeatures([{ name: "prefers-color-scheme", value: theme }]);
    await preview.setCacheEnabled(false);
    await preview.setRequestInterception(true);
    preview.on("request", async (request) => {
      if (new URL(request.url()).pathname.startsWith("/images/library-")) await releaseImage.promise;
      await request.continue();
    });
    await preview.goto(base, { waitUntil: "domcontentloaded" });
    const image = await preview.waitForSelector(".product-preview img");
    await image.evaluate((img) => img.scrollIntoView({ block: "center" }));
    const before = await image.evaluate((img) => img.offsetHeight);
    releaseImage.resolve();
    const after = await image.evaluate(async (img) => {
      await img.decode();
      return img.offsetHeight;
    });
    assert.ok(
      after > 0 && before === after,
      `${theme}: preview height changed from ${before} to ${after}`,
    );
    console.log(`${theme}: screenshot reserves ${before}px before and after decoding.`);
  } finally {
    releaseImage.resolve();
    await preview.close();
  }
}

try {
  for (const theme of ["light", "dark"]) await checkPreviewSize(theme);
} finally {
  await browser.close();
}
