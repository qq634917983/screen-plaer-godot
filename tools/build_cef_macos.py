"""Build pinned upstream gdcef, preserving macOS framework symlinks."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "doc/gdcef"
REVISION = "f4d0c72e514a5636dfe17884e31581d5a5b289c4"


def run(*args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


def main():
    if sys.platform != "darwin":
        raise SystemExit("macOS is required")
    cpp = Path(sys.argv[1]).resolve()
    if not (SOURCE / ".git").exists():
        run("git", "clone", "https://github.com/Lecrapouille/gdcef.git", str(SOURCE))
        run("git", "-C", str(SOURCE), "checkout", REVISION)
    actual = subprocess.check_output(["git", "-C", str(SOURCE), "rev-parse", "HEAD"], text=True).strip()
    if actual != REVISION:
        raise SystemExit("Unexpected gdcef revision; use the pinned revision " + REVISION)
    (SOURCE / ".gdignore").touch()
    browser = SOURCE / "gdcef/browser"
    shutil.copy2(ROOT / "native/cef_application_mac.mm", browser / "src/cef_application_mac.mm")
    # Keep the upstream checkout pinned; apply the narrow macOS integration fix.
    sconstruct = browser / "SConstruct"
    text = sconstruct.read_text()
    if 'sources += Glob("src/*.mm")' not in text:
        text = text.replace("sources = Glob('src/*.cpp')", "sources = Glob('src/*.cpp')\nif platform == 'macos':\n    sources += Glob(\"src/*.mm\")\n    env.Append(LINKFLAGS=['-framework', 'AppKit'])")
        sconstruct.write_text(text)
    registration = browser / "src/register_types.cpp"
    text = registration.read_text()
    if "screenplayer_install_cef_application" not in text:
        text = text.replace("bool loaded = false;", "bool loaded = false;\nvoid screenplayer_install_cef_application();\nvoid screenplayer_uninstall_cef_application();")
        text = text.replace("    loaded = true;", "    loaded = true;\n    screenplayer_install_cef_application();")
        text = text.replace("        cef_unload_library();", "        cef_unload_library();\n        screenplayer_uninstall_cef_application();")
        registration.write_text(text)
    implementation = browser / "src/gdcef.cpp"
    text = implementation.read_text()
    if "cef_settings.external_message_pump = true;" not in text:
        text = text.replace("    cef_settings.multi_threaded_message_loop = 0;",
                            "    cef_settings.multi_threaded_message_loop = 0;\n#ifdef __APPLE__\n    cef_settings.external_message_pump = true;\n#endif")
        implementation.write_text(text)
    spec = importlib.util.spec_from_file_location("gdcef_build", SOURCE / "build.py")
    build = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(build)
    build.GODOT_CPP_API_PATH = str(cpp)
    build.SCONS = "scons"
    # System curl uses macOS trust settings; keep TLS validation and upstream SHA1.
    build.download = lambda url, dest: run("/usr/bin/curl", "--fail", "--location", "--retry", "3", "--output", dest, url)
    build.check_build_chain()
    profile = cpp.parent / "cef-profile.json"
    profile.write_text(json.dumps({"enabled_classes": [
        "Node", "OS", "TextureRect", "ImageTexture", "Image", "ProjectSettings",
        "DisplayServer", "Input", "JSON", "GDScript", "AudioStreamGeneratorPlayback"
    ]}))
    os.chdir(cpp)
    build.scons("platform=macos", "arch=" + build.ARCHI, "target=template_release",
                "use_static_cpp=no", "build_profile=" + str(profile))
    build.download_cef()
    # CEF's post-build `ln -sf` is not safe to repeat against an existing bundle.
    app = Path(build.THIRDPARTY_CEF_PATH) / "build/tests/cefsimple/Release/cefsimple.app"
    if app.exists():
        shutil.rmtree(app)
    build.compile_cef()
    artifacts = Path(build.CEF_ARTIFACTS_OS_PATH)
    artifacts.mkdir(parents=True, exist_ok=True)
    bundle = artifacts / build.MACOS_SUBPROCESS_APP
    if bundle.exists():
        shutil.rmtree(bundle)
    shutil.copytree(app, bundle, symlinks=True)
    framework = bundle / "Contents/Frameworks/Chromium Embedded Framework.framework"
    shutil.rmtree(framework)
    shutil.copytree(Path(build.THIRDPARTY_CEF_PATH) / "Release/Chromium Embedded Framework.framework",
                    framework, symlinks=True)
    build.create_version_file()
    build.compile_gdnative_cef(build.GDCEF_PATH)
    build.compile_gdnative_cef(build.GDCEF_PROCESSES_PATH)
    build.install_gdcef_render_process_macos()
    build.create_gdextension_file()
    # Replacing Helper executables invalidates their original ad-hoc signatures.
    run("codesign", "--force", "--deep", "--sign", "-", str(bundle))
    run("codesign", "--force", "--sign", "-", str(artifacts / "libgdcef.dylib"))
    destination = ROOT / "cef_artifacts"
    destination.mkdir(exist_ok=True)
    macos = destination / "macos"
    if macos.exists():
        shutil.rmtree(macos)
    shutil.copytree(artifacts, macos, symlinks=True)
    shutil.copy2(Path(build.CEF_ARTIFACTS_BUILD_PATH) / "gdcef.gdextension", destination)
    (destination / "macos/.gdignore").touch()
    print("CEF deployed to", macos)


if __name__ == "__main__":
    main()
