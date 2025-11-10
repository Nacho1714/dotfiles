#!/bin/bash
# ============================================================================
# .bash_aliases - Carga modular de aliases organizados por categoría
# ============================================================================

# Directorio base donde están organizados los aliases
ALIASES_DIR="${HOME}/.config/aliases"

# Función para cargar aliases de forma segura
load_aliases() {
    local category="$1"
    local alias_file="${ALIASES_DIR}/${category}/aliases.sh"
    
    if [ -f "$alias_file" ]; then
        source "$alias_file"
    fi
}

# Cargar aliases por categoría (dinámicamente)
if [ -d "$ALIASES_DIR" ]; then
    for category_dir in "$ALIASES_DIR"/*; do
        if [ -d "$category_dir" ]; then
            category=$(basename "$category_dir")
            load_aliases "$category"
        fi
    done
fi

# Limpiar función temporal
unset -f load_aliases
unset ALIASES_DIR
