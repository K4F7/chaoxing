const { getDefaultConfig } = require("expo/metro-config");
const path = require("node:path");

const projectRoot = __dirname;
const workspaceRoot = path.resolve(projectRoot, "../..");
const domainRoot = path.resolve(workspaceRoot, "packages/chaoxing-domain");

const config = getDefaultConfig(projectRoot);
config.watchFolders = [domainRoot];
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, "node_modules"),
  path.resolve(workspaceRoot, "node_modules"),
];
config.resolver.extraNodeModules = {
  "@chaoxinghelper/domain": domainRoot,
};

module.exports = config;
