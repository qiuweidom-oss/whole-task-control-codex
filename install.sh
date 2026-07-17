#!/bin/sh
set -eu

PACKAGE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$PACKAGE_DIR/lib.sh"

DRY_RUN=0
REPLACE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --replace) REPLACE=1 ;;
    *) echo "未知参数：$arg" >&2; exit 2 ;;
  esac
done

SOURCE_DIR="$PACKAGE_DIR/whole-task-control"
RULE_TEMPLATE="$PACKAGE_DIR/global-rule.txt"
VERSION_FILE="$PACKAGE_DIR/VERSION"
CODEX_HOME=${CODEX_HOME:-"$HOME/.codex"}
SKILL_DIR="$CODEX_HOME/skills/whole-task-control"
AGENTS_FILE="$CODEX_HOME/AGENTS.md"
BACKUP_ROOT="$CODEX_HOME/backups/whole-task-control"
LAST_BACKUP_FILE="$CODEX_HOME/whole-task-control-last-backup"
FIRST_BACKUP_FILE="$CODEX_HOME/AGENTS.md.before-whole-task-control"

for required in "$SOURCE_DIR/SKILL.md" "$SOURCE_DIR/agents/openai.yaml" "$RULE_TEMPLATE" "$VERSION_FILE"; do
  [ -f "$required" ] || { echo "安装包不完整：缺少 $required" >&2; exit 1; }
done

if [ -e "$AGENTS_FILE" ] && [ ! -f "$AGENTS_FILE" ]; then
  echo "安装停止：AGENTS.md 已存在但不是普通文件。未修改任何文件。" >&2
  exit 1
fi

if ! wtc_validate_markers "$AGENTS_FILE"; then
  echo "安装停止：AGENTS.md 中的 Whole Task Control 标记缺失、重复或顺序错误。未修改任何文件。" >&2
  exit 1
fi

if [ -e "$SKILL_DIR" ] && [ ! -f "$SKILL_DIR/$WTC_MANAGED_FILE" ] && [ "$REPLACE" -ne 1 ]; then
  echo "安装停止：发现未受本安装器管理的同名技能。确认替换时请使用 --replace。未修改任何文件。" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "预览：将安装 Whole Task Control $(sed -n '1p' "$VERSION_FILE")"
  echo "技能目录：$SKILL_DIR"
  echo "全局规则：$AGENTS_FILE"
  [ -e "$SKILL_DIR" ] && echo "现有技能将备份后更新。" || echo "将创建新技能。"
  echo "预览完成：没有修改任何文件。"
  exit 0
fi

mkdir -p "$CODEX_HOME" "$CODEX_HOME/skills" "$BACKUP_ROOT"
STAGE_DIR=$(mktemp -d "$CODEX_HOME/.whole-task-control-stage.XXXXXX")
BACKUP_DIR=$(wtc_new_backup_dir "$BACKUP_ROOT" install)
COMMIT_STARTED=0
COMMITTED=0
FIRST_BACKUP_CREATED=0

rollback_install() {
  if [ "$COMMIT_STARTED" -eq 1 ] && [ "$COMMITTED" -eq 0 ] && [ -d "$BACKUP_DIR" ]; then
    wtc_restore_snapshot "$BACKUP_DIR" "$AGENTS_FILE" "$SKILL_DIR" || true
    wtc_restore_pointer "$BACKUP_DIR" "$LAST_BACKUP_FILE" || true
    if [ "$FIRST_BACKUP_CREATED" -eq 1 ]; then
      rm -f "$FIRST_BACKUP_FILE"
    fi
  fi
}

finish_install() {
  status=$1
  trap - 0 1 2 15
  rollback_install
  rm -rf "$STAGE_DIR"
  exit "$status"
}
trap 'finish_install $?' 0
trap 'exit 129' 1
trap 'exit 130' 2
trap 'exit 143' 15

mkdir -p "$STAGE_DIR/skill/agents"
cp "$SOURCE_DIR/SKILL.md" "$STAGE_DIR/skill/SKILL.md"
cp "$SOURCE_DIR/agents/openai.yaml" "$STAGE_DIR/skill/agents/openai.yaml"
cp "$VERSION_FILE" "$STAGE_DIR/skill/$WTC_MANAGED_FILE"

wtc_strip_rule "$AGENTS_FILE" "$STAGE_DIR/AGENTS.md"
wtc_render_rule "$RULE_TEMPLATE" "$STAGE_DIR/AGENTS.md" "$SKILL_DIR/SKILL.md"
wtc_validate_markers "$STAGE_DIR/AGENTS.md"
test -s "$STAGE_DIR/skill/SKILL.md"

if [ -f "$AGENTS_FILE" ] && [ ! -e "$FIRST_BACKUP_FILE" ]; then
  cp "$AGENTS_FILE" "$STAGE_DIR/AGENTS.md.before-whole-task-control"
fi

wtc_snapshot "$BACKUP_DIR" install "$AGENTS_FILE" "$SKILL_DIR"
wtc_snapshot_pointer "$BACKUP_DIR" "$LAST_BACKUP_FILE"
COMMIT_STARTED=1

rm -rf "$SKILL_DIR"
if ! mv "$STAGE_DIR/skill" "$SKILL_DIR"; then
  echo "安装失败：无法替换技能目录，正在恢复。" >&2
  exit 1
fi
if ! mv "$STAGE_DIR/AGENTS.md" "$AGENTS_FILE"; then
  echo "安装失败：无法替换 AGENTS.md，正在恢复。" >&2
  exit 1
fi
if [ -f "$STAGE_DIR/AGENTS.md.before-whole-task-control" ]; then
  if ! mv "$STAGE_DIR/AGENTS.md.before-whole-task-control" "$FIRST_BACKUP_FILE"; then
    echo "安装失败：无法建立首次安装前备份，正在恢复。" >&2
    exit 1
  fi
  FIRST_BACKUP_CREATED=1
fi

wtc_write_last_backup "$CODEX_HOME" "$BACKUP_DIR"
COMMITTED=1
trap - 0 1 2 15
rm -rf "$STAGE_DIR"

test -s "$SKILL_DIR/SKILL.md"
wtc_validate_markers "$AGENTS_FILE"
test "$(grep -Fxc "$WTC_BEGIN_MARKER" "$AGENTS_FILE")" -eq 1
test "$(grep -Fxc "$WTC_END_MARKER" "$AGENTS_FILE")" -eq 1

echo "安装完成：$SKILL_DIR"
echo "原状态备份：$BACKUP_DIR"
echo "Claude Code 未被读取或修改。新建 Codex 任务或重启 Codex 后生效。"
