import { expect, test } from "@playwright/test";

const fixturePath = "tests/e2e/.tmp/view-filter-e2e.rds";
const filterControls = {
  minimum: "#filterCells-nFeature_min",
  maximum: "#filterCells-nFeature_max",
  percentMt: "#filterCells-percent\\.mt_max",
  apply: "#filterCells-filter_cell",
};
const subsetSwitch = "#renameCluster-subsetCells-subsetData";
const appLoadingOverlay = ".waiter-overlay.waiter-fullscreen";
const groupBySelectizeInput = "#updateCategory-group\\.by-selectized";

const readInputValue = async (page, inputId) => page.evaluate((id) => {
  const values = window.Shiny?.shinyapp?.$inputValues;
  const value = values?.[id];
  return value == null ? value : JSON.parse(JSON.stringify(value));
}, inputId);

const toggleSubsetSwitch = async (page) => {
  const input = page.locator(subsetSwitch);
  const control = input.locator(
    "xpath=ancestor::div[contains(@class, 'bootstrap-switch-wrapper')]",
  );

  await control.scrollIntoViewIfNeeded();
  await control.click();
};

test("View Filter, category Subset, stale intent, and Restore preserve Analysis safety", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator("#dataInput-dataInput")).toBeAttached();
  await page.locator("#dataInput-dataInput").setInputFiles(fixturePath);
  await expect(page.locator("#cellCount .cell-count-total")).toHaveText("6");
  await expect(page.locator(appLoadingOverlay)).toBeHidden();

  await page
    .locator("#left_sidebar")
    .getByRole("button", { name: "Cell Filtering" })
    .click();
  await page.locator(filterControls.minimum).fill("150");
  await page.locator(filterControls.maximum).fill("450");
  await page.locator(filterControls.percentMt).fill("50");
  await page.locator(filterControls.apply).click();
  await expect(page.locator("#cellCount .cell-count-total")).toHaveText("3");

  await page.locator(groupBySelectizeInput).click();
  await page.locator(groupBySelectizeInput).fill("cluster");
  await page
    .locator(".selectize-dropdown:visible .option")
    .filter({ hasText: "cluster" })
    .click();
  await expect(page.locator("#updateCategory-group\\.by")).toHaveValue("cluster");

  await page
    .locator("#right_sidebar")
    .getByRole("button", { name: "Rename Clusters" })
    .click();
  await expect(page.locator("#renameCluster-chosenGroup option[value=\"B\"]")).toHaveCount(1);
  await page.locator("#renameCluster-chosenGroup").selectOption(["B"]);
  await expect(page.locator("#renameCluster-selectedCellsText")).toHaveText("2 Cells Selected");

  const staleCategoryIntent = await readInputValue(
    page,
    "renameCluster-categorySelectionContext",
  );
  expect(staleCategoryIntent).toMatchObject({
    category: {
      groupBy: "cluster",
      groupLevels: ["B"],
      splitBy: "None",
      splitLevels: [],
    },
    analysisVersion: 0,
    viewFilterVersion: 1,
  });
  expect(staleCategoryIntent.analysisLineageId).toBeGreaterThan(0);
  expect(staleCategoryIntent).not.toHaveProperty("cells");

  await toggleSubsetSwitch(page);
  await expect(page.locator(subsetSwitch)).toBeChecked();
  await expect(page.locator("#cellCount .cell-count-total")).toHaveText("2");

  await toggleSubsetSwitch(page);
  await expect(page.locator(subsetSwitch)).not.toBeChecked();
  await expect(page.locator("#cellCount .cell-count-total")).toHaveText("3");

  await page.evaluate((intent) => {
    window.Shiny.setInputValue(
      "renameCluster-categorySelectionContext",
      intent,
      { priority: "event" },
    );
  }, staleCategoryIntent);
  await toggleSubsetSwitch(page);

  await expect(page.locator(subsetSwitch)).not.toBeChecked();
  await expect(page.locator("#cellCount .cell-count-total")).toHaveText("3");
});
