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
        "Development Status :: 3 - Alpha",
        "Environment :: Win32 (MS Windows)",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: Microsoft :: Windows",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
    ],
    "Requires-Python": ">=3.7",
}

PACKAGE = CythonPydFile(
    "dlltracer",
    ItemDefinition("ClCompile",
        AdditionalIncludeDirectories=ConditionalValue(Path("src;").absolute(), prepend=True)
    ),
    PyxFile("dlltracer.pyx", TargetExt=".cpp"),
    source="src",
)
