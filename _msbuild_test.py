from pymsbuild import *
from pymsbuild.cython import *

METADATA = {
    "Name": "dlltracer",
    "Version": "0.0",
    "ExtSuffix": ".pyd",
}

PACKAGE = Package(
    "dlltracer",
    CythonPydFile(
        "_dlltracertest",
        PyxFile("dlltracer/_dlltracertest.pyx")
    ),        
    source="src",
)
