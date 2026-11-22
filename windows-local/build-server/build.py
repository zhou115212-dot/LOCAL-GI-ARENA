"""Build a private AstaPS runtime and a narrowly scoped class-only overlay.
No game files, login, startup or system configuration; see README before use.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile
from xml.etree import ElementTree as ET

BASE = "0fac870873a35e88b9f969aa1b242a832b602005"
GRADLE_SHA256 = "9d926787066a081739e8200858338b4a69e837c3a821a33aca9db09dd4a41026"
PATCH_SHA256 = "55270d2155699201d385e1c65d5a15e3b86cf0556473df9fe2281b917a9e32c0"
PATCH = Path(__file__).resolve().parents[1] / "server-patches/combat.patch"


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def run(*args, **kw):
    return subprocess.run([str(arg) for arg in args], check=True, **kw)


def require(ok, message):
    if not ok:
        raise ValueError(message)


def verified_gradle(archive, output):
    require(digest(archive) == GRADLE_SHA256, "Gradle ZIP checksum mismatch; nothing executed")
    with zipfile.ZipFile(archive) as z:
        # The official checksum identifies every byte including the entry table.
        z.extractall(output)
    jar = output / "gradle-8.5/lib/gradle-launcher-8.5.jar"
    require(jar.is_file(), "Verified Gradle distribution has unexpected layout")
    return jar


def normalized_patch(patch):
    raw = patch.read_bytes().replace(b"\r\n", b"\n")
    require(hashlib.sha256(raw).hexdigest() == PATCH_SHA256, "Unexpected patch bytes; review updated patch")
    return raw


def class_owners(patch):
    pattern = r"^\+\+\+ b/src/main/java/(emu/grasscutter/(?:[A-Za-z_0-9]+/)*[A-Za-z_0-9]+)\.java$"
    paths = set(re.findall(pattern, normalized_patch(patch).decode("utf-8"), flags=re.M))
    require(len(paths) == 33, "Unexpected patch scope; review the allowlist before packing")
    return paths


def overlay(private_jar, target, patch=PATCH):
    owners = class_owners(patch)
    file = target.open("xb")
    try:
        with file:
            with zipfile.ZipFile(private_jar) as inp, zipfile.ZipFile(file, "w") as out:
                names = [i.filename for i in inp.infolist() if i.filename.endswith(".class")
                         and i.filename[:-6].split("$")[0] in owners]
                require(len(set(names)) == len(names), "Duplicate overlay class")
                require(all(owner + ".class" in names for owner in owners), "Missing patched class")
                for name in sorted(names):
                    data = inp.read(name)
                    require(data[:4] == b"\xca\xfe\xba\xbe", "Not a Java class: " + name)
                    item = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                    out.writestr(item, data, compress_type=zipfile.ZIP_DEFLATED)
    except BaseException:
        target.unlink(missing_ok=True)  # Only our newly created, incomplete output.
        raise
    return len(names)


def report_tests(path):
    counts = dict(tests=0, failures=0, errors=0, skipped=0)
    for xml in path.glob("TEST-*.xml"):
        suite = ET.parse(xml).getroot()
        for key in counts:
            counts[key] += int(suite.get(key, "0"))
    require(counts["tests"] > counts["skipped"] and not counts["failures"] and not counts["errors"],
            f"No passing non-integration test suite: {counts}")
    return counts


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, required=True, help="Existing Git clone of upstream AstaPS")
    p.add_argument("--jdk", type=Path, required=True, help="JDK 21 home")
    p.add_argument("--gradle-zip", type=Path, required=True, help="Official Gradle 8.5 binary ZIP")
    p.add_argument("--work", type=Path, required=True, help="NEW private work directory")
    p.add_argument("--offline-modules", type=Path, help="Trusted Gradle 8.5 caches/modules-2 to copy; offline Gradle")
    a = p.parse_args()
    work = a.work.resolve()
    release_dir = Path(__file__).resolve().parents[2]
    require(work != release_dir and release_dir not in work.parents,
            "Keep private build outputs outside the public repository")
    source = a.source.resolve(strict=True)
    gradle = a.gradle_zip.resolve(strict=True)
    jdk = a.jdk.resolve(strict=True)
    require(not work.exists() and source not in work.parents,
            "--work must be a new directory outside the source repository")
    require(re.search(r'(?m)^JAVA_VERSION="21(?:[.+"-])', (jdk / "release").read_text(encoding="utf8")),
            "Expected JDK 21")
    java = jdk / "bin/java.exe"
    require(java.is_file() and (jdk / "bin/javac.exe").is_file(), "Expected Windows JDK, not a JRE")
    if a.offline_modules:
        modules = a.offline_modules.resolve(strict=True)
        require(work != modules and modules not in work.parents and (modules / "files-2.1").is_dir(),
                "--offline-modules must name trusted Gradle caches/modules-2 outside work")
    require(run("git", "-C", source, "rev-parse", "--verify", BASE+"^{commit}",
                capture_output=True, text=True).stdout.strip() == BASE, "Source revision absent")
    work.mkdir(parents=True)
    out = work / "src"
    temp = work / "temp"
    home = work / "home"
    temp.mkdir()
    home.mkdir()
    # Isolate Git config, clone hooks, Gradle init scripts and execution paths from the donor repo.
    env = os.environ.copy()
    env.update(JAVA_HOME=str(jdk), GRADLE_USER_HOME=str(work/"gradle-home"),
               TEMP=str(temp), TMP=str(temp), GIT_NO_REPLACE_OBJECTS="1",
               GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
    for key in ("JAVA_OPTS", "GRADLE_OPTS", "_JAVA_OPTIONS", "JDK_JAVA_OPTIONS", "JAVA_TOOL_OPTIONS"):
        env.pop(key, None)
    env["JAVA_TOOL_OPTIONS"] = (f'"-Djava.io.tmpdir={temp}" "-Duser.home={home}"')
    env["PATH"] = str(jdk / "bin") + os.pathsep + env.get("PATH", "")
    git = shutil.which("git")
    require(git is not None, "Install Git for Windows before building")
    empty_hooks = work / "empty-hooks"
    empty_hooks.mkdir()
    g = [git, "-c", "core.hooksPath=" + str(empty_hooks), "-c", "core.autocrlf=false"]
    run(*g, "clone", "--no-local", "--no-checkout", "--", source, out, env=env)
    run(*g, "-C", out, "checkout", "--detach", BASE, env=env)
    canonical_patch = work / "combat.patch"
    canonical_patch.write_bytes(normalized_patch(PATCH))
    run(*g, "-C", out, "apply", "--check", canonical_patch, env=env)
    run(*g, "-C", out, "apply", canonical_patch, env=env)
    launcher = verified_gradle(gradle, work / "tools")
    if a.offline_modules:
        dest = work / "gradle-home/caches/modules-2"
        shutil.copytree(modules, dest, ignore=shutil.ignore_patterns("*.lock", "*.lck"))
    args = ["--no-daemon", "--max-workers=1", "-PskipHandbook=1", "-PjarFilename=arena-server",
            "-PexcludeTags=integration"]
    if a.offline_modules:
        args.append("--offline")
    run(java, "-Xmx256m", "-cp", launcher, "org.gradle.launcher.GradleMain",
        *args, "jar", "test", cwd=out, env=env)
    private = out / "arena-server.jar"
    counts = report_tests(out / "build/test-results/test")
    public = work / "combat-classes.jar"
    n = overlay(private, public)
    result = {"base": BASE, "patch_sha256": PATCH_SHA256, "tests": counts,
              "private_runtime_sha256": digest(private), "overlay_classes": n,
              "overlay_sha256": digest(public)}
    (work / "build-result.json").write_text(json.dumps(result, indent=2)+"\n", encoding="utf8")
    print(json.dumps(result, indent=2))
    print("Private full server JAR:", private)
    print("Class-only overlay (NOT standalone):", public)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError, zipfile.BadZipFile) as exc:
        sys.exit(str(exc))
