# Q24 — Textile stunt corpus

**Owns:** `Stunts/`, `Tests/Fixtures/`, `scripts/stunt-from-testdata.sh`.

The stunt corpus covers Markdown (happy, broken-*) and Cooklang
(cook-one). Add a **Textile**-format corpus (`input_format: textile`) so
the app's input-format surface (M6: drawer shows profile `input_format`)
has dogfood coverage:

- `Stunts/happy-textile/` with `boris.json` (`input_format: "textile"`),
  a couple of pages, and a link between them
- A broken-textile case (e.g. a link to a missing page) if the format
  supports it
- Harvested fixtures via `scripts/stunt-from-testdata.sh` + decode tests
  in `ContractDecodeTests`

If Textile fixtures can't be harvested without a boris binary, commit the
checked-in JSON like the existing stunts (CI runs with `SKIP_EMBED_BORIS`).

Gate: `make test` — new corpus fixtures decode; `Stunts/README.md` lists
the new corpora.
