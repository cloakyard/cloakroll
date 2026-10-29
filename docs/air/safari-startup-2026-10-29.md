# Air 1.2.7 — Safari artwork startup, 29 October 2026

WebKit rounds the reported CPU count to four on devices with fewer than eight
cores. The shared artwork lifecycle incorrectly treated that value as a reason
to disable finite transform/opacity animations. A WebKit reproduction against
all five live sites produced `constrained`, zero animations and no console errors.

The canonical lifecycle now ignores CPU count for this lightweight artwork.
Reduced motion, forced colours, Save-Data, reported memory at or below 4 GiB,
missing animation APIs, offscreen/hidden suspension and finite cleanup remain.
No user-agent detection, new dependency, timing, artwork, CSS, task UI or output
change. The heavier reference shader keeps its existing resource policy.

[WebKit implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/page/NavigatorBase.cpp#L172-L182)
explains why CPU count cannot serve as this device-performance test.

Verification passes: 44 moving layouts for this app across WebKit/Chrome,
including all eleven required sizes in both themes, eight fallback visits and
two lifecycle journeys. The shared matrix proves progressing timelines, changing
composited artwork, finite completion, offscreen suspension and immediate preference
changes. Product checks/build/provenance and the applicable artwork suites pass.
PDF passes 461 units plus real upload/merge entry; Resume passes all 373 production
tests with zero skips on the complete rerun. Initial harness failures and the
previously observed Resume contact-node test race are retained in the family audit.

See the [full audit and evidence](https://github.com/cloakyard/cloakyard/blob/dev/docs/air/safari-startup-2026-10-29.md).
PR #4 is merged at `caa5d16` and deployed. Dev was fast-forwarded to main.
All eleven live public files match the tested build (eight raw hashes and three
HTML files after removing only Cloudflare’s detection injection). Live WebKit
passes both phone themes, four fallbacks and the full lifecycle journey. Desktop WebKit with a mobile viewport
and four-thread/no-memory hints is browser-engine evidence, not a physical iPhone
or Low Power Mode acceptance result. CloakIMG remains parked; native apps and
KERR are unchanged. Existing full-product and device gates remain open.


## Build configuration follow-up

The production build `03a34654-cb02-4bd5-bfe7-cdbfe757ff7d` serves this revision.
The later dev build passed verification but `npx wrangler preview` failed because
its required `previews` block was absent. Add the empty block for this static site;
assets stay at the top level and production routes are not copied into previews.
See [Cloudflare's configuration](https://developers.cloudflare.com/workers/previews/configuration/).
Production remains `main` with `npx wrangler deploy`; preview URLs stay disabled.

An attempted dashboard-only switch to `versions upload` did not change the command
used by the next dev build. That setting was restored to `npx wrangler preview`;
the final correction is the repository configuration, with no net dashboard change.
A redundant retry was cancelled. Final site verification and Worker dry-run pass;
application output remains byte-identical. No native code, permissions or data
bindings changed. PR #5 carries the rollout documentation and preview configuration.
