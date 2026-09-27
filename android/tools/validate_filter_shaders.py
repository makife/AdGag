"""Compile-checks the native editor's effect shaders (VideoFilters.kt) on a dev machine.

GLSL errors in those shaders otherwise only surface on a phone, at runtime.
The NDK's glslc can't take GLSL ES 1.00 (it targets SPIR-V, ES 3.10+), so
each shader is mechanically translated to ES 3.10 first — the type/overload
rules that catch real mistakes (int vs float literals, wrong vector sizes,
missing overloads) are the same.

Usage (from the repo root):  python android/tools/validate_filter_shaders.py
Exit code 0 = all shaders compiled.
"""

import glob
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = os.path.join(ROOT, "android", "app", "src", "main", "kotlin", "com", "adgag", "adgag", "editor", "VideoFilters.kt")


def find_glslc() -> str:
    sdk = os.environ.get("ANDROID_HOME") or os.path.join(os.environ.get("LOCALAPPDATA", ""), "Android", "Sdk")
    hits = sorted(glob.glob(os.path.join(sdk, "ndk", "*", "shader-tools", "*", "glslc*")))
    if not hits:
        sys.exit("glslc not found — install an Android NDK (it ships shader-tools/glslc).")
    return hits[-1]


def to_es310(src: str) -> str:
    src = src.replace("varying vec2 vUv;", "layout(location=0) in vec2 vUv;\nlayout(location=0) out vec4 fragColor;")
    src = src.replace("gl_FragColor", "fragColor").replace("texture2D(", "texture(")
    return "#version 310 es\n" + src


def main() -> int:
    kt = open(SOURCE, encoding="utf-8").read()
    header = re.search(r'FilterShaderHeader = """(.*?)"""', kt, re.S).group(1)
    bodies = re.findall(r'\n    (\w+)\("[^"]*", """(.*?)"""\)', kt, re.S)
    glslc = find_glslc()
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        for name, body in bodies:
            path = os.path.join(tmp, name + ".frag")
            open(path, "w").write(to_es310(header + "void main() {\n" + body + "\n}\n"))
            result = subprocess.run(
                [glslc, "--target-env=opengl", "-fauto-bind-uniforms", "-fauto-map-locations", "-c", path, "-o", os.devnull],
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                failed += 1
                print(f"FAIL {name}\n{result.stderr}")
    print(f"{len(bodies) - failed}/{len(bodies)} shaders OK")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
