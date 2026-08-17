# Q12 — Check-report fixture

**Owns:** `Tests/Fixtures/check-happy/` + one test method.

`boris check --input Stunts/happy/content --format json --report …`
from the happy project root. Check in the JSON. Decode as
`AnalysisReport`. Add `testHappyCheck` to ContractTests.
