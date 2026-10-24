#!/usr/bin/env python3
"""
dep-policy-check — dependency drift detection.

Reads dep-policy.yaml in the repo root, loads the referenced profile from
dependency-policy/profiles/, then compares baseline versions with the
actual versions found in package.json / pyproject.toml.

Exit codes:
  0  no drift
  1  drift detected  (CI: use continue-on-error: true)
  2  expired override detected
"""
import argparse
import json
import re
import sys
from datetime import date
from pathlib import Path

try:
    import yaml
except ImportError:
    print("error: PyYAML not installed — run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Readers
# ---------------------------------------------------------------------------

def _read_node_versions(repo_root: Path) -> dict[str, str]:
    """Return {tool: version} from all package.json devDependencies."""
    versions: dict[str, str] = {}
    for pkg in repo_root.rglob("package.json"):
        # skip node_modules
        if "node_modules" in pkg.parts:
            continue
        try:
            data = json.loads(pkg.read_text())
        except json.JSONDecodeError:
            continue
        for section in ("devDependencies", "dependencies"):
            for name, ver in data.get(section, {}).items():
                # strip semver range prefix (^, ~, >=, <=)
                cleaned = re.sub(r"^[\^~>=<v]+", "", ver)
                versions.setdefault(name, cleaned)
    return versions


def _read_python_versions(repo_root: Path) -> dict[str, str]:
    """Return {tool: version} from pyproject.toml optional-deps."""
    versions: dict[str, str] = {}
    ppt = repo_root / "pyproject.toml"
    if not ppt.exists():
        return versions
    try:
        import tomllib  # Python 3.11+
    except ImportError:
        try:
            import tomli as tomllib  # fallback
        except ImportError:
            # very simple regex fallback for key==version lines
            for line in ppt.read_text().splitlines():
                m = re.match(r'\s*"?([\w\-]+)([><=!~^]+)([\d.]+)', line)
                if m:
                    versions[m.group(1)] = m.group(3)
            return versions

    data = tomllib.loads(ppt.read_text())
    proj = data.get("project", {})
    all_deps: list[str] = list(proj.get("dependencies", []))
    for opt_list in proj.get("optional-dependencies", {}).values():
        all_deps.extend(opt_list)
    for dep in all_deps:
        m = re.match(r"([\w\-]+)[><=!~^]+([\d.]+)", dep)
        if m:
            versions.setdefault(m.group(1), m.group(2))
    return versions


# ---------------------------------------------------------------------------
# Profile resolver
# ---------------------------------------------------------------------------

def _parse_profile_ref(ref: str) -> tuple[str, str]:
    """'node-t2@1' → ('node-t2', '1')"""
    if "@" in ref:
        name, ver = ref.rsplit("@", 1)
        return name, ver
    return ref, "1"


def _load_profile(policy_dir: Path, name: str) -> dict:
    path = policy_dir / "profiles" / f"{name}.yaml"
    if not path.exists():
        print(f"error: profile not found: {path}", file=sys.stderr)
        sys.exit(1)
    return yaml.safe_load(path.read_text()) or {}


# ---------------------------------------------------------------------------
# Drift check
# ---------------------------------------------------------------------------

def _ecosystem(profile_name: str) -> str:
    if "node" in profile_name:
        return "node"
    if "python" in profile_name or "py" in profile_name:
        return "python"
    return "unknown"


def check(repo_root: Path, policy_dir: Path) -> int:
    dep_policy_file = repo_root / "dep-policy.yaml"
    if not dep_policy_file.exists():
        print("dep-policy.yaml not found — skip drift check")
        return 0

    config = yaml.safe_load(dep_policy_file.read_text()) or {}
    profile_ref = config.get("dependency_profile")
    if not profile_ref:
        print("dep-policy.yaml: dependency_profile not set — skip")
        return 0

    overrides = config.get("overrides", {}) or {}
    profile_name, profile_ver = _parse_profile_ref(profile_ref)
    profile = _load_profile(policy_dir, profile_name)

    eco = _ecosystem(profile_name)
    if eco == "node":
        actual = _read_node_versions(repo_root)
    elif eco == "python":
        actual = _read_python_versions(repo_root)
    else:
        actual = {}

    baseline_tools: dict[str, str] = profile.get("tools", {}) or {}

    print(f"[dep-policy] profile: {profile_ref}")

    drift_count = 0
    expired_count = 0
    today = date.today()

    for tool, baseline_ver in baseline_tools.items():
        override = overrides.get(tool)
        actual_ver = actual.get(tool, "—")

        # If override present, use override version as "expected actual"
        if override:
            ov = override.get("version", "")
            reason = override.get("reason", "(no reason)")
            expires_raw = override.get("expires")
            issue = override.get("related_issue", "")

            expired = False
            if expires_raw:
                try:
                    exp_date = date.fromisoformat(str(expires_raw))
                    if today > exp_date:
                        expired = True
                        expired_count += 1
                except ValueError:
                    pass

            tag = "EXPIRED" if expired else "override"
            print(f"  {tool:<20} baseline={baseline_ver}  override={ov}  [{tag}]")
            print(f"    reason: {reason}")
            if expires_raw:
                marker = " ← EXPIRED" if expired else ""
                print(f"    expires: {expires_raw}{marker}")
            if issue:
                print(f"    issue: {issue}")
        else:
            if actual_ver == "—":
                status = "missing"
                drift_count += 1
            elif actual_ver != baseline_ver:
                status = "DRIFT"
                drift_count += 1
            else:
                status = "ok"
            print(f"  {tool:<20} baseline={baseline_ver}  actual={actual_ver}  {status}")

    print()
    if drift_count == 0 and expired_count == 0:
        print("result: no drift")
        return 0
    if expired_count > 0:
        print(f"result: {drift_count} drift, {expired_count} expired override(s)")
        return 2
    print(f"result: {drift_count} drift")
    return 1


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="dep-policy drift detection")
    parser.add_argument(
        "--repo-root",
        default=".",
        help="Path to the repository root (default: CWD)",
    )
    parser.add_argument(
        "--policy-dir",
        default=None,
        help="Path to dependency-policy/ dir (default: <script>/../dependency-policy/)",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    if args.policy_dir:
        policy_dir = Path(args.policy_dir).resolve()
    else:
        policy_dir = (Path(__file__).parent.parent / "dependency-policy").resolve()

    if not policy_dir.exists():
        print(f"error: policy dir not found: {policy_dir}", file=sys.stderr)
        sys.exit(1)

    sys.exit(check(repo_root, policy_dir))


if __name__ == "__main__":
    main()
