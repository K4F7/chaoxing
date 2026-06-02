import { applyDevVars } from "../src/dev-vars";
import { collectUniqueWorkLinks, type DetailSummary } from "../src/processor";
import { parseAssignmentRequirement } from "../src/requirements";

await applyDevVars();

const detailsPath = "/tmp/chaoxing-probe/inbox-details-92.json";
const details = JSON.parse(await Bun.file(detailsPath).text()) as {
  summaries: DetailSummary[];
};
const limit = readLimit();
const unique = collectUniqueWorkLinks(details.summaries);

const requirements = [];
let index = 0;
for (const [entryUrl, summary] of unique) {
  if (index >= limit) {
    break;
  }
  index += 1;
  const response = await fetch(entryUrl, {
    redirect: "follow",
    headers: {
      Accept: "text/html,application/xhtml+xml",
      Cookie: Bun.env.CHAOXING_COOKIE || "",
      Referer: "https://notice.chaoxing.com/pc/notice/myNotice",
      "User-Agent": "Mozilla/5.0",
    },
  });
  const html = await response.text();
  requirements.push(
    parseAssignmentRequirement({
      html,
      entryUrl,
      finalUrl: response.url,
      status: response.status,
      sourceTitle: summary.title,
      sourceSendTime: summary.sendTime,
      sourceContent: summary.content,
    }),
  );
}

const output = {
  totalUniqueWorkLinks: unique.size,
  fetchedRequirements: requirements.length,
  requirements,
};

await Bun.write(
  "/tmp/chaoxing-probe/assignment-requirements.json",
  JSON.stringify(output, null, 2),
);
console.log(JSON.stringify(output, null, 2));

function readLimit(): number {
  const value = Bun.argv.find((arg) => arg.startsWith("--limit="))?.split("=")[1];
  return value ? Number.parseInt(value, 10) : 40;
}
