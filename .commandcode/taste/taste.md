# Taste profile

## Workflow
- For standards/protocol conformance work (e.g., OAI-PMH, XSD-validated formats), the user wants the implementation checked against the *official* specification source (openarchives.org docs, official XSDs) first — not fixed from memory or assumption. Strong preference for the pattern: study official spec → audit current code against it → apply fixes. Confidence: 0.9
- Validate standards-conformance output against the official schema file (e.g., xmllint against the real OAI-PMH.xsd fetched from the spec publisher), not just tests. Confidence: 0.8
- Run the project's full pre-commit gate (`mix precommit` — format, compile with warnings-as-errors, credo, full test suite) before declaring work done, per the project's AGENTS.md guidelines. Confidence: 0.9
- When unrelated test failures appear, verify they pre-date the change (e.g., re-run a failing test against a `git stash`ed pristine tree) rather than assuming blame or ignoring them. Confidence: 0.8

## Code quality
- High bar for correctness details in standards-facing code: exact element ordering, bare base URL for badVerb/badArgument echoes, empty resumptionToken on final pages, security gating (GetRecord visibility checks) — fixes were expected to be spec-exhaustive, not minimal patches. Confidence: 0.8
