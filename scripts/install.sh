#!/bin/zsh
# Build locally, then replace only the app bundle. Never edit user data.
set -euo pipefail
script_root="${0:A:h:h}"

usage() {
    cat <<'HELP'
Usage: ./scripts/install.sh [--no-update] [--no-open] [--destination DIRECTORY]

Install/update ~/Applications/Mac Buddy.app without sudo.
Git clones pull their configured upstream with --ff-only before building.
Source ZIPs build the files already downloaded; download a new ZIP to update.

  --no-update         Build local sources without fetching (also for contributors).
  --no-open           Install without launching the new app.
  --destination DIR   Install into DIR instead of ~/Applications.
  --help              Show this help.
HELP
}
fail() { print -u2 -- "Mac Buddy: $*"; exit 1; }
plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }

cleanup() {
    local result_code=$?
    trap - EXIT
    if (( old_moved && !new_installed )); then
        if [[ ! -e "$target" && ! -L "$target" ]] && mv "$work/Previous.app" "$target"; then
            print -u2 -- "Restored the previous app."
            if (( running_count > 0 )); then
                "$helper" open "$target" "$bundle_id" || print -u2 -- "Open the restored app manually: $target"
            fi
        else
            print -u2 -- "Previous app preserved for recovery at: $work/Previous.app"
        fi
    fi
    # Never discard the sole previous app if a rollback/backup rename failed.
    if [[ -n "$work" && ! -e "$work/Previous.app" ]]; then rm -rf -- "$work"; fi
    if (( destination_locked )); then rm -f -- "$destination_lock/pid"; rmdir "$destination_lock" || true; fi
    if (( repository_locked )); then rm -f -- "$repository_lock/pid"; rmdir "$repository_lock" || true; fi
    return "$result_code"
}

main() {
    root="$script_root"
    original_args=("$@")
    destination="$HOME/Applications"
    update_sources=1; launch_app=1
    work=""; target=""; helper=""; bundle_id=""
    repository_locked=0; destination_locked=0; old_moved=0; new_installed=0; running_count=0
    while (( $# )); do
        case "$1" in
            --help|-h) usage; return 0 ;;
            --no-update) update_sources=0; shift ;;
            --no-open) launch_app=0; shift ;;
            --destination)
                (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || fail "--destination needs a directory."
                destination="$2"; shift 2 ;;
            *) usage >&2; fail "Unknown option: $1" ;;
        esac
    done
    [[ "$(uname -s)" == Darwin ]] || fail "This installer requires macOS."
    (( EUID != 0 )) || fail "Run as your normal user, without sudo."
    [[ "$(uname -m)" == arm64 ]] || fail "Use an Apple-silicon Mac and a native (not Rosetta) Terminal."
    os_version="$(sw_vers -productVersion)"
    (( ${os_version%%.*} >= 14 )) || fail "macOS 14 or newer is required."
    swift_version="$(xcrun swiftc --version)" || fail "Install Apple's Command Line Tools: xcode-select --install"
    swift_major="$(print -r -- "$swift_version" | sed -nE 's/.*Swift version ([0-9]+).*/\1/p' | head -1)"
    [[ -n "$swift_major" ]] && (( swift_major >= 6 )) || fail "Update Xcode/Command Line Tools to Swift 6 or newer."

    mkdir -p "$root/tmp" "$destination"
    destination="${destination:A}"
    target="$destination/Mac Buddy.app"
    backup="$destination/.MacBuddy-previous.app"
    repository_lock="$root/tmp/install.lock"
    destination_lock="$destination/.MacBuddy-install.lock"
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    mkdir "$repository_lock" 2>/dev/null || fail "Another install may be running; inspect $repository_lock before retrying."
    repository_locked=1; print -r -- "$$" > "$repository_lock/pid"
    mkdir "$destination_lock" 2>/dev/null || fail "Another install may be running; inspect $destination_lock before retrying."
    destination_locked=1; print -r -- "$$" > "$destination_lock/pid"

    if (( update_sources )); then
        if [[ -d "$root/.git" || -f "$root/.git" ]]; then
            [[ -z "$(git -C "$root" status --porcelain)" ]] || fail "Source changes found. Commit/stash them, or use --no-update to build them locally."
            git -C "$root" symbolic-ref --quiet HEAD >/dev/null || fail "Detached Git checkout; choose a branch or use --no-update."
            print -- "Fetching updates from this branch's configured upstream…"
            git -C "$root" -c pull.rebase=false -c pull.autostash=false -c merge.autostash=false pull --ff-only || fail "Source update failed. Installed app and user data are unchanged."
            # Parse the newly fetched script rather than continuing an older installer.
            cleanup
            trap - EXIT INT TERM HUP
            exec /bin/zsh "$root/scripts/install.sh" --no-update "${original_args[@]}"
        else
            print -- "Source ZIP: building local files. Download a new ZIP for future updates."
        fi
    fi

    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$root/Resources/Info.plist")"
    [[ -n "$bundle_id" ]] || fail "Source bundle identifier is missing."
    for existing in "$target" "$backup"; do
        [[ ! -L "$existing" ]] || fail "Refusing to replace a symbolic link: $existing"
        if [[ -e "$existing" ]]; then
            [[ -d "$existing" ]] && [[ "$(plist_value "$existing" CFBundleIdentifier 2>/dev/null)" == "$bundle_id" ]] || fail "Destination contains a different app or file: $existing"
        fi
    done

    print -- "Building Mac Buddy. Any running copy stays open during the build…"
    /bin/zsh "$root/scripts/build.sh"
    built="$root/dist/Mac Buddy.app"
    [[ "$(plist_value "$built" CFBundleIdentifier)" == "$bundle_id" ]] || fail "Build has an unexpected bundle identity."
    [[ "$(plist_value "$built" CFBundleExecutable)" == MacBuddy ]] || fail "Build has an unexpected executable."
    codesign --verify --strict "$built"

    work="$(mktemp -d "$destination/.MacBuddy-install.XXXXXX")"
    helper="$work/lifecycle"
    xcrun swiftc -swift-version 5 -O -module-cache-path "$root/.build/module-cache" "$root/scripts/install-lifecycle.swift" -o "$helper"
    ditto "$built" "$work/New.app"
    codesign --verify --strict "$work/New.app"
    [[ "$(plist_value "$work/New.app" CFBundleIdentifier)" == "$bundle_id" ]] || fail "Staged app identity changed."

    print -- "Asking any running Mac Buddy copies to quit normally and flush history…"
    running_count="$("$helper" quit "$bundle_id")" || fail "Mac Buddy did not quit. Quit it from its menu bar and retry; no process was force-killed."
    if [[ -e "$target" ]]; then
        mv "$target" "$work/Previous.app"
        old_moved=1
    fi
    # Same-filesystem rename; never overwrite the inode of a running executable.
    mv "$work/New.app" "$target"
    new_installed=1
    if (( old_moved )); then
        if [[ -e "$backup" ]]; then rm -rf -- "$backup"; fi
        mv "$work/Previous.app" "$backup"
    fi
    print -- "Installed: $target"
    if (( old_moved )); then print -- "Previous app: $backup"; fi
    print -- "Settings, history and permission/login choices were not modified by the installer."
    if (( launch_app )); then
        "$helper" open "$target" "$bundle_id" || fail "Installed successfully, but macOS did not launch the app. Open it manually at: $target"
    fi
}
main "$@"
