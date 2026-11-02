"""Replace only RomM's rendered stock library location, before nginx starts."""

import os
from pathlib import Path
import re
import stat
import tempfile


CONFIG_PATH = Path("/etc/nginx/conf.d/default.conf")


def patch_library(config: str, base_path: str) -> str:
    """Fail closed if the upstream library location no longer matches."""
    locations = re.findall(
        r"\blocation\s+(?:(?:=|\^~|~\*?)\s+)?/library/\s*\{", config
    )
    expected = re.compile(
        r"^(?P<indent>[ \t]*)location\s+/library/\s*\{\s*"
        r"internal\s*;\s*alias\s+\""
        + re.escape(base_path + "/library/")
        + r"\"\s*;\s*\}",
        re.MULTILINE,
    )
    matches = list(expected.finditer(config))
    if len(locations) != 1 or len(matches) != 1:
        raise ValueError(
            "Expected exactly one stock /library/ location with only internal "
            "and the ROMM_BASE_PATH library alias; review the upstream nginx config "
            f"(found {len(locations)} locations, {len(matches)} expected blocks)."
        )
    return expected.sub(
        lambda match: match["indent"] + "include /etc/nginx/romm-library.conf;",
        config,
    )


def main() -> None:
    patched = patch_library(
        CONFIG_PATH.read_text(), os.environ.get("ROMM_BASE_PATH", "/romm")
    )
    # Rendered config and its directory are writable by the RomM user.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", dir=CONFIG_PATH.parent, delete=False
        ) as output:
            temporary = Path(output.name)
            output.write(patched)
            os.fchmod(output.fileno(), stat.S_IMODE(CONFIG_PATH.stat().st_mode))
        os.replace(temporary, CONFIG_PATH)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        raise SystemExit(f"RomM nginx patch failed: {error}") from error
