/**
 * caller が qa-workflows の reusable workflow を 40桁SHA で pin している場合の
 * 到達可能性判定(#77)。squash+ブランチ削除後に SHA が main から辿れなくなると
 * startup_failure になる(dataguard-rail#196)。副作用なしの純関数のみ置く。
 */
const PIN_RE =
  /^\s*(?:-\s*)?uses:\s*flipslidersand-labs\/qa-workflows\/\S+?@([0-9a-f]{40})(?![0-9a-zA-Z])/;

/** workflow 本文から qa-workflows の 40桁SHA pin を重複なしで抽出(コメント行は除外)。 */
export function extractPinnedShas(content) {
  const shas = new Set();
  for (const line of String(content ?? "").split("\n")) {
    const m = PIN_RE.exec(line);
    if (m) shas.add(m[1]);
  }
  return [...shas];
}

/** compare API の status から到達可否を判定。404(null)・diverged は到達不能。 */
export function isReachable(status) {
  return ["ahead", "identical", "behind"].includes(status);
}

/**
 * fetchStatus(sha) -> status 文字列 | null(404)。例外は「確認不能」として扱う。
 * 戻り値: [{ sha, status, reachable }]。status は 'error' の場合あり(reachable=null)。
 */
export function checkPins(shas, fetchStatus) {
  return shas.map((sha) => {
    try {
      const status = fetchStatus(sha) ?? "not-found";
      return { sha, status, reachable: isReachable(status) };
    } catch {
      return { sha, status: "error", reachable: null };
    }
  });
}
