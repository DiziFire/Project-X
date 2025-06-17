#!/bin/sh

# WeaponX Debug Script
echo "WeaponX Debug Tool"
echo "==================="

# Check if we're in a rootless environment
if [ -d /var/jb ]; then
  ROOT_PREFIX="/var/jb"
  echo "✅ Rootless jailbreak detected."
else
  ROOT_PREFIX=""
  echo "✅ Traditional jailbreak detected."
fi

DAEMON_PATH="${ROOT_PREFIX}/Library/WeaponX/WeaponXDaemon"
LAUNCHDAEMON_PATH="${ROOT_PREFIX}/Library/LaunchDaemons/com.hydra.weaponx.guardian.plist"
GUARDIAN_DIR="${ROOT_PREFIX}/Library/WeaponX/Guardian"
LOGS_DIR="${GUARDIAN_DIR}"

show_help() {
  echo "Usage: weaponx-debug.sh [command]"
  echo "Commands:"
  echo "  status     - Show daemon status"
  echo "  logs       - Show daemon logs"
  echo "  restart    - Restart the daemon"
  echo "  direct     - Run daemon directly (for debugging)"
  echo "  install    - Ensure daemon is properly installed"
  echo "  trace      - Enable full activity tracing"
}

daemon_status() {
  echo "🔍 Daemon Status:"
  if [ -f "$DAEMON_PATH" ]; then
    echo "✅ Daemon executable exists: $DAEMON_PATH"
    ls -la "$DAEMON_PATH"
  else
    echo "❌ Daemon executable not found at: $DAEMON_PATH"
  fi
  
  if [ -f "$LAUNCHDAEMON_PATH" ]; then
    echo "✅ LaunchDaemon plist exists: $LAUNCHDAEMON_PATH"
    ls -la "$LAUNCHDAEMON_PATH"
  else
    echo "❌ LaunchDaemon plist not found at: $LAUNCHDAEMON_PATH"
  fi
  
  if [ -d "$GUARDIAN_DIR" ]; then
    echo "✅ Guardian directory exists: $GUARDIAN_DIR"
    ls -la "$GUARDIAN_DIR"
  else
    echo "❌ Guardian directory not found at: $GUARDIAN_DIR"
  fi
  
  echo "🔍 Process Check:"
  if ps aux | grep -v grep | grep WeaponXDaemon > /dev/null; then
    echo "✅ WeaponXDaemon is running:"
    ps aux | grep -v grep | grep WeaponXDaemon
  else
    echo "❌ WeaponXDaemon process not found"
  fi
  
  echo "🔍 LaunchDaemon Check:"
  if launchctl list | grep "com.hydra.weaponx.guardian" > /dev/null; then
    echo "✅ LaunchDaemon is loaded:"
    launchctl list | grep "com.hydra.weaponx.guardian"
  else
    echo "❌ LaunchDaemon not loaded"
  fi
}

show_logs() {
  echo "📜 WeaponX Logs:"
  
  if [ -f "${LOGS_DIR}/daemon.log" ]; then
    echo "=== Daemon Log ==="
    tail -n 50 "${LOGS_DIR}/daemon.log"
  else
    echo "❌ Daemon log not found at: ${LOGS_DIR}/daemon.log"
  fi
  
  if [ -f "${LOGS_DIR}/guardian-stdout.log" ]; then
    echo "=== Stdout Log ==="
    tail -n 20 "${LOGS_DIR}/guardian-stdout.log"
  fi
  
  if [ -f "${LOGS_DIR}/guardian-stderr.log" ]; then
    echo "=== Stderr Log ==="
    tail -n 20 "${LOGS_DIR}/guardian-stderr.log"
  fi
  
  echo "=== System Log ==="
  log show --predicate 'subsystem contains "com.hydra.weaponx"' --style compact --last 1h | tail -n 50
}

restart_daemon() {
  echo "🔄 Restarting daemon..."
  
  echo "Unloading daemon..."
  launchctl bootout system/com.hydra.weaponx.guardian 2>/dev/null || true
  launchctl unload "$LAUNCHDAEMON_PATH" 2>/dev/null || true
  sleep 1
  
  # Kill any lingering processes
  if ps aux | grep -v grep | grep WeaponXDaemon > /dev/null; then
    echo "Killing existing process..."
    killall WeaponXDaemon 2>/dev/null || true
    sleep 1
  fi
  
  echo "Loading daemon..."
  if launchctl bootstrap system "$LAUNCHDAEMON_PATH" 2>/dev/null; then
    echo "✅ Daemon bootstrapped successfully"
  else
    echo "⚠️ Bootstrap failed, trying traditional load..."
    launchctl load -w "$LAUNCHDAEMON_PATH" 2>/dev/null
  fi
  
  sleep 2
  daemon_status
}

run_direct() {
  echo "🚀 Running daemon directly..."
  
  # Kill existing daemon if it's running
  if ps aux | grep -v grep | grep WeaponXDaemon > /dev/null; then
    echo "Killing existing daemon process..."
    killall WeaponXDaemon 2>/dev/null || true
    sleep 1
  fi
  
  echo "Launching daemon with debug flag..."
  "$DAEMON_PATH" --debug
}

ensure_install() {
  echo "🔧 Ensuring daemon is properly installed..."
  
  # Check directories
  mkdir -p "$GUARDIAN_DIR"
  chmod 755 "$GUARDIAN_DIR"
  chown root:wheel "$GUARDIAN_DIR"
  
  # Create log files
  touch "${LOGS_DIR}/daemon.log"
  touch "${LOGS_DIR}/guardian-stdout.log"
  touch "${LOGS_DIR}/guardian-stderr.log"
  chmod 664 "${LOGS_DIR}"/*.log
  chown root:wheel "${LOGS_DIR}"/*.log
  
  # Check executable permissions
  if [ -f "$DAEMON_PATH" ]; then
    chmod 755 "$DAEMON_PATH"
    chown root:wheel "$DAEMON_PATH"
  fi
  
  # Check LaunchDaemon plist
  if [ -f "$LAUNCHDAEMON_PATH" ]; then
    chmod 644 "$LAUNCHDAEMON_PATH"
    chown root:wheel "$LAUNCHDAEMON_PATH"
  fi
  
  echo "✅ Installation verified and fixed"
  restart_daemon
}

enable_tracing() {
  echo "📊 Enabling full activity tracing..."
  
  # Enable debug logging for subsystem
  log config --mode "level:debug" --subsystem com.hydra.weaponx.guardian
  
  # Show logs with tracing
  log stream --level debug --predicate 'subsystem contains "com.hydra.weaponx"' --style compact
}

# Main command processing
case "$1" in
  status)
    daemon_status
    ;;
  logs)
    show_logs
    ;;
  restart)
    restart_daemon
    ;;
  direct)
    run_direct
    ;;
  install)
    ensure_install
    ;;
  trace)
    enable_tracing
    ;;
  *)
    show_help
    ;;
esac

exit 0 