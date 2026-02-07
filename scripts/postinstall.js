import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const root = join(__dirname, "..");
const swiftDir = join(root, "swift");
const binaryPath = join(swiftDir, ".build", "release", "mail-bridge");
const entitlements = join(swiftDir, "mail-bridge.entitlements");

if (process.platform !== "darwin") {
  console.warn("apple-mail-mcp: skipping Swift build (macOS only)");
  process.exit(0);
}

if (existsSync(binaryPath)) {
  console.log("apple-mail-mcp: mail-bridge binary already exists, skipping build");
  process.exit(0);
}

try {
  execSync("which swift", { stdio: "ignore" });
} catch {
  console.error(
    "apple-mail-mcp: Swift toolchain not found.\n" +
      "Install Xcode Command Line Tools: xcode-select --install"
  );
  process.exit(1);
}

console.log("apple-mail-mcp: building mail-bridge (swift build -c release)...");

try {
  execSync("swift build -c release", { cwd: swiftDir, stdio: "inherit" });
} catch {
  console.error("apple-mail-mcp: swift build failed");
  process.exit(1);
}

try {
  execSync(
    `codesign --force --sign - --entitlements "${entitlements}" "${binaryPath}"`,
    { stdio: "inherit" }
  );
  console.log("apple-mail-mcp: mail-bridge built and signed successfully");
} catch {
  console.error("apple-mail-mcp: codesign failed (binary built but not signed)");
  process.exit(1);
}
