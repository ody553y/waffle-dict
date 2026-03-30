#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey


def normalize_models_json(models: list[dict[str, Any]]) -> bytes:
    return json.dumps(models, sort_keys=True, separators=(",", ":")).encode("utf-8")


def load_models_from_manifest(manifest_path: Path) -> list[dict[str, Any]]:
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict) and isinstance(payload.get("models"), list):
        return payload["models"]
    raise ValueError("Manifest must be a model array or signed envelope with a models array.")


def load_private_key(private_key_path: Path) -> Ed25519PrivateKey:
    private_key_bytes = private_key_path.read_bytes()
    private_key = serialization.load_pem_private_key(private_key_bytes, password=None)
    if not isinstance(private_key, Ed25519PrivateKey):
        raise ValueError("Private key must be an Ed25519 key.")
    return private_key


def load_public_key(public_key_path: Path) -> Ed25519PublicKey:
    public_key_hex = public_key_path.read_text(encoding="utf-8").strip()
    public_key_bytes = bytes.fromhex(public_key_hex)
    return Ed25519PublicKey.from_public_bytes(public_key_bytes)


def command_generate_keys(output_dir: Path) -> int:
    output_dir.mkdir(parents=True, exist_ok=True)

    private_key = Ed25519PrivateKey.generate()
    public_key = private_key.public_key()

    private_key_path = output_dir / "manifest-signing-key.pem"
    public_key_path = output_dir / "manifest-signing-key.pub"

    private_key_path.write_bytes(
        private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
    )
    public_key_hex = public_key.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    ).hex()
    public_key_path.write_text(f"{public_key_hex}\n", encoding="utf-8")

    print(public_key_hex)
    return 0


def command_sign(manifest_path: Path, private_key_path: Path, output_path: Path) -> int:
    models = load_models_from_manifest(manifest_path)
    private_key = load_private_key(private_key_path)
    normalized_models = normalize_models_json(models)
    signature_hex = private_key.sign(normalized_models).hex()

    signed_payload = {
        "manifest_version": 2,
        "signed_at": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "signature": signature_hex,
        "models": models,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(signed_payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Signed manifest written to {output_path}")
    return 0


def command_verify(manifest_path: Path, public_key_path: Path) -> int:
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        print("Invalid signed manifest: root must be an object.")
        return 1

    try:
        models = payload["models"]
        signature_hex = payload["signature"]
    except KeyError as error:
        print(f"Invalid signed manifest: missing field {error}.")
        return 1

    if not isinstance(models, list) or not isinstance(signature_hex, str):
        print("Invalid signed manifest: expected models array and hex signature string.")
        return 1

    try:
        signature = bytes.fromhex(signature_hex)
        public_key = load_public_key(public_key_path)
        public_key.verify(signature, normalize_models_json(models))
    except Exception as error:  # noqa: BLE001 - CLI should normalize errors to a readable message.
        print(f"Signature invalid: {error}")
        return 1

    print("Signature valid.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Sign and verify Waffle model manifests.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    generate_parser = subparsers.add_parser("generate-keys", help="Generate a new Ed25519 key pair.")
    generate_parser.add_argument("--output", required=True, type=Path, help="Directory for generated key files.")

    sign_parser = subparsers.add_parser("sign", help="Sign a model manifest file.")
    sign_parser.add_argument("--manifest", required=True, type=Path, help="Path to source manifest JSON.")
    sign_parser.add_argument(
        "--private-key",
        required=True,
        type=Path,
        help="Path to Ed25519 private key PEM file.",
    )
    sign_parser.add_argument("--output", required=True, type=Path, help="Path for signed manifest output.")

    verify_parser = subparsers.add_parser("verify", help="Verify a signed model manifest file.")
    verify_parser.add_argument("--manifest", required=True, type=Path, help="Path to signed manifest JSON.")
    verify_parser.add_argument(
        "--public-key",
        required=True,
        type=Path,
        help="Path to Ed25519 public key file (hex-encoded raw bytes).",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        if args.command == "generate-keys":
            return command_generate_keys(args.output)
        if args.command == "sign":
            return command_sign(args.manifest, args.private_key, args.output)
        if args.command == "verify":
            return command_verify(args.manifest, args.public_key)
        parser.error(f"Unknown command: {args.command}")
        return 2
    except Exception as error:  # noqa: BLE001 - CLI should provide readable errors.
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
