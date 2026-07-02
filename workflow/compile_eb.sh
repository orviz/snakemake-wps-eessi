#!/usr/bin/bash
# workflow/compile_eb.sh
set -euo pipefail

# 1. Parámetros de entrada de Snakemake
EESSI_INIT_SCRIPT="$1"
STATUS_JSON="$2"
LOCAL_RECIPE_PATH="$3"
MARKER_DIR="$4"
MARKER_ABS_PATH="$5"

# 2. Leemos el veredicto del JSON usando Python integrado (HPC-safe, sin dependencias de jq)
STATUS=$(python3 -c "import json; print(json.load(open('$STATUS_JSON'))['status'])")
RECIPE_TARGET=$(python3 -c "import json; print(json.load(open('$STATUS_JSON'))['recipe_target'])")

# 3. Inicialización aislada y estéril de la pila de EESSI
set +u
source "$EESSI_INIT_SCRIPT"
module load EESSI-extend
set -u

export OPENBLAS_NUM_THREADS=1
export FLEXIBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
ulimit -s unlimited

# 4. Decisión algorítmica de compilación (Bypass de Hooks de EESSI)
if [ "$STATUS" == "EESSI_OFFICIAL" ]; then
    echo "[Compilador] Sintonizando modo OFICIAL. Usando receta nativa de EESSI: $RECIPE_TARGET"
    
    eb "$RECIPE_TARGET" \
      --robot \
      --local-var-naming-check=warn \
      --skip-test-step \
      --detect-loaded-modules=purge \
      --force
else
    echo "[Compilador] Sintonizando modo CONTINGENCIA LOCAL. Inyectando receta y parches propios..."
    # Localizamos la carpeta donde Snakemake tiene los parches locales de contingencia
    PATCH_DIR=$(dirname "$LOCAL_RECIPE_PATH")
    
    eb "$LOCAL_RECIPE_PATH" \
      --robot \
      --local-var-naming-check=warn \
      --skip-test-step \
      --detect-loaded-modules=purge \
      --ignore-checksums \
      --patches-path="$PATCH_DIR" \
      --force
fi

# 5. Confirmación física del éxito
mkdir -p "$MARKER_DIR"
touch "$MARKER_ABS_PATH"
echo "[Compilador Success] Despliegue de $RECIPE_TARGET completado con éxito."
