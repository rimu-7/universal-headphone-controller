#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GH_REPO:?Set GH_REPO}"
: "${GITHUB_SHA:?Set GITHUB_SHA}"
: "${RELEASE_TAG:?Set RELEASE_TAG}"
: "${RELEASE_TITLE:?Set RELEASE_TITLE}"
ASSETS=(release-assets/HeadphoneController.dmg release-assets/HeadphoneController-update.zip release-assets/appcast.xml release-assets/SHA256SUMS)
for asset in "${ASSETS[@]}"; do test -s "$asset"; done
if gh release view "$RELEASE_TAG" --repo "$GH_REPO" --json isDraft,targetCommitish > release-assets/existing-release.json 2>/dev/null; then
    RESULT="$(python3 - "$GITHUB_SHA" <<'PY'
import json, sys
with open('release-assets/existing-release.json') as f:
    release = json.load(f)
if release['targetCommitish'] != sys.argv[1]:
    raise SystemExit('Existing release tag points at a different commit')
print('draft' if release['isDraft'] else 'published')
PY
)"
    if [ "$RESULT" = published ]; then
        echo 'This tested build is already published; leaving its assets and latest-release pointer unchanged.'
        exit 0
    fi
else
    gh release create "$RELEASE_TAG" --repo "$GH_REPO" --target "$GITHUB_SHA" \
        --title "$RELEASE_TITLE" --draft --generate-notes
fi
# Users only see the release after every signed asset is uploaded successfully.
gh release upload "$RELEASE_TAG" --repo "$GH_REPO" --clobber "${ASSETS[@]}"
gh release edit "$RELEASE_TAG" --repo "$GH_REPO" --draft=false --latest
