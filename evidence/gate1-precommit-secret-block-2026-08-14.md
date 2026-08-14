# Evidence — gate 1 blocks a secret before a commit object exists

**Date:** 2026-08-14
**Gate:** `pre-commit` / gitleaks 8.30.1, on the developer's machine
**Acceptance criterion:** phase 0 — "a test commit containing a fake AWS key is blocked
locally by pre-commit"

Terminal output is reproduced verbatim except that generated key material is redacted at
capture time (gitleaks' own `--redact` did most of it) and ANSI colour codes are stripped.

---

## Attempt 1 — the test that *should* have failed, and did not

The first attempt used AWS's canonical documentation credential pair,
`AKIAIOSFODNN7EXAMPLE` / `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`, which is what most
people reach for when testing a secret scanner.

```
$ git add leaked-credentials.txt
$ git commit -S -m "chore: attempt to commit a fake aws key"
Detect hardcoded secrets.................................................Passed
...
[test/secret-scanning-proof e4a5605] chore: attempt to commit a fake aws key
 1 file changed, 4 insertions(+)
 create mode 100644 leaked-credentials.txt
```

**The commit succeeded.** Confirmed directly against the scanner:

```
$ gitleaks dir --redact --no-banner canonical.txt
INF no leaks found
```

This is gitleaks behaving correctly, not a bug. The canonical AWS example pair is
allowlisted upstream precisely because it appears in vast quantities of documentation and
would otherwise generate constant false positives.

**Why this matters more than the passing test below.** Validating a secret scanner with a
vendor's published example credential proves nothing, because that value is the one string
guaranteed to be allowlisted. A team that tests its gate this way concludes the gate works
and ships. This is recorded first, and kept, because the failure is the more instructive
half of the exercise.

The commit was discarded (`git reset --hard HEAD~1`) and the branch deleted; the fake
credential never reached `main` and is not in this repository's history.

---

## Attempt 2 — a fake key that is not allowlisted

Regenerated as a random `AKIA` + 16 uppercase alphanumerics access key ID and a random
40-character secret, matching the real format without being a published example.

```
$ git add leaked-credentials.txt
$ git commit -S -m "chore: attempt to commit a fake aws key"
Detect hardcoded secrets.................................................Failed
- hook id: gitleaks
- exit code: 1

    ○
    │╲
    │ ○
    ○ ░
    ░    gitleaks

Finding:     aws_secret_access_key = REDACTED
Secret:      REDACTED
RuleID:      generic-api-key
Entropy:     4.665311
File:        leaked-credentials.txt
Line:        2
Fingerprint: leaked-credentials.txt:generic-api-key:2

INF 0 commits scanned.
INF scanned ~106 bytes (106 bytes) in 34.7ms
WRN leaks found: 1
```

Commit count on the branch afterwards: **1** — the branch point. The commit was refused
and no object containing the credential was written.

---

## What the finding actually says, read carefully

The rule that fired was **`generic-api-key`** on the secret, at entropy 4.67 — not an
AWS-specific rule. Checked separately, the AWS access key ID pattern does fire on its own:

```
$ gitleaks dir --redact --no-banner idonly.txt
WRN leaks found: 1
```

So both halves of the pair are detectable. But the block in attempt 2 came from a generic
high-entropy heuristic, and that carries a consequence worth stating: **a low-entropy
secret in an unrecognised format — a short database password, a bespoke internal token —
would pass this gate.** gitleaks finds what matches a rule or looks random. It does not
find what merely *is* a secret.

That limitation is why the same control exists at three levels rather than one:

| Gate | Catches what this one missed |
|---|---|
| 1 — pre-commit (this document) | — |
| 2 — `security.yml` on PR | The same scan, but over full history and unbypassable by `git commit --no-verify` |
| 3 — GitHub push protection | GitHub's partner pattern set, including providers gitleaks has no rule for, enforced server-side |

None of the three catches a low-entropy bespoke credential. The honest mitigation for that
is `.gitignore` plus `*.pkrvars.hcl.example` conventions plus code review — not a scanner.
Recorded in [`../docs/SHIFT-LEFT.md`](../docs/SHIFT-LEFT.md).

## Reproducing this

```bash
KEYID="AKIA$(tr -dc 'A-Z0-9' </dev/urandom | head -c16)"
SECRET="$(tr -dc 'A-Za-z0-9+/' </dev/urandom | head -c40)"
printf 'aws_access_key_id = %s\naws_secret_access_key = %s\n' "$KEYID" "$SECRET" \
  > leaked-credentials.txt
git add leaked-credentials.txt && git commit -m "chore: this must fail"
# expect: Detect hardcoded secrets ... Failed
git reset && rm leaked-credentials.txt
```
