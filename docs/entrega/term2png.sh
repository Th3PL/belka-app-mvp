#!/usr/bin/env bash
# Renderiza a saída real de um comando (arquivo .txt) como imagem de terminal (PNG).
# Uso: bash term2png.sh <entrada.txt> <saida.png> "<título da janela>"
set -euo pipefail
in="$1"; out="$2"; title="${3:-terminal}"
tmp="$(mktemp -d)"; html="$tmp/t.html"
lines=$(wc -l < "$in"); h=$(( lines * 19 + 90 )); [ "$h" -lt 200 ] && h=200
{
  printf '<!doctype html><meta charset="utf-8"><style>
  body{margin:0;background:#e9edf3;font:13px/19px Consolas,"Cascadia Mono",monospace}
  .w{margin:14px;border-radius:9px;overflow:hidden;box-shadow:0 6px 22px #0003}
  .b{background:#2b3442;color:#cfd6e2;padding:7px 12px;font:12px "Segoe UI",sans-serif}
  .b i{display:inline-block;width:11px;height:11px;border-radius:50%%;margin-right:6px;vertical-align:-1px}
  pre{margin:0;background:#0f1b2e;color:#e6edf7;padding:12px 14px;white-space:pre-wrap;word-break:break-word}
  .c{color:#7fd1ff}</style><div class="w"><div class="b"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i>&nbsp;%s</div><pre>' "$title"
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/\x1b\[[0-9;]*m//g' \
      -e 's/^\(\$ .*\)$/<span class="c">\1<\/span>/' "$in"
  printf '</pre></div>'
} > "$html"
E="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
"$E" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=1150,"$h" --screenshot="$(cygpath -w "$(realpath -m "$out")")" "file:///$(cygpath -m "$html")" >/dev/null 2>&1
rm -rf "$tmp"
echo "$out"
