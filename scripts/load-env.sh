# Sourced by the build scripts. Reads build-time secrets from the untracked .env
# without executing it. A variable already set in the environment wins.
if [[ -f .env ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(ANTIGRAVITY_CLIENT_SECRET)=(.*)$ ]] || continue
    name="${BASH_REMATCH[2]}" value="${BASH_REMATCH[3]}"
    value="${value%\"}"; value="${value#\"}"; value="${value%\'}"; value="${value#\'}"
    [[ -n "${!name:-}" ]] || export "$name=$value"
  done < .env
fi
