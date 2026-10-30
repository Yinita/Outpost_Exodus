#!/usr/bin/env python3
"""Replace Windows app resources on Linux, then independently verify the PE.

Setup: python3 -m venv work/pe-resources-venv
       work/pe-resources-venv/bin/pip install -r tools/build-requirements.txt
Dry run: work/pe-resources-venv/bin/python tools/patch_windows_resources.py \
  builds/windows-release/outpost-exodus.exe --output work/pe-resources-test.exe \
  --report work/pe-resources-test.json
Omit --output to atomically replace the input only after validation succeeds.

LIEF builds the resource tree; pefile independently parses the result. VERSION
serialization follows Microsoft's documented DWORD-aligned resource format.
No PE file offsets are patched, no code is changed, and no signature is added.
Sources:
https://lief.re/doc/stable/formats/pe/modifications/resources.html
https://learn.microsoft.com/en-us/windows/win32/menurc/vs-versioninfo
https://learn.microsoft.com/en-us/windows/win32/menurc/string-str
https://learn.microsoft.com/en-us/windows/win32/api/verrsrc/ns-verrsrc-vs_fixedfileinfo
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import sys
import tempfile

try:
    import lief
    import pefile
except ImportError as exc:
    raise SystemExit("Install tools/build-requirements.txt in a project virtual environment.") from exc

RT_ICON, RT_GROUP_ICON, RT_VERSION, RT_MANIFEST = 3, 14, 16, 24
LANGUAGE, CODEPAGE = 0x0409, 1200
CHANGED_TYPES = {RT_ICON, RT_GROUP_ICON, RT_VERSION}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else digest(stream.read())


def aliases(first: Path, second: Path) -> bool:
    return first == second or (first.exists() and second.exists() and first.samefile(second))


def read_icon(path: Path) -> list[dict]:
    data = path.read_bytes()
    require(len(data) >= 6, "ICO header is missing")
    reserved, kind, count = struct.unpack_from("<HHH", data)
    require((reserved, kind) == (0, 1) and count == 4, "Expected a four-layer ICO")
    require(len(data) >= 6 + count * 16, "ICO directory is truncated")
    layers = []
    for index in range(count):
        entry = data[6 + 16 * index:22 + 16 * index]
        width, height, colors, zero, planes, bits, size, offset = struct.unpack("<BBBBHHII", entry)
        require(offset >= 6 + count * 16 and offset + size <= len(data), "ICO payload is out of bounds")
        payload = data[offset:offset + size]
        dimension = width or 256
        require((height or 256) == dimension and zero == 0 and planes == 1 and bits == 32, "Unsupported ICO layer")
        require(payload.startswith(PNG_SIGNATURE) and payload[12:16] == b"IHDR", "Expected PNG-backed ICO layers")
        require(struct.unpack_from(">II", payload, 16) == (dimension, dimension), "ICO/PNG dimensions disagree")
        source_png = path.with_name(f"icon-{dimension}.png")
        require(source_png.is_file(), f"Missing original rendered PNG: {source_png}")
        require(source_png.read_bytes() == payload, f"ICO differs from original rendered PNG: {source_png}")
        layers.append({"dimension": dimension, "header": entry[:12], "payload": payload,
                       "png_source": str(source_png.resolve()), "sha256": digest(payload)})
    require(sorted(layer["dimension"] for layer in layers) == [32, 64, 128, 256], "Expected 32/64/128/256px layers")
    return layers


def align4(data: bytes) -> bytes:
    return data + b"\0" * (-len(data) % 4)


def version_block(key: str, value: bytes = b"", children: tuple[bytes, ...] = (), text: bool = True) -> bytes:
    value_length = len(value) // 2 if text else len(value)
    body = align4(b"\0" * 6 + (key + "\0").encode("utf-16le")) + value
    for child in children:
        body = align4(body) + child
    require(len(body) <= 65535, "Version resource block is too long")
    return struct.pack("<HHH", len(body), value_length, int(text)) + body[6:]


def numeric_version(value: str) -> tuple[int, int]:
    require(re.fullmatch(r"\d+\.\d+\.\d+\.\d+", value) is not None, "File version must contain four integers")
    parts = [int(part) for part in value.split(".")]
    require(all(0 <= part <= 65535 for part in parts), "Version components must fit in 16 bits")
    return parts[0] << 16 | parts[1], parts[2] << 16 | parts[3]


def make_version(strings: dict[str, str], fixed_version: tuple[int, int]) -> bytes:
    ms, ls = fixed_version
    prerelease = int("-" in strings["ProductVersion"]) * 2
    fixed = struct.pack("<13I", 0xFEEF04BD, 0x10000, ms, ls, ms, ls,
                        0x3F, prerelease, 4, 1, 0, 0, 0)
    entries = tuple(version_block(key, (value + "\0").encode("utf-16le")) for key, value in strings.items())
    table = version_block(f"{LANGUAGE:04x}{CODEPAGE:04x}", children=entries)
    string_info = version_block("StringFileInfo", children=(table,))
    translation = version_block("Translation", struct.pack("<HH", LANGUAGE, CODEPAGE), text=False)
    var_info = version_block("VarFileInfo", children=(translation,))
    return version_block("VS_VERSION_INFO", fixed, (string_info, var_info), text=False)


def add_resource(root, resource_type: int, resource_id: int, payload: bytes) -> None:
    type_node = next((node for node in root.childs if node.id == resource_type), None)
    if type_node is None:
        type_node = root.add_child(lief.PE.ResourceDirectory(resource_type))
    name_node = type_node.add_child(lief.PE.ResourceDirectory(resource_id))
    leaf = lief.PE.ResourceData(list(payload), CODEPAGE if resource_type == RT_VERSION else 0)
    leaf.id = LANGUAGE
    name_node.add_child(leaf)


def resource_leaves(pe) -> dict[tuple, bytes]:
    leaves = {}

    def walk(directory, path=()):
        for entry in directory.entries:
            key = str(entry.name) if entry.name is not None else entry.id
            current = path + (key,)
            if hasattr(entry, "directory"):
                walk(entry.directory, current)
            else:
                item = entry.data.struct
                leaves[current] = pe.get_data(item.OffsetToData, item.Size)

    if hasattr(pe, "DIRECTORY_ENTRY_RESOURCE"):
        walk(pe.DIRECTORY_ENTRY_RESOURCE)
    return leaves


def pe_snapshot(path: Path) -> tuple[dict, dict[tuple, bytes], object]:
    pe = pefile.PE(str(path), fast_load=True)
    pe.parse_data_directories(directories=[1, 2, 13])
    leaves = resource_leaves(pe)
    text = [section for section in pe.sections if section.Name.rstrip(b"\0") == b".text"]
    require(len(text) == 1, "Expected one .text code section")
    imports = []
    for directory_name in ("DIRECTORY_ENTRY_IMPORT", "DIRECTORY_ENTRY_DELAY_IMPORT"):
        for library in getattr(pe, directory_name, []):
            imports.append([directory_name, library.dll.decode("ascii"), [
                [symbol.name.decode("ascii") if symbol.name else None, symbol.ordinal, symbol.address]
                for symbol in library.imports]])
    security = pe.OPTIONAL_HEADER.DATA_DIRECTORY[4]
    require(security.Size == 0 and security.VirtualAddress == 0, "Signed input is unsupported; patch before signing")
    immutable = {str(key): digest(value) for key, value in leaves.items() if key[0] not in CHANGED_TYPES}
    snapshot = {
        "machine": pe.FILE_HEADER.Machine,
        "entrypoint_rva": pe.OPTIONAL_HEADER.AddressOfEntryPoint,
        "subsystem": pe.OPTIONAL_HEADER.Subsystem,
        "image_base": pe.OPTIONAL_HEADER.ImageBase,
        "dll_characteristics": pe.OPTIONAL_HEADER.DllCharacteristics,
        "text_sha256": digest(text[0].get_data()),
        "text_virtual_address": text[0].VirtualAddress,
        "text_virtual_size": text[0].Misc_VirtualSize,
        "non_resource_sections": [
            {"name": section.Name.rstrip(b"\0").decode("ascii"),
             "rva": section.VirtualAddress, "virtual_size": section.Misc_VirtualSize,
             "raw_size": section.SizeOfRawData, "characteristics": section.Characteristics,
             "sha256": digest(section.get_data())}
            for section in pe.sections if section.Name.rstrip(b"\0") != b".rsrc"],
        "imports": imports,
        "other_resource_sha256": immutable,
        "other_data_directories": [[item.VirtualAddress, item.Size] for index, item in enumerate(pe.OPTIONAL_HEADER.DATA_DIRECTORY) if index != 2],
        "overlay_sha256": digest(pe.get_overlay() or b""),
        "signed": False,
    }
    return snapshot, leaves, pe


def verify_result(path: Path, baseline: dict, layers: list[dict], strings: dict, fixed_version: tuple[int, int]) -> dict:
    actual, leaves, pe = pe_snapshot(path)
    try:
        require(actual == baseline, "PE invariants changed: " + ", ".join(key for key in baseline if baseline[key] != actual[key]))
        icons = {key[1]: value for key, value in leaves.items() if key[0] == RT_ICON}
        require(len(icons) == len(layers), "Unexpected embedded icon count")
        icon_report = []
        for index, layer in enumerate(layers, 1):
            require(icons.get(index) == layer["payload"], f"Embedded icon {index} differs from source PNG")
            icon_report.append({key: layer[key] for key in ("dimension", "png_source", "sha256")})
        groups = [value for key, value in leaves.items() if key[0] == RT_GROUP_ICON]
        require(len(groups) == 1, "Expected one application icon group")
        expected_group = struct.pack("<HHH", 0, 1, len(layers)) + b"".join(
            layer["header"] + struct.pack("<H", index) for index, layer in enumerate(layers, 1))
        require(groups[0] == expected_group, "Icon group does not reference the expected layers")
        tables = [table for block in getattr(pe, "FileInfo", []) for item in block
                  if getattr(item, "Key", None) == b"StringFileInfo" for table in item.StringTable]
        require(len(tables) == 1, "Expected one version string table")
        decoded = {key.decode("utf-8"): value.decode("utf-8") for key, value in tables[0].entries.items()}
        require(decoded == strings, "Version text differs from requested metadata")
        versions = getattr(pe, "VS_FIXEDFILEINFO", [])
        require(len(versions) == 1, "Expected one fixed version structure")
        fixed = versions[0]
        require((fixed.FileVersionMS, fixed.FileVersionLS) == fixed_version, "Numeric file version differs")
        require((fixed.ProductVersionMS, fixed.ProductVersionLS) == fixed_version, "Numeric product version differs")
        require(fixed.FileFlags == int("-" in strings["ProductVersion"]) * 2, "Prerelease flag differs")
        manifests = [digest(value) for key, value in leaves.items() if key[0] == RT_MANIFEST]
        require(bool(manifests), "Application manifest is missing")
        return {"verified": True, "icons": icon_report, "version_strings": decoded,
                "file_version_numeric": strings["FileVersion"], "product_version_numeric": strings["FileVersion"],
                "manifest_sha256": manifests, "text_sha256": actual["text_sha256"],
                "entrypoint_rva": actual["entrypoint_rva"], "subsystem": actual["subsystem"],
                "non_resource_sections": actual["non_resource_sections"],
                "import_libraries": len(actual["imports"]), "imports_sha256": digest(json.dumps(actual["imports"]).encode()),
                "preserved": ["all non-resource section bytes, addresses and flags", ".text bytes and address", "entrypoint", "subsystem", "image base", "DLL characteristics", "imports and delay imports", "manifest and other resources", "non-resource data directories", "overlay"],
                "authenticode_signed": False, "native_windows_execution_tested": False}
    finally:
        pe.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("exe", type=Path)
    parser.add_argument("--output", type=Path, help="Write a verified copy; default: atomically replace input")
    parser.add_argument("--icon", type=Path, default=Path(__file__).resolve().parents[1] / "assets/identity/icon.ico")
    parser.add_argument("--product-name", default="Outpost Exodus")
    parser.add_argument("--file-description", default="Outpost Exodus")
    parser.add_argument("--file-version", default="0.3.0.0")
    parser.add_argument("--product-version", default="0.3.0-dev")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    require(lief.__version__.split("-")[0] == "0.17.6", "Use pinned LIEF 0.17.6 from tools/build-requirements.txt")
    require(pefile.__version__ == "2024.8.26", "Use pinned pefile 2024.8.26 from tools/build-requirements.txt")
    source = args.exe.resolve(strict=True)
    destination = (args.output or source).resolve()
    icon = args.icon.resolve(strict=True)
    layers = read_icon(icon)
    artwork_sources = [icon] + [Path(layer["png_source"]) for layer in layers]
    require(not any(aliases(destination, path) for path in artwork_sources), "Output must not replace original icon artwork")
    if args.report:
        report_path = args.report.resolve()
        require(not any(aliases(report_path, path) for path in [source, destination] + artwork_sources),
                "Report must not overwrite the executable or original icon artwork")
    destination.parent.mkdir(parents=True, exist_ok=True)
    fixed_version = numeric_version(args.file_version)
    strings = {"FileDescription": args.file_description, "FileVersion": args.file_version,
               "ProductName": args.product_name, "ProductVersion": args.product_version}
    require(all(value and "\0" not in value for value in strings.values()), "Metadata must be nonempty without NUL characters")
    before_hash = file_digest(source)
    baseline, _, original = pe_snapshot(source)
    original.close()
    pe = lief.PE.parse(str(source))
    require(pe is not None and pe.has_resources, "Input must be a PE executable with resources")
    root = pe.resources
    for node in list(root.childs):
        if node.id in CHANGED_TYPES:
            root.delete_child(node.id)
    for index, layer in enumerate(layers, 1):
        add_resource(root, RT_ICON, index, layer["payload"])
    group = struct.pack("<HHH", 0, 1, len(layers)) + b"".join(
        layer["header"] + struct.pack("<H", index) for index, layer in enumerate(layers, 1))
    add_resource(root, RT_GROUP_ICON, 1, group)
    add_resource(root, RT_VERSION, 1, make_version(strings, fixed_version))
    config = lief.PE.Builder.config_t()
    config.resources = True
    for flag in ("imports", "exports", "relocations", "tls", "load_configuration", "debug"):
        setattr(config, flag, False)
    config.overlay = True
    descriptor, temporary = tempfile.mkstemp(prefix=destination.name + ".", suffix=".tmp", dir=destination.parent)
    os.close(descriptor)
    temporary_path = Path(temporary)
    try:
        pe.write(str(temporary_path), config)
        require(temporary_path.stat().st_size > 0, "LIEF produced an empty executable")
        report = verify_result(temporary_path, baseline, layers, strings, fixed_version)
        require(file_digest(source) == before_hash, "Source changed during resource patch; refusing replacement")
        report.update({"input": str(source), "output": str(destination), "input_sha256": before_hash,
                       "output_sha256": file_digest(temporary_path), "lief": lief.__version__, "pefile": pefile.__version__})
        os.chmod(temporary_path, stat.S_IMODE(source.stat().st_mode))
        os.replace(temporary_path, destination)
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 0
    finally:
        temporary_path.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, pefile.PEFormatError) as exc:
        print(f"Windows resource patch failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
