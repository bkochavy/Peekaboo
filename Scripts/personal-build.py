#!/usr/bin/env python3
"""Build a personal distribution from a clean, recorded repository revision."""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def run(*args, cwd=ROOT):
    subprocess.run(args, cwd=cwd, check=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=["mac", "ios"])
    parser.add_argument("--build", required=True, type=int)
    parser.add_argument("--archive", action="store_true", help="Create a signed Release archive")
    parser.add_argument("--export", action="store_true", help="Export archive for App Store Connect")
    parser.add_argument("--profile", help="Installed App Store provisioning profile name for this platform")
    args = parser.parse_args()
    if args.build < 1 or (args.export and not args.archive):
        parser.error("Use a positive build number; --export requires --archive")
    if args.archive and not args.profile:
        parser.error("Signed archives require --profile with this platform's App Store profile")
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    config = json.loads(subprocess.check_output(
        ["git", "show", f"{revision}:PersonalBuild.json"], cwd=ROOT, text=True))
    output = ROOT / "PersonalBuilds" / f"{args.build}-{args.platform}-{revision[:12]}"
    output.mkdir(parents=True, exist_ok=False)
    source = output / "source"
    run("git", "clone", "--local", "--no-hardlinks", str(ROOT), str(source))
    run("git", "checkout", "--detach", revision, cwd=source)
    # Keep the upstream checkout untouched. All identity substitutions are in
    # this disposable source tree and apply to both platforms together.
    replacements = {
        "com.emanueledipietro.Peekaboo": config["bundle_id"],
        "HR24WHR326": config["team_id"],
    }
    for relative in subprocess.check_output(["git", "ls-files"], cwd=source, text=True).splitlines():
        path = source / relative
        if path.suffix not in {".swift", ".rb", ".plist", ".entitlements", ".md", ".pbxproj"}:
            continue
        text = path.read_text()
        for old, new in replacements.items():
            text = text.replace(old, new)
        path.write_text(text)
    run("bundle", "exec", "ruby", "Scripts/generate_project.rb", cwd=source)
    run("bundle", "exec", "ruby", "Scripts/verify_project_generation.rb", cwd=source)
    scheme = "Peekaboo" if args.platform == "mac" else "PeekabooMobile"
    destination = "generic/platform=macOS" if args.platform == "mac" else "generic/platform=iOS"
    command = ["xcodebuild", "-project", "Peekaboo.xcodeproj", "-scheme", scheme,
               "-configuration", "Release", "-destination", destination,
               "-derivedDataPath", str(output / "DerivedData"),
               f"CURRENT_PROJECT_VERSION={args.build}"]
    auth = []
    if args.archive:
        for variable in ("ASC_PRIVATE_KEY_PATH", "ASC_KEY_ID", "ASC_ISSUER_ID"):
            if not os.environ.get(variable):
                raise SystemExit(f"Set {variable} before signing")
        auth = ["-allowProvisioningUpdates", "-authenticationKeyPath", os.environ["ASC_PRIVATE_KEY_PATH"],
                "-authenticationKeyID", os.environ["ASC_KEY_ID"],
                "-authenticationKeyIssuerID", os.environ["ASC_ISSUER_ID"]]
        command += ["archive", "-archivePath", str(output / f"{scheme}.xcarchive"),
                    "CODE_SIGN_STYLE=Manual", "CODE_SIGN_IDENTITY=Apple Distribution",
                    f"PROVISIONING_PROFILE_SPECIFIER={args.profile}"] + auth
        if os.environ.get("PEEKABOO_SIGNING_KEYCHAIN"):
            command += [f"OTHER_CODE_SIGN_FLAGS=--keychain {os.environ['PEEKABOO_SIGNING_KEYCHAIN']}"]
    else:
        command += ["build", "CODE_SIGNING_ALLOWED=NO"]
    (output / "provenance.json").write_text(json.dumps({
        "revision": revision, "platform": args.platform, "build": args.build,
        "identity": config, "signed_archive_requested": args.archive,
    }, indent=2) + "\n")
    run(*command, cwd=source)
    if args.export:
        run("xcodebuild", "-exportArchive", "-archivePath", str(output / f"{scheme}.xcarchive"),
            "-exportOptionsPlist", str(source / "Scripts/ExportOptions-AppStore.plist"),
            "-exportPath", str(output / "export"), *auth, cwd=source)
    print(f"Build output: {output}")

if __name__ == "__main__":
    main()
