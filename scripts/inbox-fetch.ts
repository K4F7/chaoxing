import { fetchInboxMessages } from "../src/inbox";
import { applyDevVars } from "../src/dev-vars";

await applyDevVars();

const limit = readLimit();
const result = await fetchInboxMessages({
  cookie: Bun.env.CHAOXING_COOKIE || "",
  homeUrl: Bun.env.CHAOXING_HOME_URL,
  limit,
});

console.log(
  JSON.stringify(
    {
      ...result,
      messages: result.messages,
    },
    null,
    2,
  ),
);

function readLimit(): number {
  const value = Bun.argv.find((arg) => arg.startsWith("--limit="))?.split("=")[1];
  const parsed = value ? Number.parseInt(value, 10) : 20;
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 20;
}
