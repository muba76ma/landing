#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

cd "$HOME/landing"
BRANCH="main"
MSG=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    -m) MSG="$2"; shift 2 ;;
    -f|--force) FORCE=1; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if git diff --quiet && git diff --cached --quiet \
   && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  echo "Nothing to deploy."
  exit 0
fi

git --no-pager status --short
echo
git --no-pager diff --stat

if [ "$FORCE" != "1" ]; then
  read -rp "Deploy these changes? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || { echo "Aborted."; exit 1; }
fi

MSG="${MSG:-Update $(date -u +%Y-%m-%dT%H:%M:%SZ)}"
git add -A
git commit -m "$MSG"
git push origin "$BRANCH"

echo "Waiting for GitHub Pages build…"
STATUS="unknown"
for i in $(seq 1 60); do
  STATUS=$(gh api "repos/{owner}/{repo}/pages" -q '.status // "pending"' 2>/dev/null || echo "error")
  printf "  [%02d] %s\n" "$i" "$STATUS"
  case "$STATUS" in
    built) break ;;
    errored)
      echo "Build failed:"
      gh api "repos/{owner}/{repo}/pages/builds/latest" -q '.error.message // empty' || true
      exit 1 ;;
  esac
  sleep 5
done

URL=$(gh api "repos/{owner}/{repo}/pages" -q .html_url)
echo "Live: $URL"

if command -v curl >/dev/null; then
  code=$(curl -s -o /dev/null -w '%{http_code}' "$URL?v=$(date +%s)")
  echo "HTTP $code  $URL"
  [ "$code" = "200" ] || echo "⚠️  Not 200 yet — CDN may still be warming up."
fi
