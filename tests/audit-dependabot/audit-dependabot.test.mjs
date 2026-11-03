// 実行: node --test tests/audit-dependabot/audit-dependabot.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  extractDependabotUses,
  judgeDependabotCaller,
} from "../../scripts/audit-dependabot.mjs";

const OLD = "5f38244" + "0".repeat(33);
const NEW = "2ca417cd" + "0".repeat(32);
const W = "flipslidersand-labs/qa-workflows/.github/workflows";
const triage = (ref) => ({ role: "triage", ref });
const promoter = (ref) => ({ role: "promoter", ref });
const fetchBy = (table) => (ref) => {
  if (!(ref in table)) throw new Error("unexpected " + ref);
  const v = table[ref];
  if (v instanceof Error) throw v;
  return v;
};

test("extractDependabotUses: triage/promoter 抽出、コメント行・他 reusable は除外", () => {
  const c = [
    `    uses: ${W}/dependabot-auto-merge.yml@${NEW} # note`,
    `    uses: ${W}/dependabot-auto-merge-minor.yml@main`,
    `  # uses: ${W}/dependabot-auto-merge.yml@${OLD}`,
    `    uses: ${W}/node-test.yml@${OLD}`,
  ].join("\n");
  assert.deepEqual(extractDependabotUses(c), [triage(NEW), promoter("main")]);
  assert.deepEqual(extractDependabotUses(undefined), []);
});

test("新版 SHA(ahead/identical)は ok", () => {
  const r = judgeDependabotCaller(
    { uses: [triage(NEW), promoter(OLD)] },
    fetchBy({ [NEW]: "identical", [OLD]: "ahead" }),
  );
  assert.equal(r.ok, true);
});

test("旧版 SHA(behind/diverged)は stale", () => {
  const r = judgeDependabotCaller(
    { uses: [triage(OLD), promoter(NEW)] },
    fetchBy({ [OLD]: "behind", [NEW]: "diverged" }),
  );
  assert.equal(r.ok, false);
  assert.deepEqual(r.stale, [
    { role: "triage", ref: OLD, status: "behind" },
    { role: "promoter", ref: NEW, status: "diverged" },
  ]);
});

test("@main は新版扱いで API を呼ばない", () => {
  const r = judgeDependabotCaller(
    { uses: [triage("main"), promoter("main")] },
    () => assert.fail("API を呼んではいけない"),
  );
  assert.equal(r.ok, true);
});

test("片方欠落(promoter 無し)は missing", () => {
  const r = judgeDependabotCaller(
    { uses: [triage("main")] },
    fetchBy({}),
  );
  assert.deepEqual(r.missing, ["promoter"]);
  assert.equal(r.ok, false);
});

test("両方欠落(reusable を使わない独自実装/未使用)は対象外で誤検出しない", () => {
  const r = judgeDependabotCaller({ uses: [] }, fetchBy({}));
  assert.equal(r.applicable, false);
  assert.equal(r.ok, true);
});

test("SHA が 404 は unreachable に分け stale にしない / API 例外は unknown", () => {
  const r = judgeDependabotCaller(
    { uses: [triage(OLD), promoter(NEW)] },
    fetchBy({ [OLD]: null, [NEW]: new Error("net") }),
  );
  assert.deepEqual(r.unreachable, [{ role: "triage", ref: OLD }]);
  assert.deepEqual(r.unknown, [{ role: "promoter", ref: NEW }]);
  assert.deepEqual(r.stale, []);
  assert.equal(r.ok, false);
});
