
# cython: language_level=3

from libc.string cimport memcpy, memset
from cpython cimport version as sys_version
from cpython.ref cimport PyObject, Py_INCREF

from os.path import realpath as _realpath
from threading import Thread as _Thread
from uuid import UUID as _UUID

_SystemTraceControlGuid = _UUID("9e814aad-3204-11d2-9a82-006008a86939")
_LoadLibraryProvider = _UUID('2cb15d1d-5fc1-11d2-abe1-00a0c911f518')

cdef extern from "dlltracer/audit_stub.h":
    cdef int PySys_Audit(const char* event, const char* fmt, ...) except -1


cdef extern from "windows.h" nogil:
    ctypedef void* HANDLE
    ctypedef void* HMODULE
    ctypedef const char* LPCSTR
    ctypedef char* LPSTR
    ctypedef const Py_UNICODE* LPCWSTR
    ctypedef Py_UNICODE* LPWSTR
    ctypedef unsigned char UCHAR
    ctypedef unsigned int USHORT
    ctypedef unsigned int ULONG
    ctypedef unsigned long ULONGLONG
    ctypedef size_t ULONG_PTR
    ctypedef unsigned int NTSTATUS

    ctypedef struct GUID:
        pass

    ULONG GetLastError()

    ULONG WNODE_FLAG_TRACED_GUID
    ULONG EVENT_TRACE_REAL_TIME_MODE
    ULONG EVENT_TRACE_FLAG_IMAGE_LOAD
    LPCWSTR KERNEL_LOGGER_NAMEW

    ULONG ERROR_WMI_INSTANCE_NOT_FOUND

    cdef ULONG GetCurrentProcessId()


cdef extern from "wmistr.h" nogil:
    ctypedef struct WNODE_HEADER:
        ULONG BufferSize
        GUID Guid
        ULONG ClientContext
        ULONG Flags


cdef extern from "evntrace.h" nogil:
    ctypedef void* TRACEHANDLE
    ctypedef TRACEHANDLE* PTRACEHANDLE

    TRACEHANDLE INVALID_PROCESSTRACE_HANDLE

    ctypedef struct EVENT_TRACE_PROPERTIES:
        WNODE_HEADER Wnode
        ULONG BufferSize
        ULONG LogFileMode
        ULONG FlushTimer
        ULONG EnableFlags
        ULONG LogFileNameOffset
        ULONG LoggerNameOffset

    ctypedef struct EVENT_DESCRIPTOR:
        USHORT Id
        UCHAR Channel
        UCHAR Level
        UCHAR Opcode
        USHORT Task
        ULONGLONG Keyword

    ctypedef struct EVENT_HEADER:
        USHORT Size
        USHORT HeaderType
        ULONG ProcessId
        GUID ProviderId
        EVENT_DESCRIPTOR EventDescriptor

    ctypedef struct EVENT_RECORD:
        EVENT_HEADER EventHeader
        ULONG UserDataLength
        void *UserData

    ctypedef void (__stdcall *PEVENT_RECORD_CALLBACK)(EVENT_RECORD* EventRecord) except * nogil
    ctypedef struct EVENT_TRACE_LOGFILEW:
        LPWSTR LoggerName
        ULONG ProcessTraceMode
        PEVENT_RECORD_CALLBACK EventRecordCallback

    cdef NTSTATUS ControlTraceW(TRACEHANDLE pHandle, LPCWSTR name, EVENT_TRACE_PROPERTIES* pProps, ULONG ControlCode)
    ULONG EVENT_TRACE_CONTROL_STOP

    cdef NTSTATUS StartTraceW(PTRACEHANDLE pHandle, LPCWSTR name, EVENT_TRACE_PROPERTIES* pProps)
    cdef NTSTATUS StopTraceW(TRACEHANDLE pHandle, LPCWSTR name, EVENT_TRACE_PROPERTIES* pProps)

    cdef TRACEHANDLE OpenTraceW(EVENT_TRACE_LOGFILEW* file)
    cdef ULONG ProcessTrace(TRACEHANDLE* harray, ULONG handleCount, void* t1, void* t2)
    cdef void CloseTrace(TRACEHANDLE h)


cdef extern from "Evntcons.h" nogil:
    ULONG PROCESS_TRACE_MODE_REAL_TIME
    ULONG PROCESS_TRACE_MODE_EVENT_RECORD
    ULONG PROCESS_TRACE_MODE_RAW_TIMESTAMP


cdef ULONG _pid = GetCurrentProcessId()
cdef object _collect = None
cdef object _out = None
cdef int _debug = 0
cdef int _audit = 0


class LoadEvent:
    def __init__(self, path): self.path = path
    def __repr__(self): return f"<LoadLibrary({self.path})>"
    def __str__(self):
        path = self.path
        if path.lower().startswith("\\device\\"):
            try:
                path = _realpath("\\\\." + path[7:])
            except OSError:
                pass
        return f"LoadLibrary {path}"


class LoadFailedEvent:
    def __init__(self, path): self.path = path
    def __repr__(self): return f"<LoadLibraryFailed({self.path})>"
    def __str__(self):
        path = self.path
        if path.lower().startswith("\\device\\"):
            try:
                path = _realpath("\\\\." + path[7:])
            except OSError:
                pass
        return f"Failed {self.path}"


class DebugEvent:
    # Use this later on for separating up bytes in the str view
    _sep = [" ", " ", " ", "  "] * 7 + [" ", " ", " ", "\n         "]
    # Some likely-looking path indices so we can render as string
    _opcode_path_index = {
        2: 0x38,
        3: 0x38,
        4: 0x38,
        10: 0x14,
        11: 0x28,
        12: 0x48,
        13: 0x14,
        15: 0x0C,
        21: 0x14,
        22: 0x20,
        25: 0,
        34: 0,
        35: 0x0C,
    }

    def __init__(self, provider, opcode, header, data):
        self.provider = provider
        self.opcode = opcode
        self.header = bytes(header)
        self.data = bytes(data)

    def __repr__(self):
        return f"<Debug({self.provider}, {self.opcode}, {self.header!r}, {self.data!r})>"

    def __str__(self):
        try:
            i = self._opcode_path_index[self.opcode]
            path = (self.data[i:]).decode("utf-16-le").rstrip(" \0")
            data = self.data[:i]
        except KeyError:
            path = ""
            data = self.data
        except Exception as ex:
            path = repr(ex)
            data = self.data
        return (
            f"{self.provider}: {self.opcode}" +
            "\nHeader = " +
            "".join(f"{c:02X}{self._sep[i%len(self._sep)]}" for i, c in enumerate(self.header)).rstrip() +
            "\nData   = " +
            "".join(f"{c:02X}{self._sep[i%len(self._sep)]}" for i, c in enumerate(data)).rstrip() +
            "\nPath   = " + path
        )


cdef int _check(ULONG r, str msg) except -1 nogil:
    if r == 0:
        return 0
    with gil:
        raise OSError(None, f"{msg} (0x{r:08X})", None, r & 0xFFFFFFFF)


cdef void __stdcall _event_record_callback(EVENT_RECORD* EventRecord) noexcept nogil:
    cdef EVENT_HEADER* hdr = &EventRecord.EventHeader
    cdef unsigned char* b = <unsigned char*>EventRecord.UserData
    cdef Py_ssize_t cb = <Py_ssize_t>EventRecord.UserDataLength
    cdef int is_loadlibrary = 0
    if hdr.ProcessId != _pid:
        return
    with gil:
        u = _UUID(bytes_le=(<unsigned char*>&hdr.ProviderId)[0:sizeof(GUID)])
        if u == _LoadLibraryProvider:
            is_loadlibrary = 1
    if _debug:
        with gil:
            b1 = bytes((<unsigned char*>&hdr.EventDescriptor)[0:sizeof(EVENT_DESCRIPTOR)])
            b2 = bytes(b[0:cb])
            if _collect is not None:
                _collect.append(DebugEvent(u, hdr.EventDescriptor.Opcode, b1, b2))
            if _out:
                print(DebugEvent(u, hdr.EventDescriptor.Opcode, b1, b2), file=_out)
            if _audit:
                PySys_Audit("dlltracer.debug", "OiOO",
                            <PyObject*>u, hdr.EventDescriptor.Opcode,
                            <PyObject*>b1, <PyObject*>b2)
        return

    if is_loadlibrary and hdr.EventDescriptor.Opcode == 10:
        if cb > 56:
            with gil:
                s = (b[56:cb]).decode("utf-16-le").rstrip("\0 ")
                if _collect is not None:
                    _collect.append(LoadEvent(s))
                if _out:
                    print(LoadEvent(s), file=_out, flush=True)
                if _audit:
                    PySys_Audit("dlltracer.load", "O", <PyObject*>s)
    elif is_loadlibrary and hdr.EventDescriptor.Opcode == 2:
        if cb > 56:
            with gil:
                s = (b[56:cb]).decode("utf-16-le").rstrip("\0 ")
                if _collect is not None:
                    _collect.append(LoadEvent(s))
                if _out:
                    print(LoadFailedEvent(s), file=_out, flush=True)
                if _audit:
                    PySys_Audit("dlltracer.failed", "O", <PyObject*>s)


cdef class Trace:
    cdef bytearray _props, _lf
    cdef TRACEHANDLE _h_write
    cdef TRACEHANDLE _h_read
    cdef object _thread
    cdef object _out
    cdef object _collect
    cdef bint _audit, _debug

    def __cinit__(self):
        self._h_write = NULL
        self._h_read = NULL

    def __init__(self, bint collect=False, out=None, bint audit=False, bint debug=False):
        cdef EVENT_TRACE_PROPERTIES *props
        cdef EVENT_TRACE_LOGFILEW* lf

        self._thread = None

        self._props = b = bytearray(sizeof(EVENT_TRACE_PROPERTIES) + 512)
        props = <EVENT_TRACE_PROPERTIES*><unsigned char*>self._props
        props.Wnode.BufferSize = len(b)
        gb = _SystemTraceControlGuid.bytes_le
        memcpy(&props.Wnode.Guid, <unsigned char*>gb, sizeof(GUID))
        props.Wnode.Flags = WNODE_FLAG_TRACED_GUID
        props.BufferSize = 1024
        props.LogFileMode = EVENT_TRACE_REAL_TIME_MODE
        props.FlushTimer = 1
        props.EnableFlags = EVENT_TRACE_FLAG_IMAGE_LOAD
        props.LoggerNameOffset = sizeof(EVENT_TRACE_PROPERTIES)

        self._lf = bytearray(sizeof(EVENT_TRACE_LOGFILEW))
        lf = <EVENT_TRACE_LOGFILEW*><unsigned char*>self._lf
        lf.LoggerName = KERNEL_LOGGER_NAMEW
        lf.ProcessTraceMode = (
            PROCESS_TRACE_MODE_REAL_TIME
            | PROCESS_TRACE_MODE_EVENT_RECORD
            | PROCESS_TRACE_MODE_RAW_TIMESTAMP
        )
        lf.EventRecordCallback = _event_record_callback

        self._collect = [] if collect else None
        self._out = out
        self._audit = audit
        if sys_version.PY_VERSION_HEX < 0x03080000 and audit:
            raise NotImplementedError("audit hooks are not available on this version of Python")
        self._debug = debug

    def __enter__(self):
        self.start()
        return self._collect

    def __dealloc__(self):
        self.close()

    def __exit__(self, *ex_info):
        self.close()

    def start(self):
        cdef EVENT_TRACE_PROPERTIES *props
        cdef EVENT_TRACE_LOGFILEW* lf
        cdef ULONG err = 0
        if self._thread:
            return
        props = <EVENT_TRACE_PROPERTIES*><unsigned char*>self._props
        lf = <EVENT_TRACE_LOGFILEW*><unsigned char*>self._lf
        with nogil:
            err = ControlTraceW(NULL, KERNEL_LOGGER_NAMEW, props, EVENT_TRACE_CONTROL_STOP)
            if err and err != ERROR_WMI_INSTANCE_NOT_FOUND:
                _check(err, "failed to stop existing trace")
            _check(
                StartTraceW(&self._h_write, KERNEL_LOGGER_NAMEW, props),
                "failed to start trace"
            )
            self._h_read = OpenTraceW(lf)
            if self._h_read == INVALID_PROCESSTRACE_HANDLE:
                err = GetLastError()
                self._h_read = NULL
            else:
                err = 0
        try:
            _check(err, "failed to start reading trace")
        except:
            self.close()
            raise

        self._thread = _Thread(target=_process_thread, args=(self,))
        self._thread.start()

    def close(self):
        if not self._thread or not self._h_write or not self._h_read:
            return
        cdef EVENT_TRACE_PROPERTIES *props = <EVENT_TRACE_PROPERTIES*><unsigned char*>self._props
        with nogil:
            _check(
                StopTraceW(self._h_write, KERNEL_LOGGER_NAMEW, props),
                "failed to stop collecting trace"
            )
            self._h_write = NULL
            CloseTrace(self._h_read)
            self._h_read = NULL
        self._thread.join()
        self._thread = None


cdef object _process_thread(Trace owner):
    global _collect, _out, _audit, _debug

    cdef ULONG err = 0
    cdef TRACEHANDLE h = <TRACEHANDLE>owner._h_read

    _collect = owner._collect
    _out = owner._out
    _audit = owner._audit
    _debug = owner._debug

    with nogil:
        err = ProcessTrace(&h, 1, NULL, NULL)
