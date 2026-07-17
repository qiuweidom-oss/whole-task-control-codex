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

[ -f "$LAST_BACKUP_FILE" ] || { echo "恢复停止：没有找到最近备份指针。" >&2; exit 1; }
BACKUP_DIR=$(sed -n '1p' "$LAST_BACKUP_FILE")
case "$BACKUP_DIR" in
  "$BACKUP_ROOT"/*) ;;
  *) echo "恢复停止：备份路径不属于 Whole Task Control 备份目录。" >&2; exit 1 ;;
esac
for required in agents-existed skill-existed operation; do
  [ -f "$BACKUP_DIR/$required" ] || { echo "恢复停止：备份不完整，缺少 $required。" >&2; exit 1; }
done
if [ "$(sed -n '1p' "$BACKUP_DIR/agents-existed")" = '1' ]; then
  [ -f "$BACKUP_DIR/AGENTS.md" ] || { echo "恢复停止：备份缺少 AGENTS.md。" >&2; exit 1; }
fi
if [ "$(sed -n '1p' "$BACKUP_DIR/skill-existed")" = '1' ]; then
  [ -d "$BACKUP_DIR/whole-task-control-original" ] || { echo "恢复停止：备份缺少原技能。" >&2; exit 1; }
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "预览：将恢复备份 $BACKUP_DIR"
  echo "当前状态会先创建一份新的安全备份。"
  echo "预览完成：没有修改任何文件。"
  exit 0
fi

mkdir -p "$CODEX_HOME" "$BACKUP_ROOT"
STAGE_DIR=$(mktemp -d "$CODEX_HOME/.whole-task-control-restore.XXXXXX")
SAFETY_BACKUP=$(wtc_new_backup_dir "$BACKUP_ROOT" before-restore)
COMMIT_STARTED=0
COMMITTED=0

rollback_restore() {
  if [ "$COMMIT_STARTED" -eq 1 ] && [ "$COMMITTED" -eq 0 ] && [ -d "$SAFETY_BACKUP" ]; then
    wtc_restore_snapshot "$SAFETY_BACKUP" "$AGENTS_FILE" "$SKILL_DIR" || true
    wtc_restore_pointer "$SAFETY_BACKUP" "$LAST_BACKUP_FILE" || true
  fi
}

finish_restore() {
  status=$1
  trap - 0 1 2 15
  rollback_restore
  rm -rf "$STAGE_DIR"
  exit "$status"
}
trap 'finish_restore $?' 0
trap 'exit 129' 1
trap 'exit 130' 2
trap 'exit 143' 15

AGENTS_EXISTED=$(sed -n '1p' "$BACKUP_DIR/agents-existed")
SKILL_EXISTED=$(sed -n '1p' "$BACKUP_DIR/skill-existed")
if [ "$AGENTS_EXISTED" = '1' ]; then
  cp "$BACKUP_DIR/AGENTS.md" "$STAGE_DIR/AGENTS.md"
fi
if [ "$SKILL_EXISTED" = '1' ]; then
  cp -R "$BACKUP_DIR/whole-task-control-original" "$STAGE_DIR/skill"
fi

wtc_snapshot "$SAFETY_BACKUP" before-restore "$AGENTS_FILE" "$SKILL_DIR"
wtc_snapshot_pointer "$SAFETY_BACKUP" "$LAST_BACKUP_FILE"
COMMIT_STARTED=1

rm -rf "$SKILL_DIR"
if [ "$SKILL_EXISTED" = '1' ]; then
  mkdir -p "$(dirname -- "$SKILL_DIR")"
  mv "$STAGE_DIR/skill" "$SKILL_DIR"
fi
if [ "$AGENTS_EXISTED" = '1' ]; then
  mv "$STAGE_DIR/AGENTS.md" "$AGENTS_FILE"
else
  rm -f "$AGENTS_FILE"
fi

wtc_write_last_backup "$CODEX_HOME" "$SAFETY_BACKUP"
COMMITTED=1
trap - 0 1 2 15
rm -rf "$STAGE_DIR"

echo "恢复完成：$BACKUP_DIR"
echo "恢复前状态另存为：$SAFETY_BACKUP"
