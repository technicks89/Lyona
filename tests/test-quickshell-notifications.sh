#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

model=$repo/config/quickshell/notifications/NotificationModel.qml

grep -Fq 'notification.closed.connect(() => root.remove(item.key));' "$model"
grep -Fq 'const overflow = candidates.slice(root.maxVisible);' "$model"
grep -Fq 'root.closeItem(overflowItem, false);' "$model"
grep -Fq 'root.notifications = [];' "$model"
grep -Fq 'root.remove(item.key);' "$model"
grep -Fq 'root.closeItem(root.notifications.find(n => n.key === key), false);' "$model"
grep -Fq 'root.closeItem(root.notifications.find(n => n.key === key), true);' "$model"

printf 'Quickshell notification lifecycle: PASS\n'
