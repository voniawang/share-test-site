#!/usr/bin/env bash

set -euo pipefail

OWNER="${GITHUB_OWNER:-voniawang}"
REPO_NAME="${REPO_NAME:-share-test-site}"
SITE_DIR="$(cd "$(dirname "$0")" && pwd)"
API_ROOT="https://api.github.com"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "Missing GH_TOKEN. Example:"
  echo 'export GH_TOKEN="github_pat_xxx"'
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required."
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required."
  exit 1
fi

echo "Preparing GitHub Pages deployment for ${OWNER}/${REPO_NAME}..."

touch "${SITE_DIR}/.nojekyll"

create_payload="$(python3 - <<'PY'
import json
print(json.dumps({
    "name": "share-test-site",
    "private": False,
    "description": "Static site published from local HTML for GitHub Pages"
}))
PY
)"

repo_status="$(curl -s -o /tmp/share-test-repo.json -w "%{http_code}" \
  -H "Authorization: Bearer ${GH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "${API_ROOT}/repos/${OWNER}/${REPO_NAME}")"

if [[ "${repo_status}" == "404" ]]; then
  echo "Creating repository ${OWNER}/${REPO_NAME}..."
  create_payload="$(REPO_NAME="${REPO_NAME}" python3 - <<'PY'
import json, os
print(json.dumps({
    "name": os.environ["REPO_NAME"],
    "private": False,
    "description": "Static site published from local HTML for GitHub Pages",
    "auto_init": False
}))
PY
)"
  curl -sS -X POST \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -d "${create_payload}" \
    "${API_ROOT}/user/repos" >/tmp/share-test-create.json
elif [[ "${repo_status}" != "200" ]]; then
  echo "Failed to query repository. HTTP ${repo_status}"
  cat /tmp/share-test-repo.json
  exit 1
else
  echo "Repository already exists. Reusing ${OWNER}/${REPO_NAME}..."
fi

cd "${SITE_DIR}"

if [[ ! -d .git ]]; then
  git init
fi

git checkout -B main
git add .

if ! git diff --cached --quiet; then
  git -c user.name="${OWNER}" -c user.email="${OWNER}@users.noreply.github.com" commit -m "Deploy static site"
fi

REMOTE_URL="https://x-access-token:${GH_TOKEN}@github.com/${OWNER}/${REPO_NAME}.git"

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "${REMOTE_URL}"
else
  git remote add origin "${REMOTE_URL}"
fi

echo "Pushing site files..."
git push -u origin main --force

echo "Enabling GitHub Pages..."
pages_payload="$(python3 - <<'PY'
import json
print(json.dumps({"source": {"branch": "main", "path": "/"}}))
PY
)"

pages_status="$(curl -s -o /tmp/share-test-pages.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer ${GH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -d "${pages_payload}" \
  "${API_ROOT}/repos/${OWNER}/${REPO_NAME}/pages")"

if [[ "${pages_status}" == "409" || "${pages_status}" == "422" ]]; then
  curl -sS -o /tmp/share-test-pages-update.json \
    -X PUT \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -d "${pages_payload}" \
    "${API_ROOT}/repos/${OWNER}/${REPO_NAME}/pages" >/dev/null
elif [[ "${pages_status}" != "201" ]]; then
  echo "GitHub Pages API returned HTTP ${pages_status}"
  cat /tmp/share-test-pages.json
  exit 1
fi

echo
echo "Deployment requested successfully."
echo "GitHub Pages URL:"
echo "https://${OWNER}.github.io/${REPO_NAME}/"
echo
echo "If the page is not live yet, wait 1-3 minutes and refresh."
