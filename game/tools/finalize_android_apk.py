"""Finalize a native Godot Android APK with the project's release key."""
from __future__ import annotations

import argparse
from copy import copy
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import zipfile


MANIFEST = "AndroidManifest.xml"
ADAPTIVE_ICON = "res/mipmap-anydpi-v26/icon.xml"
THEMED_ALIAS = "res/mipmap-anydpi-v26/themed_icon.xml"
ANDROID = "http://schemas.android.com/apk/res/android"
VULKAN_FEATURES = {"android.hardware.vulkan.level", "android.hardware.vulkan.version"}
OLD_SIGNATURE = re.compile(r"META-INF/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC)|SIG-[^/]+)", re.I)
KEY_PREFIX = "GODOT_ANDROID_KEYSTORE_RELEASE_"


def chunks(data: bytes, start: int, end: int):
    while start < end:
        kind, header, size = struct.unpack_from("<HHI", data, start)
        if not 8 <= header <= size <= end - start:
            raise ValueError("Malformed Android binary XML chunk")
        yield kind, start, header, size
        start += size


def string_at(data: bytes, pool: tuple[int, int, int], index: int) -> str:
    start, header, size = pool
    count, _, flags, strings, _ = struct.unpack_from("<5I", data, start + 8)
    if index >= count or header + index * 4 + 4 > size:
        raise ValueError("Invalid Android binary XML string index")
    relative, = struct.unpack_from("<I", data, start + header + index * 4)
    pos = start + strings + relative
    if not start <= pos < start + size:
        raise ValueError("Invalid Android binary XML string offset")
    if flags & 0x100:  # UTF-8 stores the UTF-16 length, then the byte length.
        pos += 2 if data[pos] & 0x80 else 1
        length = data[pos]
        pos += 1
        if length & 0x80:
            length = ((length & 0x7F) << 8) | data[pos]
            pos += 1
        encoding = "utf-8"
    else:
        length, = struct.unpack_from("<H", data, pos)
        pos += 2
        if length & 0x8000:
            low, = struct.unpack_from("<H", data, pos)
            length = ((length & 0x7FFF) << 16) | low
            pos += 2
        length *= 2
        encoding = "utf-16-le"
    if pos + length > start + size:
        raise ValueError("Truncated Android binary XML string")
    return data[pos:pos + length].decode(encoding)


def fix_manifest(data: bytes) -> bytes:
    """Restore the binary types of the Vulkan flags and versions."""
    kind, header, size = struct.unpack_from("<HHI", data)
    if kind != 0x0003 or not 8 <= header <= size == len(data):
        raise ValueError("Expected a compiled Android manifest")
    output = bytearray(data)
    pool = None
    for kind, offset, header, size in chunks(data, header, size):
        if kind == 0x0001:
            pool = (offset, header, size)
        if kind != 0x0102:  # Start element
            continue
        if pool is None:
            raise ValueError("Android binary XML has no string pool")
        extension = offset + header
        _, name, first, stride, count = struct.unpack_from("<IIHHH", data, extension)
        if string_at(data, pool, name) != "uses-feature":
            continue
        if first < 20 or stride < 20 or extension + first + stride * count > offset + size:
            raise ValueError("Malformed Android feature attributes")
        attributes = {}
        for attr in range(extension + first, extension + first + stride * count, stride):
            namespace, tag, _, _, _, datatype, value = struct.unpack_from("<IIIHBBI", data, attr)
            if namespace != 0xFFFFFFFF and string_at(data, pool, namespace) == ANDROID:
                attributes[string_at(data, pool, tag)] = attr, datatype, value
        _, name_type, feature_value = attributes.get("name", (0, 0, 0))
        if name_type != 0x03 or string_at(data, pool, feature_value) not in VULKAN_FEATURES:
            continue
        attr, datatype, value = attributes.get("required", (0, 0, 0))
        if datatype == 0x03:  # Res_value.TYPE_STRING
            flag = string_at(data, pool, value)
            if flag not in {"true", "false"}:
                raise ValueError(f"Unexpected Vulkan required flag {flag!r}")
            struct.pack_into("<IHBBI", output, attr + 8, 0xFFFFFFFF, 8, 0, 0x12,
                             0xFFFFFFFF if flag == "true" else 0)
        attr, datatype, value = attributes.get("version", (0, 0, 0))
        if datatype == 0x03:
            version = string_at(data, pool, value)
            number = int(version, 0)
            if not 0 <= number <= 0xFFFFFFFF:
                raise ValueError("Vulkan feature version is out of range")
            number_type = 0x11 if version.lower().startswith("0x") else 0x10
            struct.pack_into("<IHBBI", output, attr + 8, 0xFFFFFFFF, 8, 0, number_type, number)
    return bytes(output)


def normalize_apk(source: Path, destination: Path) -> None:
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(destination, "w") as normalized:
        manifest = fix_manifest(original.read(MANIFEST))
        for entry in original.infolist():
            if OLD_SIGNATURE.fullmatch(entry.filename):
                continue
            if entry.filename == MANIFEST:
                normalized.writestr(copy(entry), manifest)
            else:
                with original.open(entry) as reader, normalized.open(copy(entry), "w") as writer:
                    shutil.copyfileobj(reader, writer)
        if THEMED_ALIAS not in original.namelist() and ADAPTIVE_ICON in original.namelist():
            normalized.writestr(THEMED_ALIAS, original.read(ADAPTIVE_ICON))


def finalize(source: Path, destination: Path, tools: Path) -> None:
    key_path, key_alias, password = (os.environ.get(KEY_PREFIX + part)
                                     for part in ("PATH", "USER", "PASSWORD"))
    if not (key_path and key_alias and password):
        raise ValueError(f"Provide {KEY_PREFIX}PATH, USER and PASSWORD via the environment")
    executable = ".exe" if os.name == "nt" else ""
    zipalign = tools / f"zipalign{executable}"
    aapt = tools / f"aapt{executable}"
    aapt2 = tools / f"aapt2{executable}"
    java_home = os.environ.get("JAVA_HOME")
    java = str(Path(java_home) / "bin" / f"java{executable}") if java_home else "java"
    signer = [java, "-jar", str(tools / "lib/apksigner.jar")]
    if destination.exists():
        raise ValueError("Choose an output path that does not already exist")
    with tempfile.TemporaryDirectory(prefix="beastpact-apk-", dir=destination.parent) as folder:
        raw, aligned = (Path(folder) / name for name in ("raw.apk", "aligned.apk"))
        normalize_apk(source, raw)
        subprocess.run([zipalign, "-P", "16", "-f", "4", raw, aligned], check=True)
        subprocess.run([*signer, "sign", "--ks", key_path, "--ks-key-alias", key_alias,
                        "--ks-pass", "env:" + KEY_PREFIX + "PASSWORD", "--v4-signing-enabled", "false",
                        aligned], check=True)
        subprocess.run([*signer, "verify", "--verbose", aligned], check=True)
        subprocess.run([zipalign, "-c", "-P", "16", "4", aligned], check=True)
        subprocess.run([aapt, "dump", "badging", aligned], stdout=subprocess.DEVNULL, check=True)
        result = subprocess.run([aapt2, "dump", "badging", aligned], capture_output=True, check=True)
        if b"package: name='com.beastpact.game'" not in result.stdout or b"themed_icon.xml" in result.stderr:
            raise ValueError("Beastpact package identity or themed icon could not be verified")
        aligned.rename(destination)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--build-tools", type=Path, required=True)
    options = parser.parse_args()
    try:
        finalize(options.source.resolve(), options.destination.resolve(), options.build_tools.resolve())
    except (OSError, ValueError, struct.error, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        # CalledProcessError exposes the command, but the key password stays in the environment.
        parser.exit(1, f"Android APK finalization failed: {error}\n")


if __name__ == "__main__":
    main()
