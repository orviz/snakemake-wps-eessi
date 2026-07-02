#!/usr/bin/bash
# workflow/compile_eb.sh
set -euo pipefail

# =========================================================================
# 1. PARSEO DE PARÁMETROS DE ENTRADA DE SNAKEMAKE
# =========================================================================
EESSI_INIT_SCRIPT="$1"
STATUS_JSON="$2"
LOCAL_RECIPE_PATH="$3"
MARKER_DIR="$4"
MARKER_ABS_PATH="$5"

# =========================================================================
# 2. EXTRACCIÓN DINÁMICA DE METADATOS DEL JSON (HPC-Safe con Python)
# =========================================================================
# Extraemos el estado, el nombre del software y la receta objetivo del JSON real
STATUS=$(python3 -c "import json; print(json.load(open('$STATUS_JSON'))['status'])")
RECIPE_TARGET=$(python3 -c "import json; print(json.load(open('$STATUS_JSON'))['recipe_target'])")
SOFTWARE_NAME=$(python3 -c "import json; print(json.load(open('$STATUS_JSON'))['software'])")

# =========================================================================
# 3. INICIALIZACIÓN AISLADA Y ESTÉRIL DE LA PILA DE EESSI
# =========================================================================
set +u
source "$EESSI_INIT_SCRIPT"
module load EESSI-extend
set -u

# Banderas de mitigación de hilos y memoria para el subprocesamiento
export OPENBLAS_NUM_THREADS=1
export FLEXIBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
ulimit -s unlimited

# =========================================================================
# 4. DECISIÓN ALGORÍTMICA DE COMPILACIÓN (Bypass de Hooks de EESSI)
# =========================================================================
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

# =========================================================================
# 5. DESCUBRIMIENTO DINÁMICO DE LA RUTA DE INSTALACIÓN REAL (Opción 1)
# =========================================================================
# Usamos la variable nativa de EasyBuild para saber dónde se guardó el software
INSTALL_PATH="${EASYBUILD_INSTALLPATH:-$HOME/eessi/versions/2025.06/software/linux/x86_64}"

echo "[Compilador] Buscando binarios reales en la ruta dinámica: $INSTALL_PATH"

# Buscamos los binarios físicos reales generados por el build
REAL_WRF=$(find "$INSTALL_PATH" -type f -name "wrf.exe" | head -n 1)
REAL_UNGRIB=$(find "$INSTALL_PATH" -type f -name "ungrib.exe" | head -n 1)

# Creamos la carpeta local del repositorio si no existiera
mkdir -p "$MARKER_DIR"

# Sincronizamos las condiciones de victoria física creando los enlaces simbólicos locales
if [ "$SOFTWARE_NAME" == "WPS" ] && [ -n "$REAL_UNGRIB" ]; then
    echo " -> [OK] Detectado WPS en: $REAL_UNGRIB"
    ln -sf "$REAL_UNGRIB" "$MARKER_ABS_PATH"
elif [ "$SOFTWARE_NAME" == "WRF" ] && [ -n "$REAL_WRF" ]; then
    echo " -> [OK] Detectado WRF en: $REAL_WRF"
    ln -sf "$REAL_WRF" "$MARKER_ABS_PATH"
else
    echo "❌ [Error] El Sanity Check falló: No se encontraron los binarios en $INSTALL_PATH"
    exit 1
fi

echo "[Compilador Success] Enlace simbólico de producción asentado con éxito en: $MARKER_ABS_PATH"
