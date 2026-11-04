#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# DeepSting launcher (macOS / Linux)
# Run it to update the game to the latest version and play it:  ./play.sh
# - Put this file anywhere. The first run downloads the game into a
#   "DeepSting" folder next to it; later runs just update it.
#   (Run from inside the game folder itself, it updates that folder.)
# - Uses Git (recommended: it asks you to sign in to GitHub once, which a private
#   repository needs); without Git it downloads the latest zip (public repos only).
# - Downloads Godot once if it can't find it. To use your own copy, set
#   GODOT=/path/to/godot (on macOS: .../Godot.app/Contents/MacOS/Godot).
# Saves live in Godot's user data folder ("DeepSting") and are never touched by updates.
# ---------------------------------------------------------------------------
set -u
REPO="https://github.com/tmetcalf711/DEEPSTING"
# Leave BRANCH empty to follow the repository's default branch, or name one (e.g. main).
BRANCH=""
REF="${BRANCH:-HEAD}"
GODOT_VERSION="4.7.2"

HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$HERE/project.godot" ]; then GAME="$HERE"; else GAME="$HERE/DeepSting"; fi
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/deepsting/godot-$GODOT_VERSION"

echo
echo "  DeepSting - getting the latest version..."
echo

# ---- 1. Update the game -----------------------------------------------------
update_zip() {
	echo "  (Git not found - downloading the latest zip instead)"
	local tmp
	tmp="$(mktemp -d)" || return 1
	curl -fsSL "$REPO/archive/$REF.zip" -o "$tmp/game.zip" &&
		unzip -q "$tmp/game.zip" -d "$tmp" && rm -f "$tmp/game.zip" &&
		mkdir -p "$GAME" &&
		cp -R "$tmp"/*/. "$GAME"/
	local ok=$?
	rm -rf "$tmp"
	if [ $ok != 0 ]; then
		echo "  The zip download needs the repository to be public. Install Git"
		echo "  (https://git-scm.com) and sign in to GitHub when it asks, then run this again."
	fi
	return $ok
}

updated=1
if command -v git >/dev/null 2>&1; then
	if [ -d "$GAME/.git" ]; then
		git -C "$GAME" pull --ff-only origin "$REF" || updated=0
	elif [ -f "$GAME/project.godot" ]; then
		# A copy downloaded as a zip: turn it into a Git copy so it can update
		echo "  Switching this folder over to Git updates (one time only)..."
		git -C "$GAME" init -q &&
			{ git -C "$GAME" remote remove origin >/dev/null 2>&1; true; } &&
			git -C "$GAME" remote add origin "$REPO.git" &&
			git -C "$GAME" fetch --depth 1 origin "$REF" &&
			git -C "$GAME" reset -q --hard FETCH_HEAD &&
			{ [ -z "$BRANCH" ] || git -C "$GAME" branch -q -M "$BRANCH"; } || updated=0
	else
		git clone --depth 1 ${BRANCH:+--branch "$BRANCH"} "$REPO.git" "$GAME" || updated=0
	fi
else
	update_zip || updated=0
fi
if [ "$updated" = 0 ]; then
	echo
	echo "  Couldn't update the game (no internet, or local changes in the folder?)."
	if [ ! -f "$GAME/project.godot" ]; then
		echo "  There is no copy of the game yet, so there's nothing to play."
		exit 1
	fi
	echo "  Playing the version you already have."
fi

# ---- 2. Find (or fetch) Godot -------------------------------------------------
find_godot() {
	if [ -n "${GODOT:-}" ] && [ -x "$GODOT" ]; then echo "$GODOT"; return; fi
	case "$(uname -s)" in
		Darwin) local p="$CACHE/Godot.app/Contents/MacOS/Godot" ;;
		*) local p="$CACHE/Godot_v${GODOT_VERSION}-stable_linux.x86_64" ;;
	esac
	if [ -x "$p" ]; then echo "$p"; return; fi
	for name in godot godot4; do
		if command -v "$name" >/dev/null 2>&1 && "$name" --version 2>/dev/null | grep -q "^${GODOT_VERSION%.*}"; then
			command -v "$name"; return
		fi
	done
	echo "  Downloading Godot $GODOT_VERSION (one time only)..." >&2
	mkdir -p "$CACHE"
	case "$(uname -s)" in
		Darwin) local zip="Godot_v${GODOT_VERSION}-stable_macos.universal.zip" ;;
		*) local zip="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" ;;
	esac
	curl -fL --progress-bar "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/$zip" -o "$CACHE/godot.zip" &&
		unzip -qo "$CACHE/godot.zip" -d "$CACHE" && rm -f "$CACHE/godot.zip" && chmod +x "$p" 2>/dev/null
	if [ -x "$p" ]; then echo "$p"; fi
}

GODOT_EXE="$(find_godot)"
if [ -z "$GODOT_EXE" ]; then
	echo
	echo "  Couldn't find or download Godot $GODOT_VERSION. Get it from https://godotengine.org/download"
	echo "  and run:  GODOT=/path/to/godot ./play.sh"
	exit 1
fi

# ---- 3. Import new assets, then play ------------------------------------------
echo "  Preparing assets..."
"$GODOT_EXE" --headless --path "$GAME" --import >/dev/null 2>&1
echo "  Starting DeepSting!"
exec "$GODOT_EXE" --path "$GAME"
