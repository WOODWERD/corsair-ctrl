#!/bin/bash
# Prepares docs/ for MkDocs: the site reuses the repo-level files (README -> Home, changelog, notices).
# Used by the Pages workflow and for a local preview.
set -euo pipefail
cd "$(dirname "$0")/.."
cp README.md docs/index.md
sed -i.bak -e 's|](docs/|](|g' -e 's|](THIRD_PARTY_NOTICES.md)|](notices.md)|g' -e 's|](CHANGELOG.md)|](changelog.md)|g' \
  -e 's|](app/web/index.html)|](https://github.com/WOODWERD/corsair-ctrl/blob/main/app/web/index.html)|g' docs/index.md
rm -f docs/index.md.bak
cp THIRD_PARTY_NOTICES.md docs/notices.md
printf '\n\n## License\n\n```\n' >> docs/notices.md; cat LICENSE >> docs/notices.md; printf '\n```\n' >> docs/notices.md
cp CHANGELOG.md docs/changelog.md
