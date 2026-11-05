"""The Windows job-object helpers the kit's job callers share.

WHY IT EXISTS (WI-940). The session kill (`agent_session.py`) puts each
headless session in a job object and reads the job's basic accounting to
know when its tree has ended. The same prototypes and the same accounting
structure serve every other job caller, so they live here once instead of
in each caller. What stays in `agent_session` is the kill itself: the
process-id list, the containment, the terminate and the survivor wait. The
smoke budget step (`scripts/check_smoke_budget.py`) meters its tier through
the same accounting: it creates and joins an unnamed job, then reads the
CPU seconds the job's processes used.
WHAT IT TOUCHES. kernel32 and ntdll are loaded only when `win32()` is
called, so the module imports cleanly on POSIX, where nothing calls it.
Stdlib only (`ctypes`, `functools`), and no sibling import.

Contracts: IF-302 — the interface seam this module declares (process.md §8;
row of record in docs/requirements/interfaces.toml).

Contract IF-302: win32() -> (kernel32, ntdll), declared once and cached, with
    the prototypes the job calls need (among them SetInformationJobObject,
    IsProcessInJob, GetCurrentProcess and SetPriorityClass); JobAccounting, the basic-accounting
    structure; job_active_processes(job) -> int, the job's active-process
    count, raising OSError when the query fails; create_joined_job() -> job,
    a new unnamed job the calling process has joined, raising OSError when it
    cannot be made or joined; job_cpu_seconds(job) -> float, the user plus
    kernel seconds of every process the job has held, raising OSError when
    the query fails.
"""

import ctypes
import functools

# QueryInformationJobObject's JobObjectBasicAccountingInformation class.
_JOB_BASIC_ACCOUNTING = 1


class JobAccounting(ctypes.Structure):
    """JOBOBJECT_BASIC_ACCOUNTING_INFORMATION; ActiveProcesses is the count
    _kill_tree waits on."""

    _fields_ = [
        ("TotalUserTime", ctypes.c_int64),
        ("TotalKernelTime", ctypes.c_int64),
        ("ThisPeriodTotalUserTime", ctypes.c_int64),
        ("ThisPeriodTotalKernelTime", ctypes.c_int64),
        ("TotalPageFaultCount", ctypes.c_uint32),
        ("TotalProcesses", ctypes.c_uint32),
        ("ActiveProcesses", ctypes.c_uint32),
        ("TotalTerminatedProcesses", ctypes.c_uint32),
    ]


@functools.lru_cache(maxsize=None)
def win32():
    """kernel32 and ntdll with the prototypes the job calls need, declared
    once: an undeclared HANDLE is passed as a 32-bit int on x64 and truncates.

    Implements: SR-026, LLR-026
    """
    from ctypes import wintypes

    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.CreateJobObjectW.restype = wintypes.HANDLE
    k32.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
    k32.OpenProcess.restype = wintypes.HANDLE
    k32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    k32.AssignProcessToJobObject.restype = wintypes.BOOL
    k32.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
    k32.TerminateJobObject.restype = wintypes.BOOL
    k32.TerminateJobObject.argtypes = [wintypes.HANDLE, wintypes.UINT]
    k32.QueryInformationJobObject.restype = wintypes.BOOL
    k32.QueryInformationJobObject.argtypes = [
        wintypes.HANDLE,
        ctypes.c_int,
        ctypes.c_void_p,
        wintypes.DWORD,
        ctypes.POINTER(wintypes.DWORD),
    ]
    k32.WaitForSingleObject.restype = wintypes.DWORD
    k32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    k32.CloseHandle.argtypes = [wintypes.HANDLE]
    k32.SetInformationJobObject.restype = wintypes.BOOL
    k32.SetInformationJobObject.argtypes = [
        wintypes.HANDLE,
        ctypes.c_int,
        ctypes.c_void_p,
        wintypes.DWORD,
    ]
    k32.IsProcessInJob.argtypes = [
        wintypes.HANDLE,
        wintypes.HANDLE,
        ctypes.POINTER(wintypes.BOOL),
    ]
    k32.GetCurrentProcess.restype = wintypes.HANDLE
    k32.SetPriorityClass.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    ntdll = ctypes.WinDLL("ntdll")
    ntdll.NtResumeProcess.restype = ctypes.c_long  # an NTSTATUS; 0 is success
    ntdll.NtResumeProcess.argtypes = [wintypes.HANDLE]
    return k32, ntdll


def _accounting(job):
    """The job's basic accounting, the one query both readers share.

    Implements: SR-238, LLR-026
    """
    k32, _ = win32()
    info = JobAccounting()
    if not k32.QueryInformationJobObject(
        job, _JOB_BASIC_ACCOUNTING, ctypes.byref(info), ctypes.sizeof(info), None
    ):
        raise ctypes.WinError(ctypes.get_last_error())
    return info


def job_active_processes(job):
    """Windows: the job's active-process count.

    Implements: SR-238, LLR-026
    """
    return _accounting(job).ActiveProcesses


def job_cpu_seconds(job):
    """Windows: the CPU seconds, user plus kernel, every process the job has
    held has used, exited ones included. The counters are 100 ns ticks."""
    info = _accounting(job)
    return (info.TotalUserTime + info.TotalKernelTime) / 1e7


def create_joined_job():
    """Windows: a new unnamed job with the calling process inside it, so every
    process it starts from now on is born in the job. No other process can
    open an unnamed job by name. A process already in a job nests the new one
    inside it. Raises OSError when the job cannot be made or joined."""
    k32, _ = win32()
    job = k32.CreateJobObjectW(None, None)
    if not job:
        raise ctypes.WinError(ctypes.get_last_error())
    if not k32.AssignProcessToJobObject(job, k32.GetCurrentProcess()):
        error = ctypes.get_last_error()
        k32.CloseHandle(job)
        raise ctypes.WinError(error)
    return job
