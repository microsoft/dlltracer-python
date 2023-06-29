import os
from pathlib import Path
from pymsbuild import *
from pymsbuild.cython import *

VERSION = os.getenv("BUILD_BUILDNUMBER", "0.0.1")

GHREF = os.getenv("GITHUB_REF")
if GHREF:
    VERSION = GHREF.rpartition("/")[2]

METADATA = {
    "Metadata-Version": "2.1",
    "Name": "dlltracer",
    "Version": VERSION,
    "Author": "Microsoft Corporation",
    "Author-email": "python@microsoft.com",
    "Home-page": "https://github.com/microsoft/dlltracer-python",
    "Project-url": [
        "Bug Tracker, https://github.com/microsoft/dlltracer-python/issues",
    ],
    "Summary": "Python module for tracing Windows DLL loads",
    "Description": File("README.md"),
    "Description-Content-Type": "text/markdown",
    "Keywords": "Windows,Win32,DLL",
    "Classifier": [
        "Development Status :: 5 - Production/Stable",
        "Environment :: Win32 (MS Windows)",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: Microsoft :: Windows",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
    ],
    "Requires-Python": ">=3.7",
}

AUDIT_STUB = CSourceFile("dlltracer/audit_stub.c")

PYD = CythonPydFile(
    "_native",
    ItemDefinition("ClCompile",
        AdditionalIncludeDirectories=ConditionalValue(Path("src;").absolute(), prepend=True)
    ),
    ItemDefinition("Link",
        GenerateDebugInformation=ConditionalValue("false", condition="$(Configuration) == 'Release'")),
    PyxFile("dlltracer/_native.pyx", TargetExt=".cpp"),
    IncludeFile("dlltracer/audit_stub.h"),
    AUDIT_STUB,
)

PACKAGE = Package(
    "dlltracer",
    PyFile("dlltracer/__init__.py"),
    PYD,
    source="src",
)

def init_PACKAGE(wheel_tag):
    if wheel_tag and not wheel_tag.startswith("cp37"):
        PYD.members.remove(AUDIT_STUB)
