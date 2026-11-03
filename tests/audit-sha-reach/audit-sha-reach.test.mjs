// 実行: node --test tests/audit-sha-reach/audit-sha-reach.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  extractPinnedShas,
  isReachable,
  checkPins,
} from "../../scripts/audit-sha-reach.mjs";

const SHA_A = "a".repeat(40);
const SHA_B = "b".repeat(40);

test("extractPinnedShas: SHA pin のみ抽出し @main・短縮SHA・コメント行は除外", () => {
  const content = [
    "jobs:",
    "  a:",
    `    uses: flipslidersand-labs/qa-workflows/.github/workflows/node-test.yml@${SHA_A} # pin`,
    "  b:",
    "    uses: flipslidersand-labs/qa-workflows/.github/workflows/go-test.yml@main",
    "  c:",
    "    uses: flipslidersand-labs/qa-workflows/.github/workflows/go-test.yml@abc1234",
    `  # uses: flipslidersand-labs/qa-workflows/.github/workflows/x.yml@${SHA_B}`,
    `    uses: other/repo/.github/workflows/x.yml@${SHA_B}`,
    `    uses: flipslidersand-labs/qa-workflows/.github/workflows/python-test.yml@${SHA_A}`,
  ].join("\n");
  assert.deepEqual(extractPinnedShas(content), [SHA_A]);
});

test("extractPinnedShas: SHA 無し/空は空配列", () => {
  assert.deepEqual(extractPinnedShas(""), []);
  assert.deepEqual(extractPinnedShas(undefined), []);
});

test("isReachable: ahead/identical/behind は到達可能、diverged は不能", () => {
  for (const s of ["ahead", "identical", "behind"]) assert.equal(isReachable(s), true);
  assert.equal(isReachable("diverged"), false);
  assert.equal(isReachable("not-found"), false);
});

test("checkPins: 正常/diverged/404/例外を注入した fetch で判定", () => {
  const table = { [SHA_A]: "behind", [SHA_B]: "diverged", [("c".repeat(40))]: null };
  const res = checkPins(
    [SHA_A, SHA_B, "c".repeat(40), "d".repeat(40)],
    (sha) => {
      if (sha === "d".repeat(40)) throw new Error("network");
      return table[sha];
    },
  );
  assert.deepEqual(
    res.map((r) => [r.status, r.reachable]),
    [
      ["behind", true],
      ["diverged", false],
      ["not-found", false],
      ["error", null],
    ],
  );
});

test("checkPins: SHA 無しなら fetch を呼ばず空", () => {
  let called = 0;
  assert.deepEqual(checkPins([], () => (called++, "ahead")), []);
  assert.equal(called, 0);
});
