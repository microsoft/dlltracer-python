import dlltracer
import io
import pathlib
import pytest
import sys


def test_out():
    assert "_ssl" not in sys.modules

    buffer = io.StringIO()
    with dlltracer.Trace(out=buffer):
        import _ssl

    assert "_ssl.pyd" in buffer.getvalue()


def test_collect():
    assert "_msi" not in sys.modules

    with dlltracer.Trace(collect=True) as events:
        import _msi

    assert events
    names = set()
    for e in events:
        assert isinstance(e, dlltracer.LoadEvent)
        assert e.path
        assert repr(e)
        assert str(e)
        names.add(pathlib.PurePath(e.path).stem.casefold())
    assert "_msi" in names


def test_audit():
    assert "_overlapped" not in sys.modules

    try:
        with dlltracer.Trace(audit=True):
            import _overlapped
    except NotImplementedError:
        assert sys.version_info[:2] < (3, 8)

    # TODO: Collect and verify the hooked events in a subprocess
    # For now, we simply ensure that we do not crash when raising them


def test_debug():
    assert "_sqlite3" not in sys.modules

    with dlltracer.Trace(debug=True, collect=True) as events:
        import _sqlite3

    assert events
    for e in events:
        assert isinstance(e, dlltracer.DebugEvent)
        assert e.provider
        assert e.opcode
        assert e.header is not None
        assert e.data is not None
        assert repr(e)
        assert str(e)
