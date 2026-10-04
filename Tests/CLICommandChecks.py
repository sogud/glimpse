"""CLI command acceptance with an isolated workspace; never accesses Photos."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
binary = os.environ.get("GLIMPSE_TEST_BINARY")
if not binary:
    binary_directory = subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=root, text=True).strip()
    binary = str(Path(binary_directory) / "glimpse")
with tempfile.TemporaryDirectory(prefix="glimpse-cli-acceptance-") as temporary:
    directory = Path(temporary)
    environment = dict(os.environ, GLIMPSE_HOME=temporary)

    def run(*arguments, success=True):
        result = subprocess.run([binary, "photos", *arguments], env=environment, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert (result.returncode == 0) == success, result.stderr
        return result

    run("--help")
    oversized_plan = directory / "oversized.json"
    oversized_plan.write_bytes(b" " * (1024 * 1024 + 1))
    assert "计划文件超过" in run("apply", str(oversized_plan), success=False).stderr
    (directory / "state.json").write_text(json.dumps({
        "entries": {
            "fixture-success": {"outcome": "classified", "failures": 0},
            "fixture-failed": {"outcome": "failed", "failures": 3},
            "fixture-skipped": {"outcome": "skipped", "failures": 0},
        }, "isComplete": True,
    }))
    status = json.loads(run("status", "--json").stdout)
    assert status["progress"]["classified"] == 1 and status["progress"]["failed"] == 1
    receipt_directory = directory / "Receipts"
    receipt_directory.mkdir(mode=0o700)
    (receipt_directory / "fixture.json").write_text(json.dumps({
        "plan": {"id": "C0000000-0000-0000-0000-000000000001", "modelIdentifier": "test", "createdAt": 0,
                 "items": [{"assetIdentifier": "private-fixture-photo", "filename": "private-fixture-name.jpg",
                            "schemeKind": "ordinary", "categoryIdentifier": "ordinary:pets", "categoryName": "宠物",
                            "reason": "private-fixture-reason", "analysisSucceeded": True}]},
        "albums": [{"addition": {"folderName": "Glimpse", "albumName": "普通照片·宠物", "assetIdentifiers": ["private-fixture-photo"]},
                    "status": "confirmed", "result": {"albumIdentifier": "private-fixture-album", "addedAssetIdentifiers": ["private-fixture-photo"],
                                                      "existingAssetIdentifiers": [], "missingAssetIdentifiers": []}}],
    }))
    output = run("status", "--json").stdout
    assert "private-fixture" not in output, "routine status must not expose photo details"
    assert json.loads(output)["receipts"][0]["planID"] == "C0000000-0000-0000-0000-000000000001"
    assert json.loads(run("retry", "failed", "--json").stdout) == {"requeued": 1}
    status = json.loads(run("status", "--json").stdout)
    assert status["progress"]["classified"] == 1 and status["progress"]["skipped"] == 1
    assert status["progress"]["failed"] == 0 and not status["progress"]["scanComplete"]
    with (directory / "write.lock").open("w") as lease:
        fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = run("classify-next", "--endpoint", "http://127.0.0.1:9/v1", success=False)
        assert "另一个 Glimpse" in result.stderr
    run("retry", "skipped", "--json")
    run("retry", "classified", success=False)
    run("classify-next", "--limt", "1", success=False)
    result = run("classify-next", "--endpoint", "http://127.0.0.1:9/v1", success=False)
    assert "另一个 Glimpse" not in result.stderr
    assert not (directory / "Plans").exists() or not list((directory / "Plans").glob("*.json"))
print("CLI acceptance passed: status, retry, process lock, server failure without Photos export")
