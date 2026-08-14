#!/usr/bin/env bash
#
# Applies the gate-3 repository settings documented in docs/SHIFT-LEFT.md.
#
# These live in a script rather than in prose because "we turned on push protection"
# is a claim, and a re-runnable script is evidence. Idempotent: safe to run repeatedly.
#
# Requires: gh, authenticated with `repo` and `admin:org`-equivalent rights on the repo.
#   gh auth refresh -h github.com -s admin:gpg_key,user
#
# Usage: scripts/bootstrap-repo-settings.sh [owner/repo]

set -euo pipefail

REPO="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
echo "==> Configuring ${REPO}"

# --- Secret scanning and push protection ------------------------------------
# Push protection is the only one of the three secret gates a developer cannot
# switch off locally, so it is the one that actually holds.
echo "--> secret scanning + push protection"
gh api -X PATCH "repos/${REPO}" \
  -f 'security_and_analysis[secret_scanning][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_non_provider_patterns][status]=enabled' \
  --silent

# --- General hygiene ---------------------------------------------------------
echo "--> merge settings"
gh api -X PATCH "repos/${REPO}" \
  -F 'allow_squash_merge=true' \
  -F 'allow_merge_commit=false' \
  -F 'allow_rebase_merge=false' \
  -F 'delete_branch_on_merge=true' \
  -F 'allow_auto_merge=true' \
  -f 'squash_merge_commit_title=PR_TITLE' \
  -f 'squash_merge_commit_message=PR_BODY' \
  --silent

# --- Branch ruleset on main --------------------------------------------------
# A ruleset rather than classic branch protection: rulesets express an explicitly
# empty bypass list, which classic protection cannot. The repository admin is
# subject to these rules, which is the point — the admin account is the one worth
# compromising.
echo "--> ruleset: main"
RULESET_JSON="$(mktemp)"
trap 'rm -f "${RULESET_JSON}"' EXIT

cat >"${RULESET_JSON}" <<'JSON'
{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_signatures" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["squash"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          { "context": "gitleaks" },
          { "context": "checkov" },
          { "context": "packer fmt + opa policy" }
        ]
      }
    }
  ]
}
JSON

# required_approving_review_count is 0 deliberately: this is a single-maintainer
# portfolio repo, and a rule demanding an approver who cannot exist would either
# block every merge or be bypassed — which would undermine the empty bypass list
# that is the interesting part. On a team repo this is 1 or 2. Stated here rather
# than quietly set, because an interviewer will spot the 0 and ask.

EXISTING="$(gh api "repos/${REPO}/rulesets" --jq '.[] | select(.name=="main-protection") | .id' 2>/dev/null || true)"
if [[ -n "${EXISTING}" ]]; then
  echo "    updating existing ruleset ${EXISTING}"
  gh api -X PUT "repos/${REPO}/rulesets/${EXISTING}" --input "${RULESET_JSON}" --silent
else
  echo "    creating ruleset"
  gh api -X POST "repos/${REPO}/rulesets" --input "${RULESET_JSON}" --silent
fi

# --- Verify ------------------------------------------------------------------
echo
echo "==> Result"
gh api "repos/${REPO}" --jq '
  "secret_scanning:        \(.security_and_analysis.secret_scanning.status)",
  "push_protection:        \(.security_and_analysis.secret_scanning_push_protection.status)",
  "squash_only:            \(.allow_squash_merge and (.allow_merge_commit|not) and (.allow_rebase_merge|not))"'
gh api "repos/${REPO}/rulesets" --jq '.[] | "ruleset:                \(.name) [\(.enforcement)]"'

echo
echo "Note: Dependabot for github-actions is configured by .github/dependabot.yml,"
echo "which takes effect once that file is on the default branch."
