import dlltracer
import io
import pathlib
import pytest
import sys


def _runner(fn, conn):
    try:
        conn.send(fn())
    finally:
        conn.close()


def run(fn):
    from multiprocessing import Pipe, Process

    parent_conn, child_conn = Pipe()
    p = Process(target=_runner, args=(fn, child_conn,))
    p.start()
    try:
        return parent_conn.recv()
    finally:
        p.join()
        p.close()


def do_test_out():
    assert "dlltracer._dlltracertest" not in sys.modules
    buffer = io.StringIO()
    with dlltracer.Trace(out=buffer):
        from dlltracer import _dlltracertest

    return buffer.getvalue()


def test_out():
    assert "_dlltracertest.pyd" in run(do_test_out)


def do_test_collect():
    assert "dlltracer._dlltracertest" not in sys.modules
    with dlltracer.Trace(collect=True) as events:
        from dlltracer import _dlltracertest

    return events


def test_collect():
    events = run(do_test_collect)
    assert events
    names = set()
    for e in events:
        assert isinstance(e, dlltracer.LoadEvent)
        assert e.path
        assert repr(e)
        assert str(e)
        names.add(pathlib.PurePath(e.path).stem.casefold())
    assert "_dlltracertest" in names


def do_test_audit():
    # TODO: Collect and verify the hooked events
    # For now, we simply ensure that we do not crash
    with dlltracer.Trace(audit=True):
        from dlltracer import _dlltracertest


@pytest.mark.skipif(sys.version_info[:2] <= (3, 7), reason="Requires Python 3.8 or later")
def test_audit():
    run(do_test_audit)


def do_test_debug():
    with dlltracer.Trace(debug=True, collect=True) as events:
        from dlltracer import _dlltracertest

    return events


def test_debug():
    events = run(do_test_debug)
    assert events
    for e in events:
        assert isinstance(e, dlltracer.DebugEvent)
        assert e.provider
        assert e.opcode
        assert e.header is not None
        assert e.data is not None
        assert repr(e)
        assert str(e)
