import json
import subprocess
import tempfile
import unittest
from pathlib import Path


class SignManifestToolTests(unittest.TestCase):
    def test_generate_keys_sign_and_verify_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            manifest_path = temp_path / "manifest.json"
            signed_manifest_path = temp_path / "signed-manifest.json"

            manifest_path.write_text(
                json.dumps(
                    [
                        {
                            "id": "whisper-small",
                            "family": "whisper",
                            "display_name": "Whisper Small",
                            "size_mb": 488,
                            "languages": ["multilingual"],
                            "supports_live": False,
                            "supports_translation": True,
                            "download_url": "https://models.waffle.app/v1/models/whisper-small.tar.gz",
                            "sha256_checksum": "abc123",
                            "available": True,
                        }
                    ]
                ),
                encoding="utf-8",
            )

            generate = self._run_tool("generate-keys", "--output", str(temp_path))
            self.assertEqual(generate.returncode, 0, generate.stderr)
            self.assertTrue((temp_path / "manifest-signing-key.pem").exists())
            self.assertTrue((temp_path / "manifest-signing-key.pub").exists())
            self.assertRegex(generate.stdout.strip(), r"^[0-9a-f]{64}$")

            sign = self._run_tool(
                "sign",
                "--manifest",
                str(manifest_path),
                "--private-key",
                str(temp_path / "manifest-signing-key.pem"),
                "--output",
                str(signed_manifest_path),
            )
            self.assertEqual(sign.returncode, 0, sign.stderr)
            self.assertTrue(signed_manifest_path.exists())

            verify = self._run_tool(
                "verify",
                "--manifest",
                str(signed_manifest_path),
                "--public-key",
                str(temp_path / "manifest-signing-key.pub"),
            )
            self.assertEqual(verify.returncode, 0, verify.stderr)
            self.assertIn("valid", verify.stdout.lower())

    def test_verify_fails_for_tampered_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            manifest_path = temp_path / "manifest.json"
            signed_manifest_path = temp_path / "signed-manifest.json"

            manifest_path.write_text(
                json.dumps(
                    [
                        {
                            "id": "whisper-small",
                            "family": "whisper",
                            "display_name": "Whisper Small",
                            "size_mb": 488,
                            "languages": ["multilingual"],
                            "supports_live": False,
                            "supports_translation": True,
                            "download_url": "https://models.waffle.app/v1/models/whisper-small.tar.gz",
                            "sha256_checksum": "abc123",
                            "available": True,
                        }
                    ]
                ),
                encoding="utf-8",
            )

            generate = self._run_tool("generate-keys", "--output", str(temp_path))
            self.assertEqual(generate.returncode, 0, generate.stderr)

            sign = self._run_tool(
                "sign",
                "--manifest",
                str(manifest_path),
                "--private-key",
                str(temp_path / "manifest-signing-key.pem"),
                "--output",
                str(signed_manifest_path),
            )
            self.assertEqual(sign.returncode, 0, sign.stderr)

            signed_payload = json.loads(signed_manifest_path.read_text(encoding="utf-8"))
            signed_payload["models"][0]["size_mb"] = 999
            signed_manifest_path.write_text(
                json.dumps(signed_payload),
                encoding="utf-8",
            )

            verify = self._run_tool(
                "verify",
                "--manifest",
                str(signed_manifest_path),
                "--public-key",
                str(temp_path / "manifest-signing-key.pub"),
            )
            self.assertEqual(verify.returncode, 1)
            self.assertIn("invalid", verify.stdout.lower() + verify.stderr.lower())

    def _run_tool(self, *args: str) -> subprocess.CompletedProcess[str]:
        repo_root = Path(__file__).resolve().parents[2]
        tool_path = repo_root / "tools" / "sign-manifest.py"
        return subprocess.run(
            ["python3", str(tool_path), *args],
            cwd=repo_root,
            text=True,
            capture_output=True,
            check=False,
        )


if __name__ == "__main__":
    unittest.main()
