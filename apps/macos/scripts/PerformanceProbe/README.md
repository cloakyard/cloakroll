# Generated catalog performance probe

This separate command-line package measures the public core APIs with generated metadata.
It does not access an iPhone, a user's backup folder or the app's database. It creates one
uniquely named temporary database and removes that fixture folder when the run ends normally.

From this directory:

```sh
GIT_CONFIG_COUNT=0 swift build -c release
.build/release/ScaleProbe 10000 > /tmp/cloakroll-scale-10000.jsonl
.build/release/ScaleProbe 50000 > /tmp/cloakroll-scale-50000.jsonl
.build/release/ScaleProbe 100000 > /tmp/cloakroll-scale-100000.jsonl
```

Run the executable sequentially in fresh processes, without concurrent builds, for comparable
timings. Only 10,000, 50,000 and 100,000 logical items are accepted. Each catalog includes 25%
Live Photos, so it has 1.25 original-resource records per item. There are no image bytes.

JSON lines report fixture counts, projection, identity preparation, public session registration,
empty/full/single-item candidate queries, completion query plans, 100 completion lookups and
process peak resident memory. Take the median of the three runs for projection, identity and
populated candidate queries. Registration and the completion-lookup group are single measures.
On macOS, `peakRSS` is bytes from `getrusage`; it includes the entire process and all earlier
stages, not just the currently reported stage.

History rows are seeded directly into this disposable database in one transaction, after public
session registration. This isolates reading/matching from per-original transfer, hashing, fsync
and transactional completion costs. Seeded rows are generated test metadata, **not verified
media**. The probe checks returned counts, but correctness is covered separately by core tests.

These numbers cannot establish app startup time, scroll smoothness, main-thread stalls, a cache
memory plateau, USB throughput or physical interruption safety. Keep those acceptance checks
separate. Do not point this probe at a real database or add personal media to its fixtures.
