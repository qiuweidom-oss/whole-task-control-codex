#!/bin/sh

WTC_BEGIN_MARKER='<!-- WHOLE-TASK-CONTROL BEGIN (Codex root only) -->'
WTC_END_MARKER='<!-- WHOLE-TASK-CONTROL END -->'
WTC_MANAGED_FILE='.managed-by-whole-task-control'

wtc_validate_markers() {
  file=$1
  [ -f "$file" ] || return 0
  awk -v begin="$WTC_BEGIN_MARKER" -v end="$WTC_END_MARKER" '
    {
      marker_line = $0
      sub(/\r$/, "", marker_line)
    }
    marker_line == begin {
      begin_count++
      if (state != 0 || begin_count > 1) bad = 1
      state = 1
      next
    }
    marker_line == end {
      end_count++
      if (state != 1 || end_count > 1) bad = 1
      state = 2
      next
    }
    END {
      if (bad || begin_count != end_count || begin_count > 1 || (begin_count == 1 && state != 2)) exit 1
    }
  ' "$file"
}

wtc_strip_rule() {
  input=$1
  output=$2
  if [ ! -f "$input" ]; then
    : > "$output"
    return
  fi
  awk -v begin="$WTC_BEGIN_MARKER" -v end="$WTC_END_MARKER" '
    {
      marker_line = $0
      sub(/\r$/, "", marker_line)
    }
    marker_line == begin { skipping = 1; next }
    marker_line == end { skipping = 0; next }
    !skipping { print }
  ' "$input" > "$output"
}

wtc_render_rule() {
  template=$1
  output=$2
  skill_path=$3
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = '__WHOLE_TASK_CONTROL_SKILL_PATH_LINE__' ]; then
      printf '%s%s%s\n' '- 触发后完整读取：`' "$skill_path" '`。' >> "$output"
    else
      printf '%s\n' "$line" >> "$output"
    fi
  done < "$template"
}

wtc_snapshot() {
  backup_dir=$1
  operation=$2
  agents_file=$3
  skill_dir=$4
  mkdir -p "$backup_dir"
  printf '%s\n' "$operation" > "$backup_dir/operation"
  if [ -f "$agents_file" ]; then
    cp "$agents_file" "$backup_dir/AGENTS.md"
    printf '%s\n' '1' > "$backup_dir/agents-existed"
  else
    printf '%s\n' '0' > "$backup_dir/agents-existed"
  fi
  if [ -d "$skill_dir" ]; then
    cp -R "$skill_dir" "$backup_dir/whole-task-control-original"
    printf '%s\n' '1' > "$backup_dir/skill-existed"
  else
    printf '%s\n' '0' > "$backup_dir/skill-existed"
  fi
}

wtc_snapshot_pointer() {
  backup_dir=$1
  pointer_file=$2
  if [ -f "$pointer_file" ]; then
    cp "$pointer_file" "$backup_dir/last-backup-pointer"
    printf '%s\n' '1' > "$backup_dir/pointer-existed"
  else
    printf '%s\n' '0' > "$backup_dir/pointer-existed"
  fi
}

wtc_restore_snapshot() {
  backup_dir=$1
  agents_file=$2
  skill_dir=$3
  agents_existed=$(sed -n '1p' "$backup_dir/agents-existed")
  skill_existed=$(sed -n '1p' "$backup_dir/skill-existed")

  rm -rf "$skill_dir"
  if [ "$skill_existed" = '1' ]; then
    mkdir -p "$(dirname -- "$skill_dir")"
    cp -R "$backup_dir/whole-task-control-original" "$skill_dir"
  fi

  if [ "$agents_existed" = '1' ]; then
    cp "$backup_dir/AGENTS.md" "$agents_file"
  else
    rm -f "$agents_file"
  fi
}

wtc_restore_pointer() {
  backup_dir=$1
  pointer_file=$2
  [ -f "$backup_dir/pointer-existed" ] || return 0
  pointer_existed=$(sed -n '1p' "$backup_dir/pointer-existed")
  if [ "$pointer_existed" = '1' ]; then
    cp "$backup_dir/last-backup-pointer" "$pointer_file"
  else
    rm -f "$pointer_file"
  fi
}

wtc_new_backup_dir() {
  backup_root=$1
  operation=$2
  stamp=$(date '+%Y%m%d-%H%M%S')
  candidate="$backup_root/$stamp-$$-$operation"
  suffix=0
  while [ -e "$candidate" ]; do
    suffix=$((suffix + 1))
    candidate="$backup_root/$stamp-$$-$operation-$suffix"
  done
  printf '%s\n' "$candidate"
}

wtc_write_last_backup() {
  codex_home=$1
  backup_dir=$2
  pointer_tmp="$codex_home/.whole-task-control-last-backup.$$"
  printf '%s\n' "$backup_dir" > "$pointer_tmp"
  mv "$pointer_tmp" "$codex_home/whole-task-control-last-backup"
}
