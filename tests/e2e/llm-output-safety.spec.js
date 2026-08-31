import { expect, test } from "@playwright/test";

test("assistant output remains literal text and cannot render active Markdown or HTML", async ({ page }) => {
  const externalRequests = [];
  page.on("request", (request) => {
    if (request.url().includes("example.invalid/llm-tracker.png")) {
      externalRequests.push(request.url());
    }
  });
  await page.addInitScript(() => {
    window.__scspotlightXss = false;
  });
  await page.goto("/");

  await expect.poll(async () => page.locator("body").innerText()).toContain(
    "<shinychat-raw-html>",
  );
  await expect(page.locator("shinychat-raw-html")).toHaveCount(0);
  await expect(page.locator("img[onerror*='__scspotlightXss']")).toHaveCount(0);
  await expect(page.locator("img[src*='example.invalid/llm-tracker.png']")).toHaveCount(0);
  await expect.poll(async () => page.locator("body").innerText()).toContain(
    "![shinychat-markdown-image](https://example.invalid/llm-tracker.png)",
  );
  await page.waitForTimeout(250);
  expect(externalRequests).toEqual([]);
  await expect.poll(() => page.evaluate(() => window.__scspotlightXss)).toBe(false);
});
