#!/bin/sh
set -eu

PACKAGE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$PACKAGE_DIR/lib.sh"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "未知参数：$arg" >&2; exit 2 ;;
  esac
done

CODEX_HOME=${CODEX_HOME:-"$HOME/.codex"}
SKILL_DIR="$CODEX_HOME/skills/whole-task-control"
AGENTS_FILE="$CODEX_HOME/AGENTS.md"
BACKUP_ROOT="$CODEX_HOME/backups/whole-task-control"
LAST_BACKUP_FILE="$CODEX_HOME/whole-task-control-last-backup"

if [ -e "$AGENTS_FILE" ] && [ ! -f "$AGENTS_FILE" ]; then
  echo "卸载停止：AGENTS.md 已存在但不是普通文件。未修改任何文件。" >&2
  exit 1
fi

if ! wtc_validate_markers "$AGENTS_FILE"; then
  echo "卸载停止：AGENTS.md 中的标记缺失、重复或顺序错误。未修改任何文件。" >&2
  exit 1
fi

MANAGED_SKILL=0
if [ -d "$SKILL_DIR" ] && [ -f "$SKILL_DIR/$WTC_MANAGED_FILE" ]; then
  MANAGED_SKILL=1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "预览：将移除 AGENTS.md 中的 Whole Task Control 规则块。"
  [ "$MANAGED_SKILL" -eq 1 ] && echo "将移除受管理技能：$SKILL_DIR"
  [ -d "$SKILL_DIR" ] && [ "$MANAGED_SKILL" -eq 0 ] && echo "同名技能不受本安装器管理，将保留。"
  echo "预览完成：没有修改任何文件。"
  exit 0
fi

mkdir -p "$CODEX_HOME" "$BACKUP_ROOT"
STAGE_DIR=$(mktemp -d "$CODEX_HOME/.whole-task-control-uninstall.XXXXXX")
BACKUP_DIR=$(wtc_new_backup_dir "$BACKUP_ROOT" uninstall)
COMMIT_STARTED=0
COMMITTED=0

rollback_uninstall() {
  if [ "$COMMIT_STARTED" -eq 1 ] && [ "$COMMITTED" -eq 0 ] && [ -d "$BACKUP_DIR" ]; then
    wtc_restore_snapshot "$BACKUP_DIR" "$AGENTS_FILE" "$SKILL_DIR" || true
    wtc_restore_pointer "$BACKUP_DIR" "$LAST_BACKUP_FILE" || true
  fi
}

finish_uninstall() {
  status=$1
  trap - 0 1 2 15
  rollback_uninstall
  rm -rf "$STAGE_DIR"
  exit "$status"
}
trap 'finish_uninstall $?' 0
trap 'exit 129' 1
trap 'exit 130' 2
trap 'exit 143' 15

wtc_strip_rule "$AGENTS_FILE" "$STAGE_DIR/AGENTS.md"
wtc_validate_markers "$STAGE_DIR/AGENTS.md"
wtc_snapshot "$BACKUP_DIR" uninstall "$AGENTS_FILE" "$SKILL_DIR"
wtc_snapshot_pointer "$BACKUP_DIR" "$LAST_BACKUP_FILE"
COMMIT_STARTED=1

if [ "$MANAGED_SKILL" -eq 1 ]; then
  rm -rf "$SKILL_DIR"
fi
if ! mv "$STAGE_DIR/AGENTS.md" "$AGENTS_FILE"; then
  echo "卸载失败：无法替换 AGENTS.md，正在恢复。" >&2
  exit 1
fi

wtc_write_last_backup "$CODEX_HOME" "$BACKUP_DIR"
COMMITTED=1
trap - 0 1 2 15
rm -rf "$STAGE_DIR"

wtc_validate_markers "$AGENTS_FILE"
echo "卸载完成。卸载前状态备份：$BACKUP_DIR"
echo "如需恢复，运行：sh restore.sh"
