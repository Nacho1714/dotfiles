#!/bin/bash

set -e

# ============================================================================
# CONFIGURACIÓN
# ============================================================================
DOTFILES_DIR="$HOME/dotfiles"
METADATA_FILE="$DOTFILES_DIR/.install_metadata"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# FUNCIONES AUXILIARES
# ============================================================================

print_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# ============================================================================
# LECTURA DE METADATA
# ============================================================================

read_metadata() {
    if [ ! -f "$METADATA_FILE" ]; then
        print_warning "No se encontró metadata de instalación"
        echo "none"
        return
    fi
    
    source "$METADATA_FILE"
    
    print_info "Fecha de instalación: $INSTALL_DATE"
    print_info "Paquetes instalados: $INSTALLED_PACKAGES"
    
    if [ "$BACKUP_DIR" != "none" ] && [ -d "$BACKUP_DIR" ]; then
        print_info "Backup disponible: $BACKUP_DIR"
    fi
    
    echo "$INSTALLED_PACKAGES|$BACKUP_DIR"
}

# ============================================================================
# DETECCIÓN DE PAQUETES (fallback si no hay metadata)
# ============================================================================

detect_packages() {
    print_info "Detectando paquetes instalados..."
    
    local packages=()
    
    for dir in "$DOTFILES_DIR"/*; do
        if [ -d "$dir" ] && [[ $(basename "$dir") != .* ]]; then
            local pkg_name=$(basename "$dir")
            
            # Verificar si el paquete tiene symlinks activos
            if stow -n -D -t "$HOME" "$pkg_name" 2>&1 | grep -q "UNLINK"; then
                packages+=("$pkg_name")
                print_info "Encontrado instalado: $pkg_name"
            fi
        fi
    done
    
    echo "${packages[@]}"
}

# ============================================================================
# SELECCIÓN INTERACTIVA
# ============================================================================

select_packages() {
    local all_packages=($1)
    local selected_packages=()
    
    print_header "Selección de paquetes a desinstalar"
    
    if [ ${#all_packages[@]} -eq 0 ]; then
        print_warning "No se detectaron paquetes instalados"
        exit 0
    fi
    
    echo "Paquetes instalados:"
    echo ""
    
    for i in "${!all_packages[@]}"; do
        echo "  $((i+1)). ${all_packages[$i]}"
    done
    
    echo ""
    echo "Opciones:"
    echo "  a) Desinstalar todos"
    echo "  n) Números separados por espacios (ej: 1 3 5)"
    echo "  q) Cancelar"
    echo ""
    
    read -p "Tu elección: " choice
    
    case "$choice" in
        a|A)
            selected_packages=("${all_packages[@]}")
            print_success "Seleccionados todos los paquetes"
            ;;
        q|Q)
            print_warning "Desinstalación cancelada"
            exit 0
            ;;
        *)
            for num in $choice; do
                if [[ $num =~ ^[0-9]+$ ]] && [ $num -ge 1 ] && [ $num -le ${#all_packages[@]} ]; then
                    selected_packages+=("${all_packages[$((num-1))]}")
                else
                    print_warning "Opción inválida: $num"
                fi
            done
            ;;
    esac
    
    if [ ${#selected_packages[@]} -eq 0 ]; then
        print_error "No se seleccionó ningún paquete"
        exit 1
    fi
    
    echo ""
    print_info "Paquetes seleccionados: ${selected_packages[*]}"
    echo ""
    
    echo "${selected_packages[@]}"
}

# ============================================================================
# DESINSTALACIÓN
# ============================================================================

uninstall_packages() {
    local packages=($1)
    
    print_header "Desinstalando paquetes"
    
    cd "$DOTFILES_DIR"
    
    local uninstalled=()
    local failed=()
    
    for package in "${packages[@]}"; do
        print_info "Desinstalando: $package"
        
        if stow -v -D -t "$HOME" "$package" 2>&1 | while IFS= read -r line; do echo "  $line"; done; then
            uninstalled+=("$package")
            print_success "✓ $package desinstalado correctamente"
        else
            failed+=("$package")
            print_error "✗ Error al desinstalar $package"
        fi
        echo ""
    done
    
    # Resumen
    print_header "Resumen de desinstalación"
    
    if [ ${#uninstalled[@]} -gt 0 ]; then
        print_success "Desinstalados (${#uninstalled[@]}): ${uninstalled[*]}"
    fi
    
    if [ ${#failed[@]} -gt 0 ]; then
        print_error "Fallidos (${#failed[@]}): ${failed[*]}"
    fi
}

# ============================================================================
# RESTAURACIÓN DE BACKUP
# ============================================================================

restore_backup() {
    local backup_dir=$1
    
    if [ "$backup_dir" == "none" ] || [ ! -d "$backup_dir" ]; then
        print_info "No hay backup disponible para restaurar"
        return
    fi
    
    print_header "Restauración de backup"
    
    echo ""
    print_warning "Se encontró un backup en: $backup_dir"
    echo ""
    read -p "¿Deseas restaurar los archivos del backup? (s/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        print_info "Restauración omitida"
        return
    fi
    
    print_info "Restaurando archivos..."
    
    local restored=0
    
    # Copiar archivos del backup al HOME
    if [ -d "$backup_dir$HOME" ]; then
        cp -rv "$backup_dir$HOME/." "$HOME/" 2>&1 | while IFS= read -r line; do
            echo "  $line"
            ((restored++))
        done
        print_success "Backup restaurado correctamente"
    else
        print_warning "No se encontraron archivos para restaurar"
    fi
}

# ============================================================================
# LIMPIEZA COMPLETA
# ============================================================================

clean_all() {
    local backup_dir=$1
    
    print_header "Limpieza completa"
    
    echo ""
    print_warning "Esto eliminará:"
    echo "  - Metadata de instalación (.install_metadata)"
    if [ "$backup_dir" != "none" ] && [ -d "$backup_dir" ]; then
        echo "  - Directorio de backup: $backup_dir"
    fi
    echo ""
    
    read -p "¿Deseas realizar la limpieza completa? (s/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        print_info "Limpieza completa omitida"
        return
    fi
    
    # Eliminar metadata
    if [ -f "$METADATA_FILE" ]; then
        rm -f "$METADATA_FILE"
        print_success "Metadata eliminada"
    fi
    
    # Eliminar backup
    if [ "$backup_dir" != "none" ] && [ -d "$backup_dir" ]; then
        rm -rf "$backup_dir"
        print_success "Backup eliminado: $backup_dir"
    fi
    
    print_success "Limpieza completa finalizada"
}

# ============================================================================
# VERIFICACIÓN DE RASTROS
# ============================================================================

check_traces() {
    print_header "Verificación de rastros"
    
    local traces_found=0
    
    print_info "Buscando posibles rastros..."
    
    # Verificar symlinks rotos en HOME
    print_info "Verificando symlinks en HOME..."
    while IFS= read -r symlink; do
        if [ -L "$symlink" ] && [ ! -e "$symlink" ]; then
            print_warning "Symlink roto encontrado: $symlink"
            ((traces_found++))
        fi
    done < <(find "$HOME" -maxdepth 3 -type l 2>/dev/null)
    
    # Verificar archivos .stow-* 
    if find "$HOME" -maxdepth 2 -name ".stow-*" 2>/dev/null | grep -q .; then
        print_warning "Archivos .stow-* encontrados en HOME"
        find "$HOME" -maxdepth 2 -name ".stow-*" 2>/dev/null | while read -r file; do
            echo "  $file"
            ((traces_found++))
        done
    fi
    
    if [ $traces_found -eq 0 ]; then
        print_success "No se encontraron rastros. Sistema limpio ✨"
    else
        print_warning "Se encontraron $traces_found posible(s) rastro(s)"
        echo ""
        read -p "¿Deseas limpiar estos rastros? (s/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            # Eliminar symlinks rotos
            find "$HOME" -maxdepth 3 -type l 2>/dev/null | while read -r symlink; do
                if [ ! -e "$symlink" ]; then
                    rm -f "$symlink"
                    print_info "Eliminado: $symlink"
                fi
            done
            # Eliminar archivos .stow-*
            find "$HOME" -maxdepth 2 -name ".stow-*" -delete 2>/dev/null
            print_success "Rastros eliminados"
        fi
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    clear
    print_header "🗑️  Desinstalador de Dotfiles"
    
    # Verificar que estamos en el directorio correcto
    if [ ! -d "$DOTFILES_DIR" ]; then
        print_error "Directorio $DOTFILES_DIR no encontrado"
        exit 1
    fi
    
    # Verificar stow
    if ! command -v stow &> /dev/null; then
        print_error "stow no está instalado"
        exit 1
    fi
    
    # 1. Leer metadata o detectar paquetes
    metadata=$(read_metadata)
    
    if [ "$metadata" == "none" ]; then
        print_warning "Usando detección automática de paquetes..."
        packages=$(detect_packages)
        backup_dir="none"
    else
        packages=$(echo "$metadata" | cut -d'|' -f1)
        backup_dir=$(echo "$metadata" | cut -d'|' -f2)
    fi
    
    if [ -z "$packages" ] || [ "$packages" == " " ]; then
        print_warning "No se encontraron paquetes para desinstalar"
        exit 0
    fi
    
    # 2. Selección interactiva
    selected_packages=$(select_packages "$packages")
    
    # 3. Confirmación final
    echo ""
    print_warning "Esta acción eliminará los symlinks de los paquetes seleccionados"
    read -p "¿Deseas continuar con la desinstalación? (s/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        print_warning "Desinstalación cancelada"
        exit 0
    fi
    
    # 4. Desinstalar paquetes
    uninstall_packages "$selected_packages"
    
    # 5. Restaurar backup (opcional)
    restore_backup "$backup_dir"
    
    # 6. Limpieza completa (opcional)
    clean_all "$backup_dir"
    
    # 7. Verificar rastros
    check_traces
    
    # 8. Mensaje final
    print_header "✅ Desinstalación completada"
    
    print_success "El sistema ha sido limpiado correctamente"
    echo ""
}

# Ejecutar
main
