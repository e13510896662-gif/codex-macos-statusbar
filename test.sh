#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
developer_dir="$(xcode-select -p)"
testing_plugin="$developer_dir/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$testing_plugin" ]]; then
  testing_frameworks="$developer_dir/Library/Developer/Frameworks"
  swift test --build-system native --disable-xctest \
    -Xswiftc -F -Xswiftc "$testing_frameworks" \
    -Xswiftc -load-plugin-library -Xswiftc "$testing_plugin" \
    -Xlinker -rpath -Xlinker "$testing_frameworks"
else
  swift test --disable-xctest
fi
