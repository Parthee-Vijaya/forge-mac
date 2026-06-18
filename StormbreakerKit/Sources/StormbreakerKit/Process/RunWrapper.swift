import Foundation

/// The dev-server wrapper script, materialized to `<project>/.forge/storm-run.sh`
/// at launch. Inlined (rather than bundled as a SwiftPM resource) so the package
/// embeds cleanly in an Xcode app with no `Bundle.module` lookup.
///
/// It runs the real command, forwards SIGTERM/SIGINT to the child subtree, and
/// reaps the subtree if the Stormbreaker parent process dies (Foundation `Process`
/// exposes no setpgid hook).
enum RunWrapper {
    static let script = """
    #!/bin/sh
    set -u

    "$@" &
    CHILD=$!

    cleanup() {
      kill "$CHILD" 2>/dev/null
      pkill -P "$CHILD" 2>/dev/null
    }
    trap 'cleanup' TERM INT

    WATCHDOG=""
    if [ -n "${STORM_PARENT_PID:-}" ]; then
      (
        while kill -0 "$STORM_PARENT_PID" 2>/dev/null; do
          sleep 1
        done
        cleanup
        sleep 2
        kill -9 "$CHILD" 2>/dev/null
      ) &
      WATCHDOG=$!
    fi

    wait "$CHILD"
    STATUS=$?
    [ -n "$WATCHDOG" ] && kill "$WATCHDOG" 2>/dev/null
    exit "$STATUS"
    """
}
