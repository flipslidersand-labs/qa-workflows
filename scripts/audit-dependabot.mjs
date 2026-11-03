/**
 * dependabot 自動マージ caller の監査(#107)。副作用なしの純関数のみ置く。
 *  - triage(dependabot-auto-merge.yml)と promoter(dependabot-auto-merge-minor.yml)の両方を持つか
 *  - 判定集約を含む版(#108 のマージコミット以降)を指しているか
 * 到達不能 SHA の検出は audit-sha-reach.mjs(#77/#120)に任せ、ここでは重複報告しない。
 */
export const BASE_COMMIT = "2ca417cdbd9c5cea1919b894efff4b6cb5198d74"; // qa-workflows#108

export const CALLER_FILE_RE = /^dependabot-auto-merge.*\.yml$/;

const USES_RE =
  /^\s*(?:-\s*)?uses:\s*flipslidersand-labs\/qa-workflows\/\.github\/workflows\/(dependabot-auto-merge(?:-minor)?)\.yml@([^\s#]+)/;

/** workflow 本文から triage/promoter の uses を抽出(コメント行は除外)。 */
export function extractDependabotUses(content) {
  const out = [];
  for (const line of String(content ?? "").split("\n")) {
    const m = USES_RE.exec(line);
    if (m) out.push({ role: m[1] === "dependabot-auto-merge" ? "triage" : "promoter", ref: m[2] });
  }
  return out;
}

/**
 * 1リポの判定。uses: extractDependabotUses の結果(dependabot-auto-merge*.yml 全体分)、
 * qa-workflows の reusable を1つも使わないリポ(dev-platform の独自実装等)は対象外。
 * fetchBaseStatus(ref) -> BASE_COMMIT...ref の compare status | null(404) | throw。
 * 戻り値: { applicable, missing: ['triage'|'promoter'], stale: [{role,ref,status}],
 *          unreachable: [{role,ref}], unknown: [{role,ref}], ok }
 */
export function judgeDependabotCaller({ uses }, fetchBaseStatus) {
  const res = { applicable: false, missing: [], stale: [], unreachable: [], unknown: [], ok: true };
  if (uses.length === 0) return res; // qa-workflows の caller でない(未使用/独自実装)
  res.applicable = true;
  for (const role of ["triage", "promoter"]) {
    if (!uses.some((u) => u.role === role)) res.missing.push(role);
  }
  for (const { role, ref } of uses) {
    if (ref === "main") continue; // 常に最新
    let status;
    try {
      status = fetchBaseStatus(ref);
    } catch {
      res.unknown.push({ role, ref });
      continue;
    }
    if (status === null || status === undefined) res.unreachable.push({ role, ref });
    else if (status === "ahead" || status === "identical") continue;
    else res.stale.push({ role, ref, status }); // behind / diverged
  }
  res.ok = !res.missing.length && !res.stale.length && !res.unknown.length;
  return res;
}
