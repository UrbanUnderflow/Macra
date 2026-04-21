import { execFileSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";
import fs from "node:fs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, "../..");
const htmlPath = path.join(__dirname, "app-store-screenshots.html");
const outputDir = path.join(projectRoot, "artifacts/app-store-screenshots");

const screens = [
  ["01-food-journal", "journal"],
  ["02-ai-meal-scan", "scan"],
  ["03-meal-planning", "planner"],
  ["04-label-scanner", "label"],
  ["05-ask-nora", "coach"],
  ["06-macra-plus", "plus"]
];

fs.mkdirSync(outputDir, { recursive: true });

for (const [name, hash] of screens) {
  const url = `${pathToFileURL(htmlPath).href}#${hash}`;
  const outputPath = path.join(outputDir, `${name}.png`);

  execFileSync(
    "npx",
    [
      "--yes",
      "playwright@1.59.1",
      "screenshot",
      "--browser=chromium",
      "--viewport-size=1242,2688",
      "--timeout=60000",
      "--wait-for-timeout=900",
      "--wait-for-selector=.phone-screen",
      url,
      outputPath
    ],
    { stdio: "inherit", cwd: projectRoot }
  );
}

console.log(`Wrote ${screens.length} screenshots to ${outputDir}`);
