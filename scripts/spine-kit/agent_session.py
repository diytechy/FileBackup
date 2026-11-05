#!/usr/bin/env python3
"""One headless agent session: argv/stdin construction, launch, and capture.

Extracted VERBATIM from agent_loop.py (WI-218 slice B — a file split, not a
rewrite; the behaviors and their WI history are unchanged). This is the layer
that turns a CmdTemplate + model + prompt into one running CLI session and
returns its output:

  - `split_cmd`/`build_argv` — template -> argv, deciding prompt delivery:
    a `{prompt}` placeholder rides the command line except through a Windows
    batch shim (refused because cmd.exe reparses it); NO `{prompt}` routes the
    prompt to the child's STDIN (WI-216), immune to caps and batch-shell parsing.
  - `run_session` — one fresh headless driver session (stdin closed or fed +
    closed — never an interactive wait, SN-016), with a reader thread so the
    child can't block on a full pipe, and a per-session timeout. It returns
    the whole captured stream; reading a CLI's result out of it (codex's
    `--output-last-message` file, WI-217) is that CLI's adapter's job
    (`session_adapters`), and every call reaches this layer through the
    session service (`session_service`).
  - `parse_json_result` — best-effort result-event parse of a
    --output-format json / stream-json transcript.
  - `summarize_session_line`/`echo_session_line`/`LiveStatus` (+ the TTY/VT
    probes) — the console rendering of a streaming session (WI-125/WI-136).

Stdlib only, Python 3.11+, Windows/POSIX. The session service
(session_service.py) is the one caller that launches through this module;
agent_loop re-exports the argv and rendering names so its public surface is
unchanged.

Contracts: IF-041, IF-064 — the interface seams this module declares (process.md §8; rows
of record in docs/requirements/interfaces.toml).

Contract IF-064: the session-launch surface. `build_argv(template, model,
    prompt)` returns `(argv, stdin_input)` and DECIDES prompt delivery: a
    template carrying a `{prompt}` placeholder gets it substituted into argv,
    except that a Windows batch shim is refused there because the shell
    re-parses it; with no placeholder the prompt is piped to the child's stdin
    instead, immune to command-line length caps. `run_session(argv, root,
    timeout, env, on_line, stdin_input)` returns `(exit_code, output,
    timed_out)` for ONE fresh headless session: stdin is closed, or fed and then
    closed — never left open for an interactive read, so the child cannot wedge
    the run — output is pumped by a reader thread, the timeout is per session,
    and the output is the whole captured stream. `parse_json_result` and the
    console renderers complete the surface, and the loop re-exports these
    names, so its own public surface is unchanged.

Contract IF-041: our reading of the configured agent CLI, stated here because
    the CLI's own header is not ours to write. The registry row's command
    template is substituted per token: `{model}` with the routed model and,
    where the template carries `{prompt}`, the prompt on the command line;
    with no `{prompt}` the prompt is piped to the child's stdin, which is the
    path every shipped template takes. A Windows `.cmd`/`.bat` shim with a
    prompt in argv is refused before launch, because cmd.exe may reparse it.
    The session is one headless child: its exit code, captured output and a
    timed-out flag come back, and the typed result is read from the CLI's
    JSON output (a stream-json result line, or the last-message file) — a
    child that emits none is a session with no typed outcome, reported as
    such rather than guessed.
"""

import ctypes
import functools
import json
import os
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import time
import weakref

# The shared job helpers, bound under the names this module has always used.
from kitlib.winjob import JobAccounting as _JobAccounting  # noqa: F401 (re-export)
from kitlib.winjob import job_active_processes as _job_active_processes
from kitlib.winjob import win32 as _win32


def split_cmd(template):
    """Split a command template into tokens.

    TWO ACCEPTED FORMS, and the second exists because the first cannot be made
    unambiguous. A `CmdTemplate` may be:

      a JSON ARRAY   `["claude", "-p", "--model", "{model}"]` — the tokens are
                     the tokens, full stop. No quoting rules, no shell grammar,
                     nothing for a Windows path or an embedded quote to trip
                     over. This is the form to declare a NEW route in
                     (plan §11.7).
      a SHELL STRING `claude -p --model {model}` — the historical form, split
                     quote-aware with backslash escaping DISABLED so Windows
                     paths survive (shlex's posix escape rules would eat
                     drive-letter separators). Every shipped row and every
                     existing adopter registry uses it, so it is read exactly
                     as before.

    The array form is recognised only when the value parses as a JSON list;
    anything else — including a string that merely starts with a bracket —
    falls through to the shell split, so no existing template can change
    meaning. A JSON array holding a NON-STRING token raises rather than being
    stringified into a command nobody wrote: a registry is config a human
    edits, and a silent coercion there is a launch that does not match its
    declaration."""
    text = (template or "").strip()
    if text.startswith("["):
        try:
            parsed = json.loads(text)
        except ValueError:
            parsed = None
        if isinstance(parsed, list):
            bad = [tok for tok in parsed if not isinstance(tok, str)]
            if bad:
                raise ValueError(
                    "CmdTemplate is a JSON array but holds a non-string token "
                    "{!r} — argv tokens are strings".format(bad[0])
                )
            return list(parsed)
    lex = shlex.shlex(template, posix=True)
    lex.whitespace_split = True
    lex.escape = ""
    lex.commenters = ""
    return list(lex)


def _windows_batch_executable(executable, env=None, platform=None):
    """Return the resolved Windows batch path for ``executable``, else ``""``.

    Windows may route ``.cmd``/``.bat`` files through ``cmd.exe`` even when
    ``subprocess`` is called with ``shell=False``. Keep that platform exception
    in one helper so preflight and the final launch boundary make the same
    decision. ``platform`` is injectable for cross-platform tests.
    """
    if (os.name if platform is None else platform) != "nt" or not executable:
        return ""
    if executable.lower().endswith((".cmd", ".bat")):
        return executable
    search_env = os.environ if env is None else env
    resolved = shutil.which(executable, path=search_env.get("PATH"))
    if resolved and resolved.lower().endswith((".cmd", ".bat")):
        return resolved
    return ""


def _batch_prompt_error(argv, stdin_input, env=None, platform=None):
    """Explain an unsafe prompt-in-argv Windows batch launch, or return ``""``."""
    if stdin_input is not None or not argv:
        return ""
    batch = _windows_batch_executable(argv[0], env=env, platform=platform)
    if not batch:
        return ""
    return (
        "unsafe prompt delivery refused: {!r} is a Windows batch shim, so "
        "cmd.exe can reparse a {{prompt}} argument even with shell=False; omit "
        "{{prompt}} and use the CLI's stdin prompt path, or configure a native "
        "executable"
    ).format(batch)


def _validate_prompt_transport(argv, stdin_input, env=None, platform=None):
    """Raise ``ValueError`` when prompt-in-argv would cross a batch shell."""
    error = _batch_prompt_error(argv, stdin_input, env=env, platform=platform)
    if error:
        raise ValueError(error)


def substitute(token, model, prompt):
    """One command-template token with `{model}` and `{prompt}` substituted:
    the one substitution a template's tokens take, for the launch argv
    (`build_argv`) and for the runner a launch resolves before it runs.

    Implements: SR-146, LLR-163
    """
    return token.replace("{model}", model).replace("{prompt}", prompt)


def build_argv(template, model, prompt):
    """Build the session argv from a CmdTemplate and decide how the prompt is
    delivered. Returns `(argv, stdin_input)`:

    - A template that carries a `{prompt}` placeholder gets it substituted into
      argv, and `stdin_input` is None — the prompt rides the command line (the
      historical behavior; `claude -p {prompt}`).
    - A template with NO `{prompt}` placeholder delivers the prompt on STDIN
      instead: `stdin_input = prompt`, and argv carries only the flags. This keeps
      the command line short — a Windows npm `.CMD` shim runs under cmd.exe, whose
      **8191-char** command-line cap silently kills a brief-sized prompt-in-argv
      (the failure gilbert hit on `codex`) — while the CLI reads the prompt from
      stdin (`codex exec` with no PROMPT arg reads stdin; run_session pipes it).

    Substitution is per-token. On Windows a batch shim is the OS exception:
    ``.cmd``/``.bat`` arguments can be reparsed by ``cmd.exe`` even with
    ``shell=False``, so prompt-in-argv is refused for those executables; use
    stdin prompt delivery or a native executable instead."""
    argv = []
    saw_prompt = False
    for tok in split_cmd(template):
        if "{prompt}" in tok:
            saw_prompt = True
        argv.append(substitute(tok, model, prompt))
    stdin_input = None if saw_prompt else prompt
    _validate_prompt_transport(argv, stdin_input)
    return argv, stdin_input


def parse_json_result(output):
    """Best-effort parse of a --output-format json / stream-json run: the last
    line (or the whole output) that loads as a JSON object, preferring a
    `type: result` event — so a stream-json transcript whose tail carries a
    non-result event (a killed stream, trailing diagnostics) never shadows the
    session result. Returns {} when nothing parses."""
    candidates = [ln for ln in output.splitlines() if ln.strip()][-3:]
    dicts = []
    for text in reversed(candidates + [output.strip()]):
        try:
            data = json.loads(text)
        except ValueError:
            continue
        if isinstance(data, dict):
            dicts.append(data)
    for data in dicts:
        if data.get("type") == "result":
            return data
    return dicts[0] if dicts else {}


# Windows tree containment (WI-881): the session child is created suspended,
# put into a job object of its own, then resumed, so every process it ever
# spawns is born inside the job before it can spawn one.
_CREATE_SUSPENDED = 0x00000004
# PROCESS_TERMINATE | PROCESS_SUSPEND_RESUME | PROCESS_SET_QUOTA: what
# AssignProcessToJobObject and NtResumeProcess require of the child's handle.
_JOB_ASSIGN_ACCESS = 0x0001 | 0x0800 | 0x0100
# QueryInformationJobObject's JobObjectBasicProcessIdList class, the room for
# that list, and the SYNCHRONIZE right a wait on a member needs.
_JOB_PROCESS_ID_LIST = 3
_JOB_PID_CAPACITY = 4096
_SYNCHRONIZE = 0x00100000
# What the kill opens a member with: SYNCHRONIZE to wait on it. OpenProcess
# fails with ERROR_INVALID_PARAMETER for a pid that no longer exists.
_MEMBER_ACCESS = _SYNCHRONIZE
_ERROR_INVALID_PARAMETER = 87
# SR-238's stated bound: after the kill, _kill_tree waits this many seconds at
# most for the session's process group (POSIX) or job (Windows) to empty, then
# raises instead of letting the coordinator continue beside a survivor.
_TREE_END_SECONDS = 10.0


class TreeNotEnded(OSError):
    """A session's process tree could not be ended, or could not be shown to
    have ended, within _TREE_END_SECONDS. A writer may still be running, so
    the run must stop; callers let it propagate. The machinery's own OSError
    is kept as its cause.

    Implements: SR-238, LLR-026
    """


class _JobPidList(ctypes.Structure):
    """JOBOBJECT_BASIC_PROCESS_ID_LIST, sized for _JOB_PID_CAPACITY members."""

    _fields_ = [
        ("NumberOfAssignedProcesses", ctypes.c_uint32),
        ("NumberOfProcessIdsInList", ctypes.c_uint32),
        ("ProcessIdList", ctypes.c_size_t * _JOB_PID_CAPACITY),
    ]


def _contain_in_job(proc):
    """Windows: put the SUSPENDED session child in a fresh job object, then
    resume it. The job is published on `proc.session_job` as soon as the
    child is in it, BEFORE the resume. The job handle closes when `proc` is
    collected; the job carries no kill-on-close limit, so closing it never
    ends a session. NtResumeProcess resumes the child because Popen does not
    keep its primary thread's handle. Raises OSError when any step fails.

    Implements: SR-026, LLR-026
    """
    k32, ntdll = _win32()
    job = k32.CreateJobObjectW(None, None)
    if not job:
        raise ctypes.WinError(ctypes.get_last_error())
    weakref.finalize(proc, k32.CloseHandle, job)
    handle = k32.OpenProcess(_JOB_ASSIGN_ACCESS, False, proc.pid)
    try:
        if not handle or not k32.AssignProcessToJobObject(job, handle):
            raise ctypes.WinError(ctypes.get_last_error())
        proc.session_job = job
        status = ntdll.NtResumeProcess(handle)
        if status:
            raise OSError(
                "NtResumeProcess failed: NTSTATUS 0x{:08X}".format(status & 0xFFFFFFFF)
            )
    finally:
        if handle:
            k32.CloseHandle(handle)


def _spawn_session(argv, **popen_kwargs):
    """Start the session child so that _kill_tree can later end its WHOLE
    process tree (repo-review 2026-07-21 H-2): CLI-spawned tool subprocesses
    otherwise survive the direct child's kill and keep editing the worktree
    the coordinator hands to the next session. POSIX: the child leads a new
    session and process group. Windows: the child is born suspended, contained
    in its own job object, then resumed (_contain_in_job); a child that cannot
    be contained is killed before it ever runs and the OSError propagates.

    Implements: SR-026, LLR-026
    """
    if os.name != "nt":
        return subprocess.Popen(argv, start_new_session=True, **popen_kwargs)
    proc = subprocess.Popen(argv, creationflags=_CREATE_SUSPENDED, **popen_kwargs)
    try:
        _contain_in_job(proc)
    except OSError:
        with proc:  # closes the pipes and reaps the never-run child
            proc.kill()
        raise
    return proc


def _kill_tree(proc):
    """End the session's whole process tree, not just the direct child, and
    return only once it HAS ended: a `.cmd`-shim CLI's real work happens in a
    grandchild (cmd.exe -> node), and a survivor keeps editing the worktree
    the coordinator is about to hand to the next session (repo-review
    2026-07-21 H-2). `proc` comes from _spawn_session. POSIX: the child leads
    its own process group, so SIGKILL the group. Windows: take a handle on
    each member of the job every descendant was born into, then terminate the
    job, which reaches an orphaned grandchild too (_terminate_job); the
    handles are closed once the wait ends or raises.
    It replaced `taskkill /F /T`, which on a 2026-10-08 Windows build waited
    about 60 s and then failed without killing anything (WI-881). Then wait
    (D-003): the direct child is reaped and the group or job polled until it
    is empty. A tree not empty within _TREE_END_SECONDS, or any failure of the
    kill machinery, raises TreeNotEnded naming the survivor and the cause, so
    the coordinator stops instead of continuing beside it.
    A descendant that left the group, or a process started outside the job on
    the session's behalf, is not reached (D-002).

    Implements: SR-238, LLR-026
    """
    try:
        if os.name == "nt":
            _end_job_tree(proc)
        else:
            _end_group_tree(proc)
    except OSError as exc:
        raise TreeNotEnded(
            "the session tree of child {} was not ended: {}".format(proc.pid, exc)
        ) from exc


def _end_job_tree(proc):
    """Windows: terminate the session's job and wait until it has ended; the
    member handles are closed once the wait ends or raises.

    Implements: SR-238, LLR-026
    """
    job, members = proc.session_job, []
    try:
        _terminate_job(job, members)
        _await_tree_end(proc, functools.partial(_job_survivors, job, members))
    finally:
        _close_handles(members)


def _end_group_tree(proc):
    """POSIX: SIGKILL the session's process group and wait until it is empty.

    Implements: SR-238, LLR-026
    """
    pgid = proc.pid  # start_new_session: the child leads its own group
    try:
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        pass  # the group has already emptied
    _await_tree_end(proc, functools.partial(_group_survivors, pgid))


def _terminate_job(job, members):
    """Windows: open every member into `members`, then terminate the job.
    The job terminate is what takes members off the list before they are
    signalled, which is why the handles are taken before it: the job's
    active-process count reaches zero a few milliseconds before a terminated
    process is signalled. The terminate runs even when an earlier step fails,
    and that error then raises. A live member the kill could not open makes
    it raise after the terminate, naming the pid, because the kill cannot
    wait on it (S3).

    Implements: SR-238, LLR-026
    """
    k32, _ = _win32()
    unopened = []
    try:
        _open_job_members(job, members, unopened)
    finally:
        terminated = k32.TerminateJobObject(job, 1)
    if not terminated:
        raise ctypes.WinError(ctypes.get_last_error())
    if unopened:
        raise OSError(
            "the session's job was terminated, but the kill cannot wait on "
            "members it could not open: {}".format(
                ", ".join("pid {} (error {})".format(*m) for m in unopened)
            )
        )


def _open_job_members(job, handles, unopened):
    """Windows: append a handle on every process now in the job to `handles`,
    and append `(pid, error)` to `unopened` for each live member that could
    not be opened. A pid that no longer exists is skipped.

    Implements: SR-238, LLR-026
    """
    k32, _ = _win32()
    pids = _JobPidList()
    if not k32.QueryInformationJobObject(
        job, _JOB_PROCESS_ID_LIST, ctypes.byref(pids), ctypes.sizeof(pids), None
    ):
        raise ctypes.WinError(ctypes.get_last_error())
    for pid in pids.ProcessIdList[: pids.NumberOfProcessIdsInList]:
        handle = k32.OpenProcess(_MEMBER_ACCESS, False, pid)
        if not handle:
            error = ctypes.get_last_error()
            if error != _ERROR_INVALID_PARAMETER:
                unopened.append((pid, error))
            continue
        handles.append(handle)  # owned by the caller from here, even on a raise


def _close_handles(handles):
    """Windows: close each handle in `handles`.

    Implements: SR-238, LLR-026
    """
    k32, _ = _win32()
    for handle in handles:
        k32.CloseHandle(handle)


def _job_survivors(job, members):
    """Windows: "" once the job is empty and every member it held at the kill
    is signalled, else what is still running.

    Implements: SR-238, LLR-026
    """
    count = _job_active_processes(job)
    if count:
        return "{} processes still in the session's job".format(count)
    k32, _ = _win32()
    running = sum(1 for h in members if k32.WaitForSingleObject(h, 0) != 0)
    return (
        "{} processes of the session's job not yet ended".format(running)
        if running
        else ""
    )


def _group_survivors(pgid):
    """POSIX: "" once no process is left in the group, else what is. A killed
    grandchild is reaped by init once the reaped child no longer parents it.

    Implements: SR-238, LLR-026
    """
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return ""
    return "a process still in the session's process group {}".format(pgid)


def _await_tree_end(proc, survivors):
    """Reap the killed direct child, then poll `survivors()` until it reports
    an empty tree; past _TREE_END_SECONDS raise OSError naming what is left.

    Implements: SR-238, LLR-026
    """
    bound = _TREE_END_SECONDS
    deadline = time.monotonic() + bound
    try:
        proc.wait(timeout=bound)
    except subprocess.TimeoutExpired:
        raise OSError(
            "session child {} still running {}s after the kill".format(proc.pid, bound)
        ) from None
    while True:
        left = survivors()
        if not left:
            return
        if time.monotonic() >= deadline:
            raise OSError("{}s after the kill: {}".format(bound, left))
        time.sleep(0.05)


def summarize_session_line(line):
    """Parse one line of session output into zero or more compact console
    summaries (WI-125) — shared by the scrolling echo (echo_session_line) and
    the in-place live line (LiveStatus, WI-136). stream-json events render as
    `  > <assistant text>` / `  * <tool name>`; result/system/user events are
    suppressed (the coordinator prints its own outcome line, and tool results
    re-echo file contents). A line that isn't a JSON event — a plain-text CLI
    like opencode — passes through as one truncated summary. Every summary is
    truncated for console hygiene; the FULL stream is still captured for the
    session log + out/run-logs regardless."""
    s = line.rstrip()
    if not s:
        return []
    if s.startswith("{"):
        try:
            evt = json.loads(s)
        except ValueError:
            evt = None
        if isinstance(evt, dict):
            out = []
            if evt.get("type") == "assistant":
                for block in (evt.get("message") or {}).get("content") or []:
                    if block.get("type") == "text" and block.get("text", "").strip():
                        txt = " ".join(block["text"].split())
                        out.append(
                            "  > {}".format(
                                txt[:240] + ("..." if len(txt) > 240 else "")
                            )
                        )
                    elif block.get("type") == "tool_use":
                        out.append("  * {}".format(block.get("name", "tool")))
            return out  # every other event type is log detail, not progress
    return [s[:240] + ("..." if len(s) > 240 else "")]


def echo_session_line(line):
    """Scrolling live echo (WI-125): print each compact summary of one output
    line so a walk-away console shows progress instead of silent minutes."""
    for summary in summarize_session_line(line):
        print(summary)


def _stdout_is_tty():
    """True only when the coordinator console is an interactive terminal — the
    gate for the in-place live line (WI-136). A pipe / redirect / CI log is not
    a TTY, so it keeps the append-only scroll (CI logs must stay append-only)."""
    try:
        return bool(sys.stdout.isatty())
    except Exception:
        return False


def _enable_windows_vt():
    """Best-effort enable of ANSI/VT escape processing for the current Windows
    console (modern conhost + Windows Terminal support it, but the flag can be
    off). stdlib-only via ctypes — no curses / colorama dependency. Returns True
    when VT is usable (always so on a non-Windows OS), False when it could not be
    turned on, so the caller falls back to the plain scroll rather than emit raw
    escape bytes (never-breaking)."""
    if os.name != "nt":
        return True
    try:
        import ctypes

        kernel32 = ctypes.windll.kernel32
        handle = kernel32.GetStdHandle(-11)  # STD_OUTPUT_HANDLE
        if not handle or handle == -1:
            return False
        mode = ctypes.c_uint()
        if not kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
            return False
        enable_vt = 0x0004  # ENABLE_VIRTUAL_TERMINAL_PROCESSING
        if mode.value & enable_vt:
            return True
        return bool(kernel32.SetConsoleMode(handle, mode.value | enable_vt))
    except Exception:
        return False


class LiveStatus:
    """One in-place console status line for a workstream (WI-136). Opt-in
    (--live-status / [checks] live_status) and used only when stdout is a TTY with
    VT enabled — a non-TTY keeps the scrolling echo. Each streamed event
    rewrites a single line (carriage-return + clear-to-EOL) instead of
    scrolling, so a long walk-away session shows its current step rather than
    30 silent minutes. The FULL stream is still captured for the session log +
    out/run-logs; this only changes what the console shows."""

    def __init__(self, label):
        self.label = label
        self.active = False

    def event(self, line):
        for summary in summarize_session_line(line):
            self._render(summary)

    def _render(self, summary):
        prefix = "  [{}] ".format(self.label)
        width = shutil.get_terminal_size((80, 24)).columns
        text = (prefix + " ".join(summary.split()))[: max(1, width - 1)]
        # \r to column 0, \x1b[2K to clear the whole line, then rewrite it.
        sys.stdout.write("\r\x1b[2K" + text)
        sys.stdout.flush()
        self.active = True

    def finish(self):
        """Close the live line with a newline so the next scrolling print starts
        clean — a no-op when nothing was ever rendered (an idle/errored session)."""
        if self.active:
            sys.stdout.write("\n")
            sys.stdout.flush()
            self.active = False


def _pump_stdout(proc, lines, last_line, on_line):
    """The reader thread's body: pump every stdout line into `lines`, stamp
    `last_line[0]` (the idle deadline's clock, C3), and hand the line to the
    optional renderer. A module-level function, not a closure — the C901 trap
    charges a nested def to its enclosing function. The renderer is a
    convenience; the pump is load-bearing: a renderer that raises (a cp1252
    console meeting a `→`, measured 2026-08-30) must not stop the pump, or an
    unpumped pipe fills, the child blocks on its next write, and the session
    reads as a silent hang until a deadline fires."""
    for line in proc.stdout:
        lines.append(line)
        last_line[0] = time.time()
        if on_line is not None:
            try:
                on_line(line)
            except Exception:
                pass
    proc.stdout.close()


def _wait_for_exit(proc, timeout, idle_timeout, last_line):
    """Wait out ONE session under its two deadlines (C3, the stall-guard
    plan): `timeout` bounds the WALL, `idle_timeout` bounds SILENCE against
    `last_line` (the reader thread's stamp of the child's most recent output).
    Returns `(killed_message, killed_kind)` — `("", False)` for a child that
    exited on its own, kind `True` for the wall (the historical timed_out
    value, so every truthiness read holds) and `"idle"` for the idle kill.
    Polls in one-second slices only when a deadline exists; with neither it
    blocks exactly as the pre-C3 wait did. It ends nothing itself: an
    interruption propagates to run_session, whose one `finally` ends the
    whole tree (start_new_session detaches the child from the terminal group,
    so Ctrl+C no longer reaches it implicitly)."""
    wall_deadline = (time.time() + timeout) if timeout else None
    slice_ = 1.0 if (wall_deadline is not None or idle_timeout) else None
    while True:
        try:
            proc.wait(timeout=slice_)
            return "", False
        except subprocess.TimeoutExpired:
            now = time.time()
            if wall_deadline is not None and now >= wall_deadline:
                return "session timed out after {}s".format(timeout), True
            if idle_timeout and now - last_line[0] >= idle_timeout:
                return (
                    "session idle-timed out after {}s of silence "
                    "(idle-timeout {}s, wall {}s)".format(
                        int(now - last_line[0]), idle_timeout, timeout
                    ),
                    "idle",
                )


def _feed_stdin(proc, text):
    """The feeder thread's body: write the fixed prompt to the child's stdin,
    then close it so the child sees EOF. A module-level function, not a
    closure, for the same C901 reason as _pump_stdout.

    Implements: SR-026, LLR-026
    """
    try:
        proc.stdin.write(text)
    except (OSError, ValueError):
        pass  # child exited early; its status is captured by wait() below
    finally:
        try:
            proc.stdin.close()
        except (OSError, ValueError):
            pass


def _start_session_io(proc, lines, last_line, on_line, stdin_input):
    """Start the session's I/O threads and return the stdout pump. A reader
    thread pumps the pipe so the child can never block on a full buffer while
    the main thread waits, the same shape subprocess.run uses internally,
    opened up so each line can be echoed as it arrives. The prompt, when
    given, is delivered from a DAEMON thread and stdin is then closed.
    Threaded, not inline, so a large prompt to a child that never drains
    stdin cannot block the main thread before the wait's timeout. The
    timeout still fires and kills the child, so the no-wedge invariant
    (SN-016) holds. The stdout pump is already draining, so the reverse
    deadlock (the child writing before it finishes reading) cannot happen
    either.

    Implements: SR-026, LLR-026
    """
    pump = threading.Thread(
        target=_pump_stdout, args=(proc, lines, last_line, on_line), daemon=True
    )
    pump.start()
    if stdin_input is not None:
        threading.Thread(
            target=_feed_stdin, args=(proc, stdin_input), daemon=True
        ).start()
    return pump


def run_session(
    argv, root, timeout, env=None, on_line=None, stdin_input=None, idle_timeout=None
):
    """One fresh headless driver session. Returns (exit_code, output,
    timed_out). stdin is closed so a CLI that would wait on it can't hang —
    UNLESS `stdin_input` is given, in which case that fixed text is written to the
    child's stdin which is then closed: the child reads its prompt and sees EOF,
    so the no-wedge invariant (SN-016) still holds — there is never an interactive
    read. This is how a CmdTemplate with no `{prompt}` placeholder delivers the
    prompt (build_argv), keeping the command line short enough for the Windows
    cmd.exe 8191-char cap on `.CMD`-shim CLIs.

    `env` is the merged environment for a pair row that declares one (the
    registry `Env` column, already merged over os.environ by the caller); None
    means inherit the ambient environment exactly — today's call, byte for
    byte. `on_line`, when given, is called with each output line as it arrives —
    the console renderer (echo_session_line's scroll, WI-125, or LiveStatus's
    in-place line, WI-136); the returned output is the full captured stream
    either way."""
    if os.name == "nt":
        # CreateProcess resolves a bare argv[0] only to .exe/.com — never the
        # PATHEXT script shims (.cmd/.bat) npm-style CLIs install on Windows —
        # while preflight's shutil.which honors PATHEXT, so a shim-only CLI
        # passes preflight then dies here with [WinError 2] (WI-120). Hand
        # CreateProcess the which-resolved path (an explicit .cmd runs fine);
        # a miss, or a .ps1-only resolution (no CreateProcess interposition),
        # falls through unchanged to the OSError sentinel below.
        resolved = shutil.which(argv[0], path=(env or os.environ).get("PATH"))
        if resolved and not resolved.lower().endswith(".ps1"):
            argv = [resolved] + argv[1:]

    # The idle deadline's clock (C3, docs/plans/2026-08-30-stall-guard-plan.md):
    # the reader thread stamps the last time the child SAID anything, so the
    # waiter can kill a session that has gone silent without waiting for the
    # wall deadline. A one-element list, not a bare float: the pump thread
    # rebinding a closure-captured float would be invisible to the waiter.
    lines, last_line, natural_exit = [], [time.time()], False
    try:
        _validate_prompt_transport(argv, stdin_input, env=env)
        # Spawned so a timeout or interrupt can kill the WHOLE tree
        # (_kill_tree): a process group on POSIX, a job object on Windows.
        proc = _spawn_session(
            argv,
            cwd=str(root),
            stdin=(subprocess.PIPE if stdin_input is not None else subprocess.DEVNULL),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
        )
    except (OSError, ValueError) as exc:
        return -1, "coordinator: session error: {}".format(exc), False
    # From here run_session supervises the child. The `finally` is the one
    # place the tree is ended: at a deadline, on an interruption, or when the
    # I/O setup fails, but never after a natural exit. TWO deadlines (C3):
    # `timeout` bounds the WALL and `idle_timeout` bounds SILENCE. A child
    # that stops emitting used to be discovered only at the wall; two silent
    # hangs on 2026-08-30 each went quiet minutes in and burned a 7200 s wall
    # slot.
    try:
        pump = _start_session_io(proc, lines, last_line, on_line, stdin_input)
        killed, killed_kind = _wait_for_exit(proc, timeout, idle_timeout, last_line)
        natural_exit = not killed
    finally:
        if not natural_exit:
            _kill_tree(proc)
    pump.join(5)
    if killed:
        return -1, "".join(lines) + "\ncoordinator: " + killed, killed_kind
    return proc.returncode, "".join(lines), False
