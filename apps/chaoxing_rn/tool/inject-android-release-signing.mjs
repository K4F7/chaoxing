#!/usr/bin/env node
/**
 * After `expo prebuild`, point the generated release build at CI-provided
 * keystore files. Does not print keystore contents or passwords.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const gradlePath = join(root, "android/app/build.gradle");
const snippetPath = join(root, "android/app/ci-release-signing.gradle");
const applyLine = 'apply from: "ci-release-signing.gradle"';

writeFileSync(
  snippetPath,
  `android {
    signingConfigs {
        release {
            def props = new Properties()
            props.load(new FileInputStream(rootProject.file("keystore.properties")))
            storeFile file("upload-keystore.jks")
            storePassword props["storePassword"]
            keyAlias props["keyAlias"]
            keyPassword props["keyPassword"]
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
`,
  "utf8",
);

const gradle = readFileSync(gradlePath, "utf8");
if (!gradle.includes(applyLine)) {
  writeFileSync(gradlePath, `${gradle.trimEnd()}\n${applyLine}\n`, "utf8");
}
