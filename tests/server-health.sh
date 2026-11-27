#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Server health workflow: Java status and Bedrock (NetherNet signaling, with a
# RakNet fallback) are queried, a miss counts only after a retry, and the issue
# opens, updates and closes from the set of ports that failed. An unset
# MC_HEALTH_HOST skips with a notice.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

if ! date -u -d '2020-01-01T00:00:00Z' +%s >/dev/null 2>&1; then
    echo "server-health tests need GNU date" >&2
    exit 1
fi

fail() {
    echo "server-health: $*" >&2
    exit 1
}

assert_eq() {
    local desc="$1" want="$2" got="$3"
    if [[ "$want" != "$got" ]]; then
        printf 'want: %s\ngot:  %s\n' "$want" "$got" >&2
        fail "$desc"
    fi
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if ! printf '%s\n' "$haystack" | grep -F -q -- "$needle"; then
        printf '%s\n' "$haystack" >&2
        fail "missing ($desc): $needle"
    fi
}

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if printf '%s\n' "$haystack" | grep -F -q -- "$needle"; then
        printf '%s\n' "$haystack" >&2
        fail "unexpected ($desc): $needle"
    fi
}

WF="${ROOT}/.github/workflows/server-health.yml"
workflow=$(cat "${WF}")

assert_contains "health workflow reads the host variable" \
    "${workflow}" 'vars.MC_HEALTH_HOST'
assert_contains "health workflow reads the host secret" \
    "${workflow}" 'secrets.MC_HEALTH_HOST'
assert_contains "health workflow defaults the java port" \
    "${workflow}" "MC_HEALTH_JAVA_PORT || '25565'"
assert_contains "health workflow defaults the bedrock port" \
    "${workflow}" "MC_HEALTH_BEDROCK_PORT || '19132'"
assert_contains "health workflow defaults the bedrock mode" \
    "${workflow}" "MC_HEALTH_BEDROCK_MODE || 'nethernet'"
assert_contains "health workflow describes NetherNet signaling" \
    "${workflow}" "NetherNet HTTP, any status"
assert_contains "health workflow keeps the RakNet fallback" \
    "${workflow}" "A RakNet unconnected ping on UDP"
assert_contains "health workflow runs every 15 minutes" \
    "${workflow}" '*/15 * * * *'
assert_contains "health workflow can be run on demand" \
    "${workflow}" "workflow_dispatch:"
assert_contains "health workflow writes issues" \
    "${workflow}" "issues: write"
assert_contains "health workflow stays on ubuntu" \
    "${workflow}" "runs-on: ubuntu-latest"
assert_not_contains "health workflow has no macOS runner" \
    "${workflow}" "macos"
assert_contains "health workflow passes per-port detail" \
    "${workflow}" "steps.probe.outputs.detail"
assert_contains "health workflow skips when the host is unset" \
    "${workflow}" "steps.probe.outputs.skipped"
assert_contains "health workflow still closes a recovered issue" \
    "${workflow}" "gh issue close"
dollar='$'
down_marker="port(s): **${dollar}{DOWN}**"
assert_contains "health workflow still names the failed ports" \
    "${workflow}" "${down_marker}"
assert_contains "health workflow still waits 6 hours between repeats" \
    "${workflow}" "21600"
assert_not_contains "health workflow pins no third-party action" \
    "${workflow}" "uses:"

# YAML's block scalar strips the run-step indent. The markers stay in the file
# and out of the script that actually runs.
extract_block() {
    local begin="$1" end="$2" dest="$3"
    awk -v begin="${begin}" -v end="${end}" '
        index($0, begin) { capture = 1; next }
        index($0, end) { capture = 0 }
        capture {
            sub(/^          /, "")
            print
        }
    ' "${WF}" > "${dest}"
}

extract_block "# mc-server-health-probe-begin" "# mc-server-health-probe-end" \
    "${WORK}/probe.py"
extract_block "# mc-server-health-issue-begin" "# mc-server-health-issue-end" \
    "${WORK}/issue.sh"

python3 -m py_compile "${WORK}/probe.py"
bash -n "${WORK}/issue.sh"
shellcheck -s bash "${WORK}/issue.sh"
python3 "${ROOT}/tests/server-health-driver.py" "${WORK}/probe.py" "${WORK}"

# Issue open / update / close, with gh stubbed out.
STUB="${WORK}/bin"
mkdir -p "${STUB}"
cat > "${STUB}/gh" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "${GH_LOG}"
jq_filter=""
args=("$@")
i=0
while [[ ${i} -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
        --jq)
            jq_filter="${args[$((i + 1))]}"
            i=$((i + 2))
            continue
            ;;
        --body)
            printf '%s\n' "${args[$((i + 1))]}" > "${GH_LAST_BODY}"
            i=$((i + 2))
            continue
            ;;
    esac
    i=$((i + 1))
done
cmd="${1:-}"
sub="${2:-}"
if [[ "${cmd}" == "label" ]]; then
    exit 0
fi
if [[ "${cmd}" == "issue" && "${sub}" == "list" ]]; then
    if [[ -z "${GH_OPEN_NUMBER:-}" ]]; then
        printf '[]\n' | jq -r "${jq_filter}"
    else
        printf '[{"number":%s}]\n' "${GH_OPEN_NUMBER}" | jq -r "${jq_filter}"
    fi
    exit 0
fi
if [[ "${cmd}" == "issue" && "${sub}" == "view" ]]; then
    jq -r "${jq_filter}" "${GH_VIEW_JSON}"
    exit 0
fi
if [[ "${cmd}" == "issue" && ( "${sub}" == "create" || "${sub}" == "comment" || "${sub}" == "close" ) ]]; then
    printf '%s\n' "${sub}" >> "${GH_ACTIONS}"
    exit 0
fi
printf 'stub gh: unhandled: %s\n' "$*" >&2
exit 1
EOF
chmod +x "${STUB}/gh"

run_issue() {
    local number="$1" down="$2" detail="$3" skipped="${4:-}"
    : > "${WORK}/gh.log"
    : > "${WORK}/actions"
    : > "${WORK}/body"
    env -i PATH="${STUB}:/usr/bin:/bin" \
        GH_LOG="${WORK}/gh.log" \
        GH_LAST_BODY="${WORK}/body" \
        GH_ACTIONS="${WORK}/actions" \
        GH_OPEN_NUMBER="${number}" \
        GH_VIEW_JSON="${WORK}/view.json" \
        ISSUE_TITLE="Server down" \
        ISSUE_LABEL="server-down" \
        GITHUB_REPOSITORY="KevinTCoughlin/minecraft-server" \
        GITHUB_SERVER_URL="https://github.com" \
        GITHUB_RUN_ID="99" \
        MC_HEALTH_HOST="203.0.113.10" \
        MC_HEALTH_JAVA_PORT="25565" \
        MC_HEALTH_BEDROCK_PORT="19132" \
        DOWN="${down}" \
        DETAIL="${detail}" \
        TRIES="2" \
        SKIPPED="${skipped}" \
        bash "${WORK}/issue.sh" > "${WORK}/issue.out" 2> "${WORK}/issue.err"
}

detail=$'- 25565 up: Paper 26.3, players 1/20\n- 19132 down: no NetherNet HTTP response or RakNet unconnected pong'

printf '%s\n' '{"comments":[]}' > "${WORK}/view.json"
run_issue "" "" "${detail}" "true"
assert_eq "unset host does not touch issues" "" "$(cat "${WORK}/actions")"

run_issue "" "" "${detail}"
assert_eq "healthy run with no issue does nothing" "" "$(cat "${WORK}/actions")"

run_issue "41" "" "${detail}"
assert_contains "recovery comments" "$(cat "${WORK}/actions")" "comment"
assert_contains "recovery closes" "$(cat "${WORK}/actions")" "close"
assert_contains "recovery names both ports" "$(cat "${WORK}/body")" "Java 25565 and Bedrock 19132"
assert_contains "recovery keeps the per-port lines" "$(cat "${WORK}/body")" "Paper 26.3"
assert_not_contains "recovery is not a down comment" "$(cat "${WORK}/body")" "port(s):"

run_issue "" "19132" "${detail}"
assert_eq "first failure opens one issue" "create" "$(cat "${WORK}/actions")"
body=$(cat "${WORK}/body")
assert_contains "failure names the dead port" "${body}" "port(s): **19132**"
assert_contains "failure shows the live port" "${body}" "25565 up: Paper 26.3"
assert_contains "failure shows the dead port" "${body}" "19132 down: no NetherNet HTTP response or RakNet unconnected pong"
assert_contains "failure describes NetherNet signaling" "${body}" "NetherNet HTTP, any status"
assert_contains "failure keeps the RakNet fallback" "${body}" "RakNet unconnected ping on UDP"
assert_contains "failure still points at the run" "${body}" "actions/runs/99"
assert_contains "failure names the status command" "${body}" "mc-server-manager status"
assert_contains "failure says how many tries" "${body}" "after 2 tries"

recent=$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)
cat > "${WORK}/view.json" <<EOF
{"comments":[
  {"body":"Recovered at 2020-01-01 00:00 UTC","createdAt":"2020-01-01T00:00:00Z"},
  {"body":"Down at 2026-11-26 00:00 UTC: no Java status or RakNet ping reply from 203.0.113.10 on port(s): **19132** after 2 tries.","createdAt":"${recent}"}
]}
EOF
run_issue "41" "19132" "${detail}"
assert_eq "same ports inside 6 hours do not comment again" "" "$(cat "${WORK}/actions")"

old=$(date -u -d '8 hours ago' +%Y-%m-%dT%H:%M:%SZ)
cat > "${WORK}/view.json" <<EOF
{"comments":[
  {"body":"Down at 2026-11-26 00:00 UTC: no Java status or RakNet ping reply from 203.0.113.10 on port(s): **19132** after 2 tries.","createdAt":"${old}"}
]}
EOF
run_issue "41" "19132" "${detail}"
assert_eq "same ports after 6 hours comment again" "comment" "$(cat "${WORK}/actions")"

cat > "${WORK}/view.json" <<EOF
{"comments":[
  {"body":"Down at 2026-11-26 00:00 UTC: no Java status or RakNet ping reply from 203.0.113.10 on port(s): **19132** after 2 tries.","createdAt":"${recent}"}
]}
EOF
run_issue "41" "25565" "${detail}"
assert_eq "a different dead port comments" "comment" "$(cat "${WORK}/actions")"
assert_contains "the new dead port is named" "$(cat "${WORK}/body")" "port(s): **25565**"

cat > "${WORK}/view.json" <<EOF
{"comments":[
  {"body":"Down at 2026-11-26 00:00 UTC: no Java status or RakNet ping reply from 203.0.113.10 on port(s): **25565 19132** after 2 tries.","createdAt":"${recent}"}
]}
EOF
run_issue "41" "25565 19132" "${detail}"
assert_eq "both ports still down does not comment again" "" "$(cat "${WORK}/actions")"

printf '%s\n' '{"comments":[]}' > "${WORK}/view.json"
run_issue "41" "19132" "${detail}"
assert_eq "an open issue with no down comment is updated" "comment" "$(cat "${WORK}/actions")"

echo "server health issue tests passed"
