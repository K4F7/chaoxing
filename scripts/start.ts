import { spawn } from "bun";

import { checkChaoxingAuth } from "../src/auth";
import { applyDevVars } from "../src/dev-vars";

await applyDevVars();

const result = await checkChaoxingAuth({
  cookie: Bun.env.CHAOXING_COOKIE,
  homeUrl: Bun.env.CHAOXING_HOME_URL,
});

if (!result.authenticated) {
  console.log("学习通 Cookie 不可用，正在打开登录窗口...");
  const login = spawn(["bun", "run", "auth:login"], {
    stdout: "inherit",
    stderr: "inherit",
  });
  const loginExitCode = await login.exited;
  if (loginExitCode !== 0) {
    process.exit(loginExitCode);
  }

  await applyDevVars(".dev.vars", { overwrite: true });
  const refreshed = await checkChaoxingAuth({
    cookie: Bun.env.CHAOXING_COOKIE,
    homeUrl: Bun.env.CHAOXING_HOME_URL,
  });

  if (!refreshed.authenticated) {
    console.error("学习通登录后仍未通过认证，请重新运行 bun run start。");
    process.exit(1);
  }
}

console.log("学习通认证已通过，可以进入主界面。");
