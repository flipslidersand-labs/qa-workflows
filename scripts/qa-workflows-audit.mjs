#!/usr/bin/env node
/**
 * org全リポでqa-workflows(flipslidersand-labs/qa-workflows)の reusable workflow
 * 導入状況を監査する。ローカルディスクのチェックアウトではなく必ず GitHub 上の
 * default branch を見る(2026-09-13 セッションでローカル未fetchによる大量の
 * 偽陰性が判明したため。see: reference_reusable_workflow_branch_protection_check_name)。
 *
 * Usage:
 *   node scripts/qa-workflows-audit.mjs                 # レポートのみ(dry-run)
 *   node scripts/qa-workflows-audit.mjs --apply          # 実際にissueをclose/create
 *   node scripts/qa-workflows-audit.mjs --apply --repo=owner/name  # 1リポのみ
 *
 * 自動化する範囲は「機械的に判定できること」に限定する:
 *   - 導入済みなのに open の追跡issueが残っている → 自動close
 *   - 未導入・CI(.github/workflows)あり・言語判定できる・追跡issue無し → issue作成
 * それ以外(独自CIの方が高機能だから置換すべきでない、lint/format修正が
 * 大規模すぎるので分割すべき、等の質的判断)は自動化せず、レポートに
 * "needs-review" として出すだけに留める。
 */
import { execSync } from "child_process";

const args = process.argv.slice(2);
const apply = args.includes("--apply");
const repoFilter = args.find((a) => a.startsWith("--repo="))?.split("=")[1];

const TRACKED_ORGS = ["flipslidersand", "flipslidersand-labs"];
const TRACKING_ISSUE = "flipslidersand-labs/qa-workflows#37";

const REUSABLE_BY_MANIFEST = [
  { file: "go.mod", reusable: "go-test.yml", lang: "Go" },
  { file: "Cargo.toml", reusable: "rust-test.yml", lang: "Rust" },
  { file: "pyproject.toml", reusable: "python-test.yml", lang: "Python" },
  { file: "requirements.txt", reusable: "python-test.yml", lang: "Python" },
  { file: "package.json", reusable: "node-test.yml", lang: "Node" },
];

const print = (msg) => process.stdout.write(`${msg}\n`);

function gh(cmd) {
  return execSync(`gh ${cmd}`, {
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
  }).trim();
}

function ghJson(cmd, fallback = []) {
  try {
    return JSON.parse(gh(cmd));
  } catch {
    return fallback;
  }
}

function getActiveRepos(org) {
  return ghJson(
    `repo list ${org} --limit 300 --json nameWithOwner,isArchived,defaultBranchRef --jq '[.[] | select(.isArchived | not) | {name: .nameWithOwner, branch: .defaultBranchRef.name}]'`,
  );
}

function listRootFiles(repo, branch) {
  try {
    return ghJson(`api repos/${repo}/contents?ref=${branch} --jq '[.[].name]'`);
  } catch {
    return [];
  }
}

function listWorkflowFiles(repo, branch) {
  try {
    return ghJson(
      `api repos/${repo}/contents/.github/workflows?ref=${branch} --jq '[.[] | select(.type=="file") | .name]'`,
    );
  } catch {
    return [];
  }
}

function getFileContent(repo, branch, path) {
  try {
    return gh(
      `api repos/${repo}/contents/${path}?ref=${branch} --jq '.content' | base64 -d`,
    );
  } catch {
    return "";
  }
}

function detectLanguage(repo, branch) {
  const rootFiles = listRootFiles(repo, branch);
  for (const { file, reusable, lang } of REUSABLE_BY_MANIFEST) {
    if (rootFiles.includes(file)) return { lang, reusable };
  }
  return null;
}

function findTrackingIssue(repo) {
  const issues = ghJson(
    `issue list --repo ${repo} --search "qa-workflows reusable workflow" --state open --json number,title`,
  );
  return issues[0]?.number ?? null;
}

function auditRepo(repo, branch) {
  const workflowFiles = listWorkflowFiles(repo, branch);
  const hasCi = workflowFiles.length > 0;
  const detected = detectLanguage(repo, branch);

  let adopted = false;
  if (hasCi && detected) {
    for (const f of workflowFiles) {
      const content = getFileContent(repo, branch, `.github/workflows/${f}`);
      if (
        content.includes(`qa-workflows/.github/workflows/${detected.reusable}`)
      ) {
        adopted = true;
        break;
      }
    }
  }

  const trackingIssue = findTrackingIssue(repo);

  return {
    repo,
    branch,
    hasCi,
    lang: detected?.lang ?? "unknown",
    adopted,
    trackingIssue,
  };
}

function closeStaleIssue(result) {
  gh(
    `issue close ${result.trackingIssue} --repo ${result.repo} --comment "自動監査(scripts/qa-workflows-audit.mjs)により、既にreusable workflowが導入済みと確認できたためクローズする。関連: ${TRACKING_ISSUE}"`,
  );
  print(`  → closed #${result.trackingIssue} (already adopted)`);
}

function createIssue(result) {
  const body = [
    `全リポ横断監査(scripts/qa-workflows-audit.mjs)でCI(.github/workflows)は存在するがqa-workflows reusable workflow(${result.lang})未導入と判定。`,
    "",
    "対応方針・落とし穴は memory `project_qa_platform_reusable_workflows` および qa-workflows README参照。",
    "",
    `関連: ${TRACKING_ISSUE}`,
  ].join("\n");
  const out = gh(
    `issue create --repo ${result.repo} --title "qa-workflows reusable workflow (${result.lang}) 導入" --body ${JSON.stringify(body)}`,
  );
  print(`  → created ${out}`);
}

async function main() {
  print(
    `🔍 qa-workflows 導入状況監査${apply ? "" : " [dry-run, --applyで実際に変更]"}\n`,
  );

  let targets = [];
  if (repoFilter) {
    targets = [
      {
        name: repoFilter,
        branch: gh(
          `repo view ${repoFilter} --json defaultBranchRef --jq .defaultBranchRef.name`,
        ),
      },
    ];
  } else {
    for (const org of TRACKED_ORGS) {
      targets.push(...getActiveRepos(org));
    }
  }

  const needsReview = [];
  const closed = [];
  const alreadyTracked = [];
  const skippedNoCiOrLang = [];

  for (const { name: repo, branch } of targets) {
    if (repo === "flipslidersand-labs/qa-workflows") continue; // provider repo itself
    const r = auditRepo(repo, branch);

    if (r.adopted) {
      if (r.trackingIssue) {
        print(`✅ ${repo}: adopted, stale issue #${r.trackingIssue}`);
        if (apply) closeStaleIssue(r);
        closed.push(r);
      }
      continue;
    }

    if (!r.hasCi || r.lang === "unknown") {
      skippedNoCiOrLang.push(r);
      continue;
    }

    if (r.trackingIssue) {
      alreadyTracked.push(r);
      continue;
    }

    print(`🆕 ${repo}: not adopted, lang=${r.lang}, no tracking issue`);
    if (apply) createIssue(r);
    needsReview.push(r);
  }

  print("\n--- Summary ---");
  print(`stale issues closed (adopted already): ${closed.length}`);
  print(`new issues candidates (created if --apply): ${needsReview.length}`);
  print(
    `already tracked (open issue exists, left as-is): ${alreadyTracked.length}`,
  );
  print(`skipped (no CI or unknown language): ${skippedNoCiOrLang.length}`);
  print(
    "\n注意: このスクリプトは機械的判定のみ行う。「独自CIの方が高機能」「lint修正が大規模」等の質的判断は行わないため、" +
      "作成されたissueは着手前に必ず該当リポのCI内容を確認すること。",
  );
}

main();
