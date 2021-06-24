# dlltracer

The `dlltracer` tool is an assistive tool for diagnosing import errors in
CPython when they are caused by DLL resolution failures on Windows.

In general, any DLL load error is reported as an `ImportError` of the top-level
extension module. No more specific information is available for CPython to
display, which can make it difficult to diagnose.

This tool uses not-quite-documented performance events to report on the
intermediate steps of importing an extension module. These events are
undocumented and unsupported, so the format has been inferred by example and may
change, but until it does it will report on the loads that _actually occur_.
However, because it can't report on loads that _never_ occur, you'll still need
to do some work to diagnose the root cause of the failure.

The most useful static analysis tool is
[dumpbin](https://docs.microsoft.com/cpp/build/reference/dumpbin-reference),
which is included with Visual Studio. When passed a DLL or PYD file and the
`/imports` option, it will list all dependencies that _should be_ loaded. It
shows them by name, that is, before path resolution occurs.

`dlltracer` performs dynamic analysis, which shows the DLLs that are loaded at
runtime with their full paths. Combined with understanding the dependency
graph of your module, it is easier to diagnose why the overall import fails.


# Install

```
pip install dlltracer
```

Where the `pip` command may be replaced by a more appropriate command for your
environment, such as `python -m pip` or `pip3.9`.


# Use

*Note:* Regardless of how output is collected, this tool *must be run as
Administrator*. Otherwise, starting a trace will fail with a `PermissionError`.
Only one thread may be tracing across your entire machine. Because the state
of traces is not well managed by Windows, this tool will attempt to stop any
other running traces.

A basic trace that prints messages to standard output is:

```python
import dlltracer
import sys

with dlltracer.Trace(out=sys.stdout):
    import module_to_trace
```

The output may look like this (for `import ssl`):

```
LoadLibrary \Device\HarddiskVolume3\Windows\System32\kernel.appcore.dll
LoadLibrary \Device\HarddiskVolume3\Program Files\Python39\DLLs\_ssl.pyd
LoadLibrary \Device\HarddiskVolume3\Windows\System32\crypt32.dll
LoadLibrary \Device\HarddiskVolume3\Program Files\Python39\DLLs\libcrypto-1_1.dll
LoadLibrary \Device\HarddiskVolume3\Program Files\Python39\DLLs\libssl-1_1.dll
LoadLibrary \Device\HarddiskVolume3\Windows\System32\user32.dll
LoadLibrary \Device\HarddiskVolume3\Windows\System32\win32u.dll
LoadLibrary \Device\HarddiskVolume3\Windows\System32\gdi32.dll
LoadLibrary \Device\HarddiskVolume3\Windows\System32\gdi32full.dll
LoadLibrary \Device\HarddiskVolume3\Windows\System32\msvcp_win.dll
LoadLibrary \Device\HarddiskVolume3\Windows\System32\imm32.dll
LoadLibrary \Device\HarddiskVolume3\Program Files\Python39\DLLs\_socket.pyd
LoadLibrary \Device\HarddiskVolume3\Program Files\Python39\DLLs\select.pyd
```

A failed import may look like this (for `import ssl` but with `libcrypto-1_1.dll`
missing):

```
LoadLibrary \Device\HarddiskVolume3\Windows\System32\kernel.appcore.dll
LoadLibrary \Device\HarddiskVolume3\Program Files\Python39\DLLs\_ssl.pyd
LoadLibrary \Device\HarddiskVolume3\Windows\System32\crypt32.dll
LoadLibrary \Device\HarddiskVolume3\Program Files\Python39\DLLs\libssl-1_1.dll
Failed \Device\HarddiskVolume3\Windows\System32\crypt32.dll
Failed \Device\HarddiskVolume3\Program Files\Python39\DLLs\libssl-1_1.dll
Failed \Device\HarddiskVolume3\Program Files\Python39\DLLs\_ssl.pyd
Traceback (most recent call last):
  File "C:\Projects\test-script.py", line 28, in <module>
    import ssl
  File "C:\Program Files\Python39\lib\ssl.py", line 98, in <module>
    import _ssl             # if we can't import it, let the error propagate
ImportError: DLL load failed while importing _ssl: The specified module could not be found.
```

Notice that the missing DLL is never mentioned, and so human analysis is
necessary to diagnose the root cause.

## Write to file

To write output to a file-like object (anything that can be passed to the
`file=` argument of `print`), pass it as the `out=` argument of `Trace`.

```python
import dlltracer

with open("log.txt", "w") as log:
    with dlltracer.Trace(out=log):
        import module_to_trace
```


## Collect to list

To collect events to an iterable object, pass `collect=True` to `Trace` and
bind the context manager. The result will be a list containing event objects,
typically `dlltracer.LoadEvent` and `dlltracer.LoadFailedEvent`.

```python
import dlltracer

with dlltracer.Trace(collect=True) as events:
    try:
        import module_to_trace
    except ImportError:
        # If we don't handle the error, program will exit before
        # we get to inspect the events.
        pass

# Inspect the events after ending the trace
all_loaded = {e.path for e in events if isinstance(e, dlltracer.LoadEvent)}
all_failed = {e.path for e in events if isinstance(e, dlltracer.LoadFailedEvent)}
```

## Raise audit events

To raise audit events for DLL loads, pass `audit=True` to `Trace`. The events
raised are `dlltracer.load` and `dlltracer.failed`, and both only include the
path as an argument.

```python
import dlltracer
import sys

def hook(event, args):
    if event == "dlltracer.load":
        # args = (path,)
        print("Loaded", args[0])
    elif event == "dlltracer.failed":
        # args = (path,)
        print("Failed", args[0])

sys.add_audit_hook(hook)

with dlltracer.Trace(audit=True):
    import module_to_trace
```


## Additional events

*Note:* This is mainly intended for development of `dlltracer`.

Because event formats may change, and additional events may be of interest but
are not yet handled, passing the `debug=True` option to `Trace` enables all
events to be collected, written, or audited. Regular events are suppressed.

```python
import dlltracer
import sys

def hook(event, args):
    if event != "dlltracer.debug":
        return

    # args schema:
    #   provider is a UUID representing the event source
    #   opcode is an int representing the operation
    #   header is bytes taken directly from the event header
    #   data is bytes taken directly from the event data
    provider, opcode, header, data = args

sys.add_audit_hook(hook)

with dlltracer.Trace(debug=True, audit=True, collect=True, out=sys.stderr) as events:
    try:
        import module_to_trace
    except ImportError:
        pass

for e in events:
    assert isinstance(e, dlltracer.DebugEvent)
    # DebugEvent contains provider, opcode, header and data as for the audit event
```


# Contribute

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.


# Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
