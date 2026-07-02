import { readFileSync } from "node:fs";

const index = readFileSync(new URL("../src/index.ts", import.meta.url), "utf8");
const requiredExports = ["ChatSDK", "InstaChatSDK", "InstaChatChatProvider", "InstaChatMediaUploadProvider"];
const missing = requiredExports.filter((name) => !index.includes(name));

if (missing.length > 0) {
  throw new Error(`Missing public exports: ${missing.join(", ")}`);
}

console.log("SDK public export smoke check passed.");
