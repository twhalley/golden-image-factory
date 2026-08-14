# Evidence — gate 3 blocks a secret server-side, and the one it missed

**Date:** 2026-08-14
**Gate:** GitHub secret scanning push protection, enforced by GitHub, not by this repo
**Acceptance criterion:** phase 0 — "a test commit containing a fake AWS key is blocked
… by push protection"

Gate 1 was deliberately bypassed with `git commit --no-verify` for both attempts below.
That is the whole point of gate 3: it is the control a developer cannot switch off.
Generated key material is redacted; no real credential was used at any stage.

---

## Attempt 1 — a randomly generated AWS key pair. Not blocked.

```
$ git commit -S --no-verify -m "chore: bypass local hooks and attempt to push a secret"
$ git push -u origin test/push-protection-proof
...
branch 'test/push-protection-proof' set up to track 'origin/test/push-protection-proof'.
```

**The push succeeded.** The branch reached GitHub carrying the fake credential. It was
deleted immediately (`git push origin --delete`), and a check confirmed GitHub had raised
no alert of any kind:

```
$ gh api repos/twhalley/golden-image-factory/secret-scanning/alerts
(empty)
```

So this was not "detected but allowed". GitHub never classified the string as a secret.

**Why.** A real AWS access key ID is not arbitrary text after the `AKIA` prefix — the
remaining characters encode an account identifier with a checksum. A key ID assembled from
`/dev/urandom` matches the *shape* but fails that structure, so GitHub's provider pattern
discards it as a false positive. This is correct behaviour by a scanner whose false
positive rate has to be near zero to be usable at push time.

**The consequence is the finding.** A randomly generated AWS key cannot be used to validate
push protection. Combined with the gate 1 result — where AWS's *canonical documentation*
key pair is allowlisted by gitleaks — there are two obvious ways to test an AWS secret
gate and **both produce a false pass**:

| Test credential | gitleaks (gate 1) | Push protection (gate 3) |
|---|---|---|
| `AKIAIOSFODNN7EXAMPLE` (AWS's published example) | allowlisted, not detected | not detected |
| Random `AKIA` + 16 chars | detected — via generic entropy, not the AWS rule | **not detected** — fails checksum |
| A real AWS key | detected | detected |

The only credential that exercises the AWS path end to end is a real one, which is not an
acceptable test. Anyone who "verified push protection works" using either fake has verified
nothing about AWS keys.

---

## Attempt 2 — four fabricated provider patterns in one push. Blocked.

To establish whether push protection was working at all, rather than assuming, the same
push carried four different fabricated credentials.

```
$ git push -u origin test/push-protection-proof-2
remote: error: GH013: Repository rule violations found for refs/heads/test/push-protection-proof-2.
remote:
remote: - GITHUB PUSH PROTECTION
remote:   —————————————————————————————————————————
remote:     Resolve the following violations before pushing again
remote:
remote:     - Push cannot contain secrets
remote:
remote:       —— Slack Incoming Webhook URL ————————————————————————
remote:        locations:
remote:          - commit: f48c0ea…
remote:            path: leaked-credentials.txt:3
remote:
remote:       —— Stripe API Key ————————————————————————————————————
remote:        locations:
remote:          - commit: f48c0ea…
remote:            path: leaked-credentials.txt:4
remote:
remote:       —— SendGrid API Key ——————————————————————————————————
remote:        locations:
remote:          - commit: f48c0ea…
remote:            path: leaked-credentials.txt:5
remote:
To https://github.com/twhalley/golden-image-factory.git
 ! [remote rejected] test/push-protection-proof-2 -> test/push-protection-proof-2 (push declined due to repository rule violations)
error: failed to push some refs to 'https://github.com/twhalley/golden-image-factory.git'
```

**Push rejected.** Three of the four patterns were caught: Slack incoming webhook, Stripe
API key, SendGrid API key. These formats carry no checksum, so a well-formed fabricated
value is indistinguishable from a real one and the pattern fires.

The AWS pair on lines 1–2 of the same file was **again not flagged**, in a push GitHub was
demonstrably scanning and demonstrably willing to reject. That isolates the variable
cleanly: push protection is enabled and working, and the AWS-specific pattern is the part
that a random key cannot trigger.

The branch was never created remotely — the push was refused before any ref was written —
and the local branch was deleted.

---

## What this establishes

1. **Push protection is enabled and enforcing.** `GH013`, ref rejected, no bypass offered
   beyond the audited unblock URL, which this repo's ruleset does not permit anyone to use.
2. **It is pattern-based, not entropy-based.** It catches credentials matching a known
   provider format precisely. It will not catch a bespoke internal token, a database
   password, or a vCenter credential — none of which have a published format for GitHub to
   recognise. That is exactly the class of secret this repo handles, which is why real
   values live in `PKR_VAR_*` environment variables and only `*.pkrvars.hcl.example` with
   dummy values is committed.
3. **Gates 1 and 3 fail differently, which is the argument for having both.** Gate 1 caught
   the random AWS secret on entropy where gate 3's pattern matching did not. Gate 3 catches
   provider formats that gitleaks' ruleset may lack, server-side, unbypassably. Neither is
   a superset of the other.

## Reproducing this

```bash
git checkout -b test/push-protection-proof
printf 'slack_webhook = https://hooks.slack.com/services/T%s/B%s/%s\n' \
  "$(tr -dc 'A-Z0-9' </dev/urandom | head -c10)" \
  "$(tr -dc 'A-Z0-9' </dev/urandom | head -c10)" \
  "$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c24)" > leaked-credentials.txt
git add leaked-credentials.txt
git commit --no-verify -m "chore: this must be rejected by the server"
git push -u origin test/push-protection-proof   # expect: GH013, remote rejected
git checkout main && git branch -D test/push-protection-proof
```

Use a checksum-free provider format. Do not use an AWS key, for the reasons above.
