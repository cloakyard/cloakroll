## Change

Describe the problem and resulting behavior. Promote verified work from `dev` to `main`.

## Validation

Record the checks actually run, including native builds/tests/lint for app changes and
`npm run verify` / `npm run check:worker` for website changes. Link the dated evidence.
List remaining hardware, accessibility or distribution gates separately.

## Deployment

State whether the website output changes. Cloudflare production uses `main`; `dev` is retained
for ongoing work. Merge with a merge commit, then fast-forward `dev` to the merged `main`.
