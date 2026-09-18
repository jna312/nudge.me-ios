#!/bin/bash
set -euo pipefail
NUDGE_WIDGET_TEST_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
NUDGE_WIDGET_REPO="$(cd -- "$NUDGE_WIDGET_TEST_DIR/../.." && pwd)"
NUDGE_WIDGET_OUTPUT="$(mktemp -d /tmp/nudge-widget-tests.XXXXXX)"
trap 'rm -rf "$NUDGE_WIDGET_OUTPUT"' EXIT
xcrun swiftc -parse-as-library \
 "$NUDGE_WIDGET_REPO/nudge.me/WidgetSnapshot.swift" \
 "$NUDGE_WIDGET_REPO/nudge.me/ReminderItem.swift" \
 "$NUDGE_WIDGET_REPO/nudge.me/WidgetReminderActions.swift" \
 "$NUDGE_WIDGET_TEST_DIR/TestDoubles.swift" \
 "$NUDGE_WIDGET_TEST_DIR/WidgetRegression.swift" \
 -o "$NUDGE_WIDGET_OUTPUT/widget-tests"
"$NUDGE_WIDGET_OUTPUT/widget-tests"
