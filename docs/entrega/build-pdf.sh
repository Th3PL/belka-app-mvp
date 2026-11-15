#!/usr/bin/env bash
# Monta docs/entrega/entrega.html a partir do template e gera o PDF da entrega.
# Prints: salve as imagens em docs/entrega/prints/ com os nomes indicados no template
# (ex.: 05-terraform-apply.png). Os que faltarem aparecem como quadro tracejado.
#
# Uso (Git Bash): bash docs/entrega/build-pdf.sh
set -euo pipefail
cd "$(dirname "$0")"

URL="${URL:-https://belka-api.salmonisland-04dfa6a6.brazilsouth.azurecontainerapps.io}"
REPO="${REPO:-https://github.com/Th3PL/belka-app-mvp}"
RUN_BLOCKED="${RUN_BLOCKED:-$REPO/actions/runs/43745100897}"
RUN_FIXED="${RUN_FIXED:-$REPO/actions?query=branch%3Ademo%2Fsegredo-vazado}"
RUN_DEPLOY="${RUN_DEPLOY:-$REPO/actions/runs/43747965034}"

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$1"; }
EVID_INGRESS="$( [ -f evidencias/ingress.txt ] && esc evidencias/ingress.txt || echo 'Rode: az containerapp show ... (ver README)')"
EVID_PROXY="$( [ -f evidencias/proxy.txt ] && esc evidencias/proxy.txt || echo "pendente")"
EVID_ALERTA="$( [ -f evidencias/alerta.txt ] && esc evidencias/alerta.txt || echo 'pendente')"

awk -v url="$URL" -v repo="$REPO" -v rb="$RUN_BLOCKED" -v rf="$RUN_FIXED" -v rd="$RUN_DEPLOY" \
    -v ingress="$EVID_INGRESS" -v alerta="$EVID_ALERTA" -v proxy="$EVID_PROXY" '
  function rep(s, k, v) { while ((i = index(s, k)) > 0) s = substr(s, 1, i-1) v substr(s, i+length(k)); return s }
  /\{\{DIAGRAMA\}\}/ { while ((getline l < "diagrama.svg") > 0) print l; next }
  /<!--PRINT:/ {
    match($0, /<!--PRINT:[^|]+\|[^>]*-->/)
    spec = substr($0, RSTART+10, RLENGTH-13); split(spec, p, "|")
    f = "prints/" p[1]
    if ((getline tmp < f) >= 0) { close(f); printf "<figure><img src=\"%s\" alt=\"%s\"><figcaption>%s</figcaption></figure>\n", f, p[2], p[2] }
    else printf "<div class=\"ph\"><b>PRINT PENDENTE</b> — %s<br><code>docs/entrega/%s</code></div>\n", p[2], f
    next
  }
  { s = $0
    s = rep(s, "{{URL}}", url); s = rep(s, "{{REPO}}", repo)
    s = rep(s, "{{RUN_BLOCKED}}", rb); s = rep(s, "{{RUN_FIXED}}", rf); s = rep(s, "{{RUN_DEPLOY}}", rd)
    s = rep(s, "{{EVID_INGRESS}}", ingress); s = rep(s, "{{EVID_ALERTA}}", alerta); s = rep(s, "{{EVID_PROXY}}", proxy)
    print s }
' entrega.template.html > entrega.html

BROWSER=""
for b in "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
         "/c/Program Files/Microsoft/Edge/Application/msedge.exe" \
         "/c/Program Files/Google/Chrome/Application/chrome.exe"; do
  [ -x "$b" ] && BROWSER="$b" && break
done
[ -n "$BROWSER" ] || { echo "Edge/Chrome não encontrado; abra entrega.html e imprima em PDF."; exit 0; }

OUT="$(cygpath -w "$PWD/Belka-Entrega-SecureDevOps-Cloud.pdf" 2>/dev/null || echo "$PWD/Belka-Entrega-SecureDevOps-Cloud.pdf")"
IN="file:///$(cygpath -m "$PWD/entrega.html" 2>/dev/null || echo "$PWD/entrega.html")"
"$BROWSER" --headless=new --disable-gpu --no-pdf-header-footer --print-to-pdf="$OUT" "$IN" >/dev/null 2>&1
echo "PDF gerado: $OUT"
