#!/usr/bin/env bash
#
# Obsilain installer (macOS / Linux / Windows Git-Bash)
#
#   Usage:
#     ./install.sh [VAULT_PATH] [--beautitab] [--wallpaper /path/to/image.jpg]
#
#   - VAULT_PATH   Path to your Obsidian vault (the folder that contains .obsidian/).
#                  If omitted, the script tries to detect your vaults and lets you pick.
#   - --beautitab  Also install the Beautitab plugin (new-tab homepage). Downloads
#                  executable plugin code from its official GitHub release.
#   - --wallpaper  Local image to use as the background (sets --lain-wp for you).
#
# Installs: Border theme + lain-glass.css snippet, then enables them in appearance.json.
# A timestamped backup of .obsidian is taken before any config edit.
#
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/danisotosol/obsilain/main"
BORDER_RAW="https://raw.githubusercontent.com/Akifyss/obsidian-border/main"
BEAUTITAB_API="https://api.github.com/repos/andrewmcgivery/obsidian-beautitab/releases/latest"

VAULT=""
INSTALL_BEAUTITAB=""
WALLPAPER=""

err()  { printf '\033[31m[x] %s\033[0m\n' "$*" >&2; }
info() { printf '\033[36m[*] %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m[+] %s\033[0m\n' "$*"; }

# ---- parse args (first non-flag arg = vault) -------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --beautitab) INSTALL_BEAUTITAB=1; shift;;
    --wallpaper) WALLPAPER="${2:-}"; shift 2;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    --*) err "Unknown flag: $1"; exit 1;;
    *)   VAULT="$1"; shift;;
  esac
done

command -v curl >/dev/null 2>&1 || { err "curl is required."; exit 1; }
PY="$(command -v python3 || command -v python || true)"

# ---- locate the obsidian.json (for vault auto-detect) ----------------------
obsidian_json() {
  case "$(uname -s)" in
    Darwin) echo "$HOME/Library/Application Support/obsidian/obsidian.json";;
    Linux)  echo "${XDG_CONFIG_HOME:-$HOME/.config}/obsidian/obsidian.json";;
    MINGW*|MSYS*|CYGWIN*) echo "${APPDATA:-$HOME/AppData/Roaming}/obsidian/obsidian.json";;
    *) echo "";;
  esac
}

# ---- pick a vault if none was given ----------------------------------------
if [ -z "$VAULT" ]; then
  OJ="$(obsidian_json)"
  if [ -n "$PY" ] && [ -f "$OJ" ]; then
    info "Detected vaults:"
    mapfile -t VAULTS < <("$PY" - "$OJ" <<'PYEOF'
import json,sys
try:
    d=json.load(open(sys.argv[1],encoding="utf-8"))
    for v in d.get("vaults",{}).values():
        print(v.get("path",""))
except Exception:
    pass
PYEOF
)
    if [ "${#VAULTS[@]}" -gt 0 ]; then
      i=1; for v in "${VAULTS[@]}"; do printf '   %d) %s\n' "$i" "$v"; i=$((i+1)); done
      printf 'Pick a number (or type a path): '; read -r CHOICE
      if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#VAULTS[@]}" ]; then
        VAULT="${VAULTS[$((CHOICE-1))]}"
      else
        VAULT="$CHOICE"
      fi
    fi
  fi
fi
if [ -z "$VAULT" ]; then
  printf 'Path to your Obsidian vault: '; read -r VAULT
fi

OBS="$VAULT/.obsidian"
[ -d "$OBS" ] || { err "No .obsidian folder in: $VAULT"; exit 1; }
ok "Vault: $VAULT"

# ---- backup ----------------------------------------------------------------
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$OBS.backup-$STAMP"
cp -r "$OBS" "$BACKUP"
ok "Backup: $BACKUP"

mkdir -p "$OBS/themes/Border" "$OBS/snippets"

# ---- Border theme ----------------------------------------------------------
info "Downloading Border theme..."
curl -fsSL "$BORDER_RAW/theme.css"    -o "$OBS/themes/Border/theme.css"
curl -fsSL "$BORDER_RAW/manifest.json" -o "$OBS/themes/Border/manifest.json"
ok "Border installed."

# ---- lain-glass snippet ----------------------------------------------------
info "Downloading lain-glass snippet..."
curl -fsSL "$REPO_RAW/lain-glass.css" -o "$OBS/snippets/lain-glass.css"
ok "Snippet installed."

# ---- optional wallpaper ----------------------------------------------------
if [ -n "$WALLPAPER" ]; then
  if [ -f "$WALLPAPER" ]; then
    ABS="$(cd "$(dirname "$WALLPAPER")" && pwd)/$(basename "$WALLPAPER")"
    URL="app://local/${ABS#/}"   # app://local/ + absolute path (no leading slash)
    if [ -n "$PY" ]; then
      "$PY" - "$OBS/snippets/lain-glass.css" "$URL" <<'PYEOF'
import re,sys
f,url=sys.argv[1],sys.argv[2]
css=open(f,encoding="utf-8").read()
css=re.sub(r'(--lain-wp:\s*)url\([^)]*\)[^;]*;', r'\1url("%s");' % url, css, count=1)
open(f,"w",encoding="utf-8").write(css)
PYEOF
      ok "Wallpaper set: $URL"
    else
      err "python not found; set --lain-wp manually in lain-glass.css."
    fi
  else
    err "Wallpaper not found: $WALLPAPER (skipping)."
  fi
fi

# ---- optional Beautitab plugin --------------------------------------------
if [ -n "$INSTALL_BEAUTITAB" ]; then
  info "Installing Beautitab plugin (executable code from official release)..."
  mkdir -p "$OBS/plugins/beautitab"
  JSON="$(curl -fsSL "$BEAUTITAB_API")"
  for f in manifest.json main.js styles.css; do
    U="$(printf '%s' "$JSON" | grep -o "\"browser_download_url\": *\"[^\"]*/$f\"" | head -1 | sed 's/.*"\(https[^"]*\)".*/\1/')"
    [ -n "$U" ] && curl -fsSL "$U" -o "$OBS/plugins/beautitab/$f"
  done
  ok "Beautitab installed (enable Community plugins in Obsidian if in Restricted mode)."
fi

# ---- enable in appearance.json + community-plugins.json --------------------
if [ -n "$PY" ]; then
  "$PY" - "$OBS" "${INSTALL_BEAUTITAB:-}" <<'PYEOF'
import json,os,sys
obs,beauti=sys.argv[1],sys.argv[2]
def load(p,default):
    try: return json.load(open(p,encoding="utf-8"))
    except Exception: return default
ap=os.path.join(obs,"appearance.json")
a=load(ap,{})
a["cssTheme"]="Border"
snips=a.get("enabledCssSnippets",[])
if "lain-glass" not in snips: snips.append("lain-glass")
a["enabledCssSnippets"]=snips
json.dump(a,open(ap,"w",encoding="utf-8"),indent=2)
if beauti:
    cp=os.path.join(obs,"community-plugins.json")
    c=load(cp,[])
    if "beautitab" not in c: c.append("beautitab")
    json.dump(c,open(cp,"w",encoding="utf-8"),indent=2)
print("config updated")
PYEOF
  ok "Enabled: theme=Border, snippet=lain-glass${INSTALL_BEAUTITAB:+, plugin=beautitab}."
else
  err "python not found — enable manually:"
  echo "    Settings > Appearance > Theme: Border"
  echo "    Settings > Appearance > CSS snippets: lain-glass (ON)"
fi

echo
ok "Done. Reload Obsidian (Ctrl/Cmd+R)."
[ -z "$WALLPAPER" ] && echo "    Tip: set your wallpaper by editing --lain-wp in .obsidian/snippets/lain-glass.css"
