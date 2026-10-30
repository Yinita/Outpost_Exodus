#!/usr/bin/env python3
"""Package clean committed source and native development builds, with hashes."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

PROJECT = Path(__file__).resolve().parents[1]


def git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(PROJECT), *args], text=True).strip()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=PROJECT.parent)
    options = parser.parse_args()
    if git("status", "--porcelain"):
        raise SystemExit("Commit the candidate first: packaging requires a clean source tree.")
    version_match = re.search(r'config/version="([^"]+)"', (PROJECT / "project.godot").read_text())
    if version_match is None:
        raise SystemExit("Missing project version")
    version = version_match.group(1)
    commit = git("rev-parse", "HEAD")
    smoke_path = PROJECT / "work" / "native-smoke" / "result.json"
    if not smoke_path.is_file():
        raise SystemExit("Run tools/smoke_native.py against this Linux native export before packaging.")
    smoke = json.loads(smoke_path.read_text())
    if smoke.get("success") is not True:
        raise SystemExit("The Linux native smoke test did not succeed.")
    for name in ("outpost-exodus.x86_64", "outpost-exodus.pck"):
        payload = PROJECT / "builds" / "linux-release" / name
        if not payload.is_file() or smoke.get("payload_sha256", {}).get(name) != sha256(payload):
            raise SystemExit("Linux native smoke evidence is stale; rerun tools/smoke_native.py.")
    output = options.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source_name = f"outpost-exodus-source-{version}.zip"
    artifacts: dict[str, dict] = {}
    source_files = subprocess.check_output(["git", "-C", str(PROJECT), "ls-files", "-z"]).split(b"\0")
    with zipfile.ZipFile(output / source_name, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for raw_path in source_files:
            if raw_path:
                relative = Path(raw_path.decode())
                bundle.write(PROJECT / relative, Path("outpost-exodus") / relative)
    artifacts[source_name] = {"sha256": sha256(output / source_name), "bytes": (output / source_name).stat().st_size}
    for platform, executable in (("linux", "outpost-exodus.x86_64"), ("windows", "outpost-exodus.exe")):
        directory = PROJECT / "builds" / f"{platform}-release"
        files = [directory / name for name in (executable, "outpost-exodus.pck", "FONT-NOTICE.txt", "GODOT-LICENSE.txt", "GODOT-COPYRIGHT.txt")]
        missing = [str(path) for path in files if not path.is_file()]
        if missing:
            raise SystemExit(f"Missing native export files: {missing}")
        provenance_path = directory / "export-source.json"
        if not provenance_path.is_file():
            raise SystemExit(f"Missing export provenance: {provenance_path}; rerun tools/export_release.sh")
        provenance = json.loads(provenance_path.read_text())
        if provenance.get("source_commit") != commit or provenance.get("source_tree") != git("rev-parse", "HEAD^{tree}"):
            raise SystemExit(f"Stale {platform} build: export the current committed source first.")
        for name in (executable, "outpost-exodus.pck"):
            if provenance.get("sha256", {}).get(name) != sha256(directory / name):
                raise SystemExit(f"Changed {platform} export payload: {name}")
        info = {
            "project": "逐营突围 / Outpost Exodus", "version": version,
            "source_commit": commit, "source_tree": git("rev-parse", "HEAD^{tree}"),
            "engine": "Godot 4.7.2.stable.official.ed1daf0bf",
            "platform": f"{platform} x86_64 official release template",
            "development_build": True, "steam_ready": False,
            "native_launch_verified_here": platform == "linux",
            "validation": "See source docs/validation-plan.md and docs/current-checkpoint.md for exact evidence and limits.",
            "sha256": {path.name: sha256(path) for path in files},
        }
        (directory / "build-info.json").write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n")
        launch = "解压整个文件夹后运行 outpost-exodus.exe。" if platform == "windows" else "解压整个文件夹后运行 ./outpost-exodus.x86_64；如需恢复权限，执行 chmod +x outpost-exodus.x86_64。"
        readme = f"""逐营突围 / Outpost Exodus {version}

{launch}
可执行文件与 outpost-exodus.pck 必须保留在同一目录，无需安装 Godot 编辑器。

开始：菜单选择“开始峡谷战役”，按左侧引导行动。
操作：左键选择/拖框，右键移动，X攻击移动；WASD/中键/滚轮控制镜头。
小地图左键定位，右键下令；B建设、V指挥、P生产、N训练。
Ctrl+1–4保存编队，1–4选择；Space战术暂停；F5手动保存、F9读取。
Esc菜单提供设置、帮助、自动存档和手动存档备份恢复。
后方追兵会迫使你撤营。先运走口粮、燃料与建材，给出口工程和当地发电预留资源。

这是内部开发版，当前只包含一场峡谷战役。代码提交：{commit}
Linux在开发机器启动和渲染验证；Windows仅完成导出和文件格式检查，尚未在Windows执行。
人工可玩性、最低配置、完整美术/音效与Steam发布验证仍在进行，详细状态见同版源码docs。
存档和设置写入系统用户数据目录，不写入安装目录。请保留随包字体和Godot版权通知。
"""
        (directory / "README.txt").write_text(readme)
        archive_name = f"outpost-exodus-{platform}-{version}.zip"
        with zipfile.ZipFile(output / archive_name, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
            for path in [*files, directory / "build-info.json", directory / "README.txt"]:
                bundle.write(path, Path(f"outpost-exodus-{platform}") / path.name)
        artifacts[archive_name] = {"sha256": sha256(output / archive_name), "bytes": (output / archive_name).stat().st_size}
    manifest = {"version": version, "source_commit": commit, "artifacts": artifacts}
    target = output / f"outpost-exodus-{version}-checksums.json"
    target.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
