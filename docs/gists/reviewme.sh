#!/bin/bash

TARGET_DIR="${1:-.}"
OUTPUT_FILE="collected_sources.txt"

> "$OUTPUT_FILE"

declare -A LANG_MAP=(
  ["py"]="python"
  ["kt"]="kotlin"
  ["js"]="javascript"
  ["ts"]="typescript"
  ["java"]="java"
  ["sh"]="bash"
  ["rb"]="ruby"
  ["go"]="go"
  ["c"]="c"
  ["cpp"]="cpp"
)

# Use git to list tracked files that match extensions
git -C "$TARGET_DIR" ls-files | grep -E '\.(py|kt|js|ts|java|sh|rb|go|c|cpp)$' | while read -r file; do
    ext="${file##*.}"
    lang="${LANG_MAP[$ext]}"
    {
      echo "## $TARGET_DIR/$file"
      echo
      echo "\`\`\`$lang"
      cat "$TARGET_DIR/$file"
      echo "\`\`\`"
      echo
      echo "------------------------"
      echo
    } >> "$OUTPUT_FILE"
done

echo "Collected sources written to $OUTPUT_FILE"
