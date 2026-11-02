#!/usr/bin/env python3
"""Exercise the real image with disposable data, without provider requests."""
import json
import os
import pty
import select
import subprocess
import sys
import time
import uuid


PROBE = r"""
import { writeFileSync } from 'node:fs';
import { createConnection } from 'node:net';
import { join } from 'node:path';
import { getAgentDir } from '@earendil-works/pi-coding-agent';
export default function(pi) {
  pi.on('session_start', async (_event, ctx) => {
    const id = ctx.sessionManager.getSessionId();
    const path = join(getAgentDir(), 'herdcats', id + '.sock');
    const state = await new Promise((resolve, reject) => {
      const socket = createConnection(path);
      let data = '';
      socket.setTimeout(5000, () => socket.destroy(new Error('probe timeout')));
      socket.on('error', reject);
      socket.on('connect', () => socket.write('{"method":"state","params":{}}\n'));
      socket.on('data', chunk => {
        data += chunk.toString();
        if (data.includes('\n')) { socket.end(); resolve(JSON.parse(data)); }
      });
    });
    if (state.error || state.result.session_id !== id || state.result.version !== '1.4.0') {
      throw new Error('Pi extension identity/version mismatch');
    }
    writeFileSync('/tmp/review-probe-result.json', JSON.stringify({
      protocol: state.result.protocol,
      version: state.result.version,
      session_matches: state.result.session_file === ctx.sessionManager.getSessionFile(),
      prompts: state.result.capabilities.prompts
    }));
    ctx.shutdown();
  });
}
"""


def run(*args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True,
                          timeout=120, **kwargs).stdout.strip()


def main():
    image = sys.argv[1] if len(sys.argv) == 2 else "herdcats-review:test"
    name = "herdcats-review-smoke-" + uuid.uuid4().hex[:10]
    volume = name + "-data"

    def execute(*args, **kwargs):
        return run("docker", "exec", name, *args, **kwargs)

    def verify():
        last_error = None
        for _ in range(120):
            try:
                # Startup itself verifies Pi. Wait for Herdr before launching a
                # second version probe, especially under memory-heavy emulation.
                execute("test", "-S", "/data/home/review/.config/herdr/herdr.sock")
            except subprocess.CalledProcessError as error:
                last_error = error
                if run("docker", "inspect", "--format", "{{.State.Running}}", name) != "true":
                    break
                time.sleep(0.5)
            else:
                return execute("runuser", "-u", "review", "--", "review-verify", "/data/home/review")
        raise RuntimeError("Image failed to initialize: " + run("docker", "logs", name)) from last_error

    run("docker", "volume", "create", volume)
    try:
        run("docker", "run", "--detach", "--name", name,
            "--mount", "type=volume,source=" + volume + ",target=/data",
            "--env", "REVIEW_SSH_PASSWORD=disposable-smoke-only", image)
        print(verify(), flush=True)
        # These are synthetic user-owned files, deliberately distinct from image defaults.
        execute("runuser", "-u", "review", "--", "sh", "-c", """
          printf '%s' '{"custom":"preserve"}' > "$HOME/.pi/agent/settings.json"
          printf '%s' 'synthetic-auth' > "$HOME/.pi/agent/auth.json"
          mkdir -p "$HOME/.pi/agent/sessions/synthetic"
          printf '%s' 'synthetic-history' > "$HOME/.pi/agent/sessions/synthetic/session.jsonl"
          printf '%s' 'custom-extension' > "$HOME/.pi/agent/extensions/custom.txt"
          printf '%s' 'old-managed-runtime' > "$HOME/.pi/agent/extensions/herdcats/runtime.mjs"
          printf '%s' 'old-managed-bridge' > "$HOME/.local/bin/herdcats-bridge"
        """)
        run("docker", "restart", name)
        print(verify(), flush=True)
        for path, expected in {
            "settings.json": '{"custom":"preserve"}',
            "auth.json": "synthetic-auth",
            "sessions/synthetic/session.jsonl": "synthetic-history",
            "extensions/custom.txt": "custom-extension",
        }.items():
            assert execute("cat", "/data/home/review/.pi/agent/" + path) == expected, path
        print("Restart preserved user files and refreshed managed runtime", flush=True)

        run("docker", "exec", "-i", "--user", "review", name,
            "sh", "-c", "cat > /tmp/review-probe.ts", input=PROBE)
        master, slave = pty.openpty()
        process = subprocess.Popen([
            "docker", "exec", "-it", "--user", "review", "--workdir", "/tmp",
            "--env", "TERM=xterm-256color",
            "--env", "PI_CODING_AGENT_DIR=/tmp/review-probe-agent", name,
            "pi", "--no-extensions", "--no-skills", "--no-prompt-templates",
            "-e", "/data/home/review/.pi/agent/extensions/herdcats/index.ts",
            "-e", "/tmp/review-probe.ts", "--session", "/tmp/review-probe-session.jsonl",
        ], stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        output = bytearray()
        try:
            deadline = time.monotonic() + 60
            while process.poll() is None and time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError:
                        break
            if process.wait(timeout=5) != 0:
                raise RuntimeError(output.decode(errors="replace")[-6000:])
        except Exception:
            print(output.decode(errors="replace")[-6000:], file=sys.stderr)
            raise
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            os.close(master)
        state = json.loads(execute("cat", "/tmp/review-probe-result.json"))
        assert state == {"protocol": 1, "version": "1.4.0", "session_matches": True, "prompts": True}, state
        print("Real Pi TUI loaded the shipped extension and answered socket state with matching identity", flush=True)
    finally:
        subprocess.run(["docker", "rm", "--force", name], capture_output=True)
        subprocess.run(["docker", "volume", "rm", volume], capture_output=True)


if __name__ == "__main__":
    main()
