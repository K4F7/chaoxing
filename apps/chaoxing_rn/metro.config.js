const { getDefaultConfig } = require("expo/metro-config");
const path = require("node:path");

const projectRoot = __dirname;
const workspaceRoot = path.resolve(projectRoot, "../..");
const domainRoot = path.resolve(workspaceRoot, "packages/chaoxing-domain");
const alarmsRoot = path.resolve(workspaceRoot, "packages/chaoxing-android-alarms");

const config = getDefaultConfig(projectRoot);
config.watchFolders = [domainRoot, alarmsRoot];
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, "node_modules"),
  path.resolve(workspaceRoot, "node_modules"),
];
config.resolver.extraNodeModules = {
  "@chaoxinghelper/domain": domainRoot,
  "@chaoxinghelper/android-alarms": alarmsRoot,
};

module.exports = config;
