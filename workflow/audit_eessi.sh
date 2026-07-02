#!/usr/bin/bash
# workflow/audit_eessi.sh
set -euo pipefail

# 1. Parámetros de entrada de Snakemake
EESSI_INIT_SCRIPT="$1"
SOFTWARE_NAME="$2"      # Ej: "WPS" o "WRF"
SOFTWARE_VERSION="$3"   # Ej: "4.6.0" o "4.6.1"
TOOLCHAIN_SUFIX="$4"    # Ej: "-foss-2024a-dmpar"
OUTPUT_JSON="$5"

# 2. Inicialización aislada y estéril de la pila de EESSI
set +u
source "$EESSI_INIT_SCRIPT"
module load EESSI-extend
set -u

echo "[Auditor EESSI] Interrogando al repositorio central para $SOFTWARE_NAME v$SOFTWARE_VERSION..."

# Nombre exacto de la receta oficial que debería estar en CVMFS
TARGET_RECIPE="${SOFTWARE_NAME}-${SOFTWARE_VERSION}${TOOLCHAIN_SUFIX}.eb"

# Ejecutamos eb -S capturando la salida y forzando la limpieza de módulos para que no colapse
EB_SEARCH_OUT=$(eb -S "$SOFTWARE_NAME" --detect-loaded-modules=purge 2>&1 || true)

# 3. Analizamos de forma empírica si la receta buscada aparece en el índice de CVMFS
if echo "$EB_SEARCH_OUT" | grep -q "$TARGET_RECIPE"; then
    echo " -> [FOUND] La receta oficial '$TARGET_RECIPE' SÍ está integrada en EESSI."
    STATUS="EESSI_OFFICIAL"
else
    echo " -> [NOT FOUND] La receta '$TARGET_RECIPE' NO existe en EESSI. Se requerirá fallback local."
    STATUS="FALLBACK_LOCAL"
fi

# 4. Escribimos el resultado en un JSON estructurado para que Snakemake lo lea nativamente
mkdir -p "$(dirname "$OUTPUT_JSON")"
cat << EOF > "$OUTPUT_JSON"
{
  "software": "$SOFTWARE_NAME",
  "version": "$SOFTWARE_VERSION",
  "recipe_target": "$TARGET_RECIPE",
  "status": "$STATUS",
  "timestamp": "$(date -Iseconds)"
}
EOF

echo "[Auditor EESSI] Diagnóstico consolidado con éxito en: $OUTPUT_JSON"
