const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const root = path.resolve(__dirname, "..");
const configPath = path.join(root, "wow-path.local");
const source = path.join(root, "AuctionPrices") + path.sep;

if (!fs.existsSync(configPath)) {
  console.error("Create wow-path.local and put the WoW client folder path in it.");
  process.exit(1);
}

const wowPath = fs.readFileSync(configPath, "utf8").trim();
if (!wowPath) {
  console.error("wow-path.local is empty. Put the WoW client folder path in it.");
  process.exit(1);
}

const addonsPath = path.join(wowPath, "Interface", "AddOns");
if (!fs.existsSync(addonsPath)) {
  console.error("Interface/AddOns was not found in: " + wowPath);
  process.exit(1);
}

const destination = path.join(addonsPath, "AuctionPrices") + path.sep;
fs.mkdirSync(destination, { recursive: true });

const result = spawnSync("rsync", [
  "-a",
  "--no-owner",
  "--no-group",
  "--no-perms",
  "--delete",
  source,
  destination,
], { stdio: "inherit" });

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

console.error('Copied to  ' + destination);
process.exit(result.status ?? 1);
