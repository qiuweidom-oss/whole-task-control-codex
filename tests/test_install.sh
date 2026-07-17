#!/bin/sh
set -eu

PACKAGE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BEGIN_MARKER='<!-- WHOLE-TASK-CONTROL BEGIN (Codex root only) -->'
END_MARKER='<!-- WHOLE-TASK-CONTROL END -->'

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

assert_utf8_bom() {
  bytes=$(od -An -tx1 -N3 "$1" | tr -d ' \n')
  [ "$bytes" = 'efbbbf' ] || fail "$1 is not UTF-8 BOM encoded"
}

assert_contains() {
  grep -Fq "$2" "$1" || fail "$1 does not contain: $2"
}

assert_not_contains() {
  if grep -Fq "$2" "$1"; then
    fail "$1 unexpectedly contains: $2"
  fi
}

if command -v shasum >/dev/null 2>&1; then
  HASH_TOOL='shasum'
elif command -v sha256sum >/dev/null 2>&1; then
  HASH_TOOL='sha256sum'
else
  fail 'neither shasum nor sha256sum is available; SHA-256 assertions cannot run'
fi

hash_file() {
  case "$HASH_TOOL" in
    shasum)
      hash_output=$(shasum -a 256 "$1") || fail "shasum failed for $1"
      ;;
    sha256sum)
      hash_output=$(sha256sum "$1") || fail "sha256sum failed for $1"
      ;;
    *)
      fail "unsupported hash tool: $HASH_TOOL"
      ;;
  esac
  hash_value=${hash_output%% *}
  if [ "${#hash_value}" -ne 64 ]; then
    fail "hash command returned an empty or invalid SHA-256 digest for $1"
  fi
  case "$hash_value" in
    *[!0-9A-Fa-f]*|'') fail "hash command returned an empty or invalid SHA-256 digest for $1" ;;
  esac
  printf '%s\n' "$hash_value"
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
}

assert_file "$PACKAGE_DIR/install.sh"
assert_file "$PACKAGE_DIR/uninstall.sh"
assert_file "$PACKAGE_DIR/restore.sh"
assert_file "$PACKAGE_DIR/install.ps1"
assert_file "$PACKAGE_DIR/uninstall.ps1"
assert_file "$PACKAGE_DIR/restore.ps1"
assert_file "$PACKAGE_DIR/lib.ps1"
assert_file "$PACKAGE_DIR/INSTALL.txt"
assert_file "$PACKAGE_DIR/tests/test_install.ps1"
assert_file "$PACKAGE_DIR/global-rule.txt"
assert_file "$PACKAGE_DIR/whole-task-control/SKILL.md"
assert_file "$PACKAGE_DIR/whole-task-control/agents/openai.yaml"
assert_file "$PACKAGE_DIR/VERSION"
[ "$(sed -n '1p' "$PACKAGE_DIR/VERSION")" = '2.1.1' ] || fail 'VERSION is not 2.1.1'

for powershell_file in \
  "$PACKAGE_DIR/install.ps1" \
  "$PACKAGE_DIR/uninstall.ps1" \
  "$PACKAGE_DIR/restore.ps1" \
  "$PACKAGE_DIR/lib.ps1" \
  "$PACKAGE_DIR/tests/test_install.ps1"; do
  assert_utf8_bom "$powershell_file"
done

assert_contains "$PACKAGE_DIR/tests/test_install.sh" 'command -v sha256sum'
assert_contains "$PACKAGE_DIR/tests/test_install.sh" 'hash command returned an empty or invalid SHA-256 digest'
assert_contains "$PACKAGE_DIR/lib.ps1" 'Assert-WtcWindowsPathBudget'
assert_contains "$PACKAGE_DIR/whole-task-control/SKILL.md" 'exist and are relevant to the current task'
assert_contains "$PACKAGE_DIR/whole-task-control/agents/openai.yaml" 'allow_implicit_invocation: true'

sh -n "$PACKAGE_DIR/install.sh"
sh -n "$PACKAGE_DIR/uninstall.sh"
sh -n "$PACKAGE_DIR/restore.sh"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/whole-task-control-v2-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

# Clean Codex: standalone install, no Claude touch, repeated install is idempotent.
CLEAN="$TEST_ROOT/clean"
mkdir -p "$CLEAN/.claude"
printf '%s\n' 'CLAUDE-KEEP' > "$CLEAN/.claude/KEEP"
CLAUDE_HASH=$(hash_file "$CLEAN/.claude/KEEP")
HOME="$CLEAN" sh "$PACKAGE_DIR/install.sh" >/dev/null
assert_file "$CLEAN/.codex/skills/whole-task-control/SKILL.md"
assert_file "$CLEAN/.codex/skills/whole-task-control/.managed-by-whole-task-control"
assert_contains "$CLEAN/.codex/AGENTS.md" "$BEGIN_MARKER"
assert_contains "$CLEAN/.codex/AGENTS.md" '自包含、低风险、单步'
assert_contains "$CLEAN/.codex/AGENTS.md" '子代理禁止加载'
FIRST_AGENTS_HASH=$(hash_file "$CLEAN/.codex/AGENTS.md")
HOME="$CLEAN" sh "$PACKAGE_DIR/install.sh" >/dev/null
[ "$FIRST_AGENTS_HASH" = "$(hash_file "$CLEAN/.codex/AGENTS.md")" ] || fail 'repeat install changed AGENTS.md'
[ "$(grep -Fxc "$BEGIN_MARKER" "$CLEAN/.codex/AGENTS.md")" -eq 1 ] || fail 'duplicate begin marker'
[ "$CLAUDE_HASH" = "$(hash_file "$CLEAN/.claude/KEEP")" ] || fail 'Claude file changed'

# Existing unrelated global rules must coexist unchanged.
COEXIST="$TEST_ROOT/coexist"
mkdir -p "$COEXIST/.codex"
printf '%s\n' 'EXISTING-BEGIN' 'OTHER-INDEPENDENT-RULE' 'EXISTING-END' > "$COEXIST/.codex/AGENTS.md"
HOME="$COEXIST" sh "$PACKAGE_DIR/install.sh" >/dev/null
assert_contains "$COEXIST/.codex/AGENTS.md" 'OTHER-INDEPENDENT-RULE'
assert_contains "$COEXIST/.codex/AGENTS.md.before-whole-task-control" 'OTHER-INDEPENDENT-RULE'

# Reversed markers must fail before any mutation.
REVERSED="$TEST_ROOT/reversed"
mkdir -p "$REVERSED/.codex"
printf '%s\n' 'KEEP-BEFORE' "$END_MARKER" 'KEEP-MIDDLE' "$BEGIN_MARKER" 'KEEP-AFTER' > "$REVERSED/.codex/AGENTS.md"
REVERSED_HASH=$(hash_file "$REVERSED/.codex/AGENTS.md")
expect_failure env HOME="$REVERSED" sh "$PACKAGE_DIR/install.sh"
[ "$REVERSED_HASH" = "$(hash_file "$REVERSED/.codex/AGENTS.md")" ] || fail 'reversed markers mutated AGENTS.md'
[ ! -e "$REVERSED/.codex/skills/whole-task-control" ] || fail 'reversed marker failure half-installed skill'

# Unmatched markers must also fail before skill copy.
UNMATCHED="$TEST_ROOT/unmatched"
mkdir -p "$UNMATCHED/.codex"
printf '%s\n' 'KEEP' "$BEGIN_MARKER" 'NO-END' > "$UNMATCHED/.codex/AGENTS.md"
UNMATCHED_HASH=$(hash_file "$UNMATCHED/.codex/AGENTS.md")
expect_failure env HOME="$UNMATCHED" sh "$PACKAGE_DIR/install.sh"
[ "$UNMATCHED_HASH" = "$(hash_file "$UNMATCHED/.codex/AGENTS.md")" ] || fail 'unmatched marker failure mutated AGENTS.md'
[ ! -e "$UNMATCHED/.codex/skills/whole-task-control" ] || fail 'unmatched marker failure half-installed skill'

# AGENTS.md must be a regular file when it already exists; a directory must fail before copying the skill.
WRONG_TYPE="$TEST_ROOT/wrong-type"
mkdir -p "$WRONG_TYPE/.codex/AGENTS.md"
expect_failure env HOME="$WRONG_TYPE" sh "$PACKAGE_DIR/install.sh"
[ -d "$WRONG_TYPE/.codex/AGENTS.md" ] || fail 'wrong-type AGENTS.md was replaced'
[ ! -e "$WRONG_TYPE/.codex/skills/whole-task-control" ] || fail 'wrong-type failure half-installed skill'

# Custom same-name skill is protected; explicit replacement backs it up.
CUSTOM="$TEST_ROOT/custom"
mkdir -p "$CUSTOM/.codex/skills/whole-task-control"
printf '%s\n' 'CUSTOM-SKILL' > "$CUSTOM/.codex/skills/whole-task-control/SKILL.md"
printf '%s\n' 'CUSTOM-AGENTS' > "$CUSTOM/.codex/AGENTS.md"
CUSTOM_SKILL_HASH=$(hash_file "$CUSTOM/.codex/skills/whole-task-control/SKILL.md")
CUSTOM_AGENTS_HASH=$(hash_file "$CUSTOM/.codex/AGENTS.md")
expect_failure env HOME="$CUSTOM" sh "$PACKAGE_DIR/install.sh"
[ "$CUSTOM_SKILL_HASH" = "$(hash_file "$CUSTOM/.codex/skills/whole-task-control/SKILL.md")" ] || fail 'custom skill overwritten without --replace'
[ "$CUSTOM_AGENTS_HASH" = "$(hash_file "$CUSTOM/.codex/AGENTS.md")" ] || fail 'custom refusal mutated AGENTS.md'
HOME="$CUSTOM" sh "$PACKAGE_DIR/install.sh" --replace >/dev/null
BACKUP_DIR=$(sed -n '1p' "$CUSTOM/.codex/whole-task-control-last-backup")
assert_contains "$BACKUP_DIR/whole-task-control-original/SKILL.md" 'CUSTOM-SKILL'

# V1 upgrade replaces the old always-on rule while preserving unrelated global rules.
V1="$TEST_ROOT/v1-upgrade"
mkdir -p "$V1/.codex/skills/whole-task-control"
printf '%s\n' 'OLD-V1-SKILL' > "$V1/.codex/skills/whole-task-control/SKILL.md"
printf '%s\n' \
  'BEFORE-V1' \
  "$BEGIN_MARKER" \
  '旧规则：每个 turn 都完整读取。' \
  "$END_MARKER" \
  'AFTER-V1' > "$V1/.codex/AGENTS.md"
HOME="$V1" sh "$PACKAGE_DIR/install.sh" --replace >/dev/null
assert_contains "$V1/.codex/AGENTS.md" 'BEFORE-V1'
assert_contains "$V1/.codex/AGENTS.md" 'AFTER-V1'
assert_not_contains "$V1/.codex/AGENTS.md" '每个 turn 都完整读取'
assert_contains "$V1/.codex/AGENTS.md" '如果仅看当前消息即可安全、完整处理'
[ "$(grep -Fxc "$BEGIN_MARKER" "$V1/.codex/AGENTS.md")" -eq 1 ] || fail 'V1 upgrade duplicated begin marker'

# Dry run has zero filesystem mutation.
DRY="$TEST_ROOT/dry"
mkdir -p "$DRY/.codex"
printf '%s\n' 'DRY-KEEP' > "$DRY/.codex/AGENTS.md"
DRY_HASH=$(hash_file "$DRY/.codex/AGENTS.md")
HOME="$DRY" sh "$PACKAGE_DIR/install.sh" --dry-run >/dev/null
[ "$DRY_HASH" = "$(hash_file "$DRY/.codex/AGENTS.md")" ] || fail 'dry run mutated AGENTS.md'
[ ! -e "$DRY/.codex/skills/whole-task-control" ] || fail 'dry run installed skill'
[ ! -e "$DRY/.codex/backups" ] || fail 'dry run created backup'

# CODEX_HOME paths containing spaces work.
SPACES="$TEST_ROOT/home with spaces/custom codex"
CODEX_HOME="$SPACES" sh "$PACKAGE_DIR/install.sh" >/dev/null
assert_file "$SPACES/skills/whole-task-control/SKILL.md"
assert_contains "$SPACES/AGENTS.md" "$SPACES/skills/whole-task-control/SKILL.md"

# POSIX installers recognize and replace rule markers written with Windows CRLF endings.
CRLF="$TEST_ROOT/crlf"
mkdir -p "$CRLF/.codex"
printf 'BEFORE\r\n%s\r\nOLD-CRLF-BLOCK\r\n%s\r\nAFTER\r\n' \
  "$BEGIN_MARKER" "$END_MARKER" > "$CRLF/.codex/AGENTS.md"
HOME="$CRLF" sh "$PACKAGE_DIR/install.sh" >/dev/null
[ "$(grep -Fc "$BEGIN_MARKER" "$CRLF/.codex/AGENTS.md")" -eq 1 ] || fail 'CRLF upgrade duplicated begin marker'
[ "$(grep -Fc "$END_MARKER" "$CRLF/.codex/AGENTS.md")" -eq 1 ] || fail 'CRLF upgrade duplicated end marker'
assert_contains "$CRLF/.codex/AGENTS.md" 'BEFORE'
assert_contains "$CRLF/.codex/AGENTS.md" 'AFTER'
assert_not_contains "$CRLF/.codex/AGENTS.md" 'OLD-CRLF-BLOCK'

# Normal uninstall removes only managed assets and keeps later unrelated rules.
UNINSTALL="$TEST_ROOT/uninstall"
mkdir -p "$UNINSTALL/.codex"
printf '%s\n' 'ORIGINAL-RULE' > "$UNINSTALL/.codex/AGENTS.md"
HOME="$UNINSTALL" sh "$PACKAGE_DIR/install.sh" >/dev/null
printf '%s\n' 'LATER-RULE' >> "$UNINSTALL/.codex/AGENTS.md"
HOME="$UNINSTALL" sh "$PACKAGE_DIR/uninstall.sh" >/dev/null
[ ! -e "$UNINSTALL/.codex/skills/whole-task-control" ] || fail 'uninstall left managed skill'
assert_contains "$UNINSTALL/.codex/AGENTS.md" 'ORIGINAL-RULE'
assert_contains "$UNINSTALL/.codex/AGENTS.md" 'LATER-RULE'
assert_not_contains "$UNINSTALL/.codex/AGENTS.md" "$BEGIN_MARKER"

# Explicit restore returns the exact pre-install AGENTS and custom skill.
RESTORE="$TEST_ROOT/restore"
mkdir -p "$RESTORE/.codex/skills/whole-task-control"
printf '%s\n' 'RESTORE-ORIGINAL-AGENTS' > "$RESTORE/.codex/AGENTS.md"
printf '%s\n' 'RESTORE-ORIGINAL-SKILL' > "$RESTORE/.codex/skills/whole-task-control/SKILL.md"
HOME="$RESTORE" sh "$PACKAGE_DIR/install.sh" --replace >/dev/null
printf '%s\n' 'POST-INSTALL-CHANGE' >> "$RESTORE/.codex/AGENTS.md"
HOME="$RESTORE" sh "$PACKAGE_DIR/restore.sh" >/dev/null
assert_contains "$RESTORE/.codex/AGENTS.md" 'RESTORE-ORIGINAL-AGENTS'
assert_not_contains "$RESTORE/.codex/AGENTS.md" 'POST-INSTALL-CHANGE'
assert_contains "$RESTORE/.codex/skills/whole-task-control/SKILL.md" 'RESTORE-ORIGINAL-SKILL'

# Activation remains feature-based and standalone.
assert_contains "$PACKAGE_DIR/global-rule.txt" '如果仅看当前消息即可安全、完整处理'
assert_contains "$PACKAGE_DIR/global-rule.txt" '需要结合此前决定、约束或真实进度'
assert_contains "$PACKAGE_DIR/whole-task-control/SKILL.md" 'self-contained, low-risk, and single-step'
assert_contains "$PACKAGE_DIR/whole-task-control/SKILL.md" 'Children never load this skill'

# PowerShell delivery exists even when pwsh is unavailable on the build Mac.
assert_contains "$PACKAGE_DIR/install.ps1" '[switch]$DryRun'
assert_contains "$PACKAGE_DIR/install.ps1" '[switch]$Replace'
assert_contains "$PACKAGE_DIR/uninstall.ps1" '[switch]$DryRun'
assert_contains "$PACKAGE_DIR/restore.ps1" 'whole-task-control-last-backup'

echo "HASH_TOOL=$HASH_TOOL"
POWERSHELL_OUTPUT=''
if command -v pwsh >/dev/null 2>&1; then
  if ! POWERSHELL_OUTPUT=$(pwsh -NoProfile -File "$PACKAGE_DIR/tests/test_install.ps1"); then
    fail 'native PowerShell tests failed under pwsh'
  fi
elif command -v powershell.exe >/dev/null 2>&1; then
  POWERSHELL_TEST_PATH="$PACKAGE_DIR/tests/test_install.ps1"
  if command -v wslpath >/dev/null 2>&1; then
    POWERSHELL_TEST_PATH=$(wslpath -w "$POWERSHELL_TEST_PATH")
  fi
  if ! POWERSHELL_OUTPUT=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$POWERSHELL_TEST_PATH"); then
    fail 'native PowerShell tests failed under powershell.exe'
  fi
else
  echo 'POWERSHELL_RUNTIME_NOT_FOUND: native PowerShell tests skipped'
fi
if [ -n "$POWERSHELL_OUTPUT" ]; then
  printf '%s\n' "$POWERSHELL_OUTPUT"
  case "$POWERSHELL_OUTPUT" in
    *ALL_V211_POWERSHELL_TESTS_PASSED*) ;;
    *) fail 'native PowerShell tests did not emit their final success marker' ;;
  esac
fi
echo 'ALL_V211_SHELL_INSTALL_TESTS_PASSED'
