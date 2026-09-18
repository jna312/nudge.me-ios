#!/bin/bash
set -euo pipefail
NUDGE_TEST_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
NUDGE_REPO="$(cd -- "$NUDGE_TEST_DIR/../.." && pwd)"
NUDGE_OUTPUT="$(mktemp -d /tmp/nudge-capture-tests.XXXXXX)"
trap 'rm -rf "$NUDGE_OUTPUT"' EXIT
python3 - "$NUDGE_REPO/nudge.me/SmartFeatures.swift" "$NUDGE_OUTPUT/SmartFeatures.swift" <<'PY'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_text()
a = source.index('// MARK: - Calendar Conflict Detection')
b = source.index('// MARK: - Reminder Search')
source = source[:a] + 'struct CalendarConflictDetector { static func checkConflicts(at date: Date) async -> [String] { [] } }\n\n' + source[b:]
Path(sys.argv[2]).write_text(source)
PY
xcrun swiftc -parse-as-library \
 "$NUDGE_REPO/nudge.me/ReminderParser.swift" \
 "$NUDGE_REPO/nudge.me/ReminderDraft.swift" \
 "$NUDGE_REPO/nudge.me/ReminderItem.swift" \
 "$NUDGE_REPO/nudge.me/StringExtensions.swift" \
 "$NUDGE_REPO/nudge.me/Helpers.swift" \
 "$NUDGE_REPO/nudge.me/CaptureFlow.swift" \
 "$NUDGE_REPO/nudge.me/ErrorLogger.swift" \
 "$NUDGE_OUTPUT/SmartFeatures.swift" \
 "$NUDGE_TEST_DIR/TestDoubles.swift" \
 "$NUDGE_TEST_DIR/CaptureRegression.swift" \
 -o "$NUDGE_OUTPUT/capture-tests"
"$NUDGE_OUTPUT/capture-tests"
