import hashlib
import json
import shutil
import sys
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
HOSTS = ("https://huggingface.co", "https://hf-mirror.com")


def sha256(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def install_model(model):
    directory = ROOT / "models" / model["directory"]
    directory.mkdir(parents=True, exist_ok=True)
    hosts = list(HOSTS)
    for name, expected in model["files"].items():
        target = directory / name
        if target.is_file() and sha256(target) == expected:
            continue
        temporary = directory / (name + ".part")
        for host in hosts:
            url = f"{host}/{model['repo']}/resolve/{model['revision']}/{name}"
            print(f"Downloading {model['directory']}/{name} from {host}", flush=True)
            try:
                request = Request(url, headers={"User-Agent": "VoxRibbon-Windows-Installer"})
                with urlopen(request, timeout=15) as response, temporary.open("wb") as file:
                    shutil.copyfileobj(response, file)
                if sha256(temporary) != expected:
                    raise ValueError("SHA-256 mismatch")
                temporary.replace(target)
            except (URLError, OSError, ValueError) as error:
                temporary.unlink(missing_ok=True)
                print(f"Download failed: {error}", file=sys.stderr)
                continue
            hosts = [host, *(candidate for candidate in HOSTS if candidate != host)]
            break
        else:
            raise SystemExit(f"Could not download a verified copy of {model['directory']}/{name}.")


def main():
    models = json.loads((ROOT / "model-files.json").read_text(encoding="utf-8"))
    for model in models:
        install_model(model)


if __name__ == "__main__":
    main()
