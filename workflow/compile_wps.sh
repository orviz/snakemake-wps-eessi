#!/usr/bin/bash
# workflow/compile_wps.sh
set -euo pipefail

# =========================================================================
# 1. PARSEO DE PARÁMETROS DE REGLA
# =========================================================================
EESSI_INIT_SCRIPT="$1"
TARGET_COMPILATION_DIR="$2"
MARKER_DIR="$3"
MARKER_ABS_PATH="$4"

# =========================================================================
# 2. CARGA AISLADA DE MÓDULOS DE ENTORNO (EESSI Master Toolchain)
# =========================================================================
set +u
source "$EESSI_INIT_SCRIPT"
module load foss/2024a \
            WRF/4.6.1-foss-2024a-dmpar \
            JasPer/4.2.4-GCCcore-13.3.0 \
            netCDF-Fortran/4.6.1-gompi-2024a \
            libpng/1.6.43-GCCcore-13.3.0 \
            Perl/5.38.2-GCCcore-13.3.0
set -u

# =========================================================================
# 3. ACCESO AL ENTORNO LOCAL Y PURGA RADICAL DE CONFIGURACIONES VLEJAS
# =========================================================================
cd "$TARGET_COMPILATION_DIR"

echo "[Bash Script] Destroying stale configurations to unblock ungrib compiler..."
# Forzamos la eliminación del archivo configure de la raíz para que no herede bloqueos viciados
rm -f configure.wps configure.wrf 2>/dev/null || true
rm -f *.exe geogrid/*.exe metgrid/*.exe ungrib/*.exe 2>/dev/null || true

# Ejecutamos una limpieza profunda en las fuentes de ungrib
(cd ungrib/src && rm -f *.o *.exe ../*.exe 2>/dev/null || true)

# =========================================================================
# 4. BLINDAJE DE ENLAZADO DE BAJO NIVEL (NetCDF + JasPer + PNG)
# =========================================================================
export LD_LIBRARY_PATH=$NETCDFF/lib:$NETCDF_C/lib:$EBROOTJASPER/lib:$EBROOTJASPER/lib64:${LD_LIBRARY_PATH:-}

# Exportamos las variables de la toolchain al entorno de Bash
export NETCDF=$NETCDFF
export NETCDF_DIR=$NETCDFF
export JASPERLIB=$EBROOTJASPER/lib
export JASPERINC=$EBROOTJASPER/include
export WRF_DIR=$EBROOTWRF/WRFV4.6.1

# Banderas de bajo nivel universales para compresión GRIB2
export WRF_EXTRA_LIBS="-lnetcdff -lnetcdf -ljasper -lpng -lz"
export LDFLAGS="-L$EBROOTJASPER/lib -L$EBROOTJASPER/lib64 -L$NETCDFF/lib -L$NETCDF_C/lib"
export LIBS="-lnetcdff -lnetcdf -ljasper -lpng -lz"

# Mitigación de memoria para Arquitectura Zen3
export OPENBLAS_NUM_THREADS=1
export FLEXIBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
ulimit -s unlimited

echo "[Bash Script] Configuring fresh new WPS build..."
# Forzamos la opción 3 (gfortran dmpar) alimentando el ./configure limpio
echo "3" | ./configure

echo "[Bash Script] Injecting missing EESSI compression flags into fresh configure.wps..."
# Aseguramos que el configure.wps recién creado lleve las directivas estricta de PNG y ZLIB
sed -i "s|-ljasper|-ljasper -lpng -lz|g" configure.wps
sed -i "s|COMPRESSION_LIBS	=|COMPRESSION_LIBS	= -L$EBROOTJASPER/lib -L$EBROOTJASPER/lib64 -ljasper -lpng -lz|g" configure.wps
sed -i "s|COMPRESSION_INC	=|COMPRESSION_INC	= -I$EBROOTJASPER/include|g" configure.wps

echo "[Bash Script] Launching compilation (csh ./compile)..."
csh ./compile

# =========================================================================
# 5. AUDITORÍA DINÁMICA DE ENDPOINTS BINARIOS
# =========================================================================
echo "[Bash Script] Auditing workspace to locate generated binaries..."

REAL_GEOGRID=$(find . -type f -name "geogrid.exe" | head -n 1)
REAL_METGRID=$(find . -type f -name "metgrid.exe" | head -n 1)
REAL_UNGRIB=$(find . -type f -name "ungrib.exe" | head -n 1)

if [ -n "$REAL_GEOGRID" ] && [ -n "$REAL_METGRID" ] && [ -n "$REAL_UNGRIB" ]; then
    echo "[Bash Script Success] Validation passed! All 3 core executables exist."
    echo " -> Geogrid: $REAL_GEOGRID"
    echo " -> Metgrid: $REAL_METGRID"
    echo " -> Ungrib:  $REAL_UNGRIB"
    
    rm -f geogrid.exe metgrid.exe ungrib.exe 2>/dev/null || true
    ln -sf "$REAL_GEOGRID" geogrid.exe
    ln -sf "$REAL_METGRID" metgrid.exe
    ln -sf "$REAL_UNGRIB"  ungrib.exe
    
    mkdir -p "$MARKER_DIR"
    touch "$MARKER_ABS_PATH"
else
    echo "❌ [Bash Script Error] Main meteorology executables are missing!"
    echo "Rastreo de control del disco actual:"
    find . -maxdepth 3 -name "*.exe" || true
    exit 1
fi
