"""Run a command with a deadline; stop its process group on timeout or interruption."""
import os
import signal
import subprocess
import sys


def stop_group(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass
        # The parent may exit before a descendant that ignored TERM.
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def main():
    try:
        seconds = int(sys.argv[1])
        if seconds <= 0 or len(sys.argv) < 3:
            raise ValueError
    except (ValueError, IndexError):
        print("usage: run_with_timeout.py POSITIVE_SECONDS COMMAND [ARGS...]", file=sys.stderr)
        return 2

    process = subprocess.Popen(sys.argv[2:], start_new_session=True)

    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    timed_out = False
    try:
        result = process.wait(timeout=seconds)
        return result if result >= 0 else 128 - result
    except subprocess.TimeoutExpired:
        timed_out = True
        print(f"FATAL: command timed out after {seconds}s: {sys.argv[2:]}", file=sys.stderr, flush=True)
        return 124
    finally:
        if timed_out or process.poll() is None:
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            signal.signal(signal.SIGINT, signal.SIG_IGN)
            stop_group(process)


if __name__ == "__main__":
    sys.exit(main())
