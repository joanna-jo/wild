#!/usr/bin/env bash
set -euo pipefail

source_dir=wild/tests/sources/macho
apple_ld="$(xcrun --find ld)"
lld="$(command -v ld64.lld)"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

clang --version | sed -n '1p'
"$lld" --version
"$apple_ld" -version_details > ld-version.json
awk -F '"' '/"version":/ { print "Apple ld version: " $4; exit }' ld-version.json

for source_file in tlv-thread-ptrs/foo.c tlv-thread-ptrs/tlv-thread-ptrs.c common/runtime.c; do
  clang -Werror=attributes -mmacosx-version-min=11.0 -c \
    "$source_dir/$source_file" -o "${source_file##*/}.o"
done

clang --ld-path="$lld" -dynamiclib -o "$PWD/foo.lld.dylib" foo.c.o
binary=./tlv-thread-ptrs.ld
clang --ld-path="$apple_ld" -o "$binary" \
  tlv-thread-ptrs.c.o "$PWD/foo.lld.dylib" runtime.c.o

xcrun otool -l "$binary" > sections.txt
for section in __thread_ptrs __got; do
  if awk -v section="$section" '
    $1 == "sectname" && $2 == section { found = 1 }
    END { exit !found }
  ' sections.txt; then
    printf '%s exists: yes\n' "$section"
  else
    printf '%s exists: no\n' "$section"
  fi
done

xcrun dyld_info -fixups "$binary" > fixups.txt
printf '_value import binding (segment, section, address, type, target):\n'
awk '
  /(^|[\/[:space:]])_value([[:space:]]|$)/ { print; found = 1 }
  END { if (!found) print "  No _value import fixup found" }
' fixups.txt

exit_status=0
"$binary" > run.log 2>&1 || exit_status=$?
printf 'Executable exit status: %s (expected 42)\n' "$exit_status"
if [[ "$exit_status" -ne 42 ]]; then
  cat run.log
  exit 1
fi
