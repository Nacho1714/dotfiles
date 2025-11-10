#!/bin/bash

set -Eeuo pipefail
trap 'print_error "Ocurrió un error inesperado en la línea $LINENO"; exit 1' ERR

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

DOTFILES_DIR="$HOME/dotfiles"
BACKUP_DIR="$HOME/dotfiles_backup_$(date +%Y%m%d_%H%M%S)"
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

# Función simple para debug
log() {
	echo "[DEBUG] $1"
}

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
# VERIFICACIÓN DE DEPENDENCIAS
# ============================================================================

check_dependencies() {
	print_header "Verificando dependencias"

	local missing_deps=()

	if ! command -v stow &> /dev/null; then
		missing_deps+=("stow")
		print_warning "stow no está instalado"
	else
		print_success "$(stow --version | head -n1)"
	fi

	if ! command -v git &> /dev/null; then
		print_warning "git no está instalado (recomendado para gestión de dotfiles)"
	else
		print_success "$(git --version)"
	fi

	if [[ ${#missing_deps[@]} -gt 0 ]]; then
		print_error "Dependencias faltantes: ${missing_deps[*]}"
		echo ""
		read -p "¿Deseas instalar las dependencias faltantes? (Y/n): " -n 1 -r
		echo ""
		if [[ -z $REPLY || $REPLY =~ ^[Yy]$ ]]; then
			install_dependencies "${missing_deps[@]}"
		else
			print_error "No se puede continuar sin las dependencias necesarias"
			exit 1
		fi
	fi
}

install_dependencies() {
	print_info "Instalando dependencias..."

    	if command -v apt-get &> /dev/null; then
        	sudo apt-get update
        	sudo apt-get install -y "$@"
    	elif command -v dnf &> /dev/null; then
        	sudo dnf install -y "$@"
    	elif command -v yum &> /dev/null; then
        	sudo yum install -y "$@"
    	elif command -v pacman &> /dev/null; then
        	sudo pacman -S --noconfirm "$@"
    	else
        	print_error "No se pudo detectar el gestor de paquetes"
        	exit 1
    	fi

	print_success "Dependencias instaladas correctamente"
}

# ============================================================================
# DETECCIÓN DE PAQUETES
# ============================================================================

detect_packages() {
	# IMPORTANTE: Los mensajes visuales van a stderr (&>2)
    	# Los datos a devolver van a stdout (sin redirección)

	print_header "Detectando paquetes disponibles" >&2

	local packages=()

	for dir in "$DOTFILES_DIR"/*; do
        	if [[ -d "$dir" && $(basename "$dir") != .* ]]; then
            		local pkg_name
            		pkg_name=$(basename "$dir")
            		packages+=("$pkg_name")
            		print_info "Encontrado: $pkg_name" >&2
        	fi
    	done

	if [[ ${#packages[@]} -eq 0 ]]; then
        	print_error "No se encontraron paquetes en: $DOTFILES_DIR" >&2
        	exit 1
    	fi

	# Solo los nombres de paquetes van a stdout (salida limpia)
    	printf "%s\n" "${packages[@]}"
}

# ============================================================================
# SELECCIÓN INTERACTIVA
# ============================================================================

select_packages() {
	# IMPORTANTE: Los mensajes visuales van a stderr (&>2)
    	# Los datos a devolver van a stdout (sin redirección)

	local all_packages=("$@")
    	local selected_packages=()

	print_header "Selección de paquetes" >&2

	echo "Paquetes disponibles:" >&2
	echo "" >&2

	for i in "${!all_packages[@]}"; do
        	echo "  $((i + 1)). ${all_packages[$i]}" >&2
    	done

	echo "" >&2
    	echo "Opciones:" >&2
    	echo "  a) Instalar todos" >&2
    	echo "  n) Ingresar números separados por espacios (ej: 1 3 5)" >&2
    	echo "  q) Cancelar" >&2
    	echo "" >&2

	read -rp "Tu elección: " choice >&2
    	echo "" >&2

    	case "$choice" in
        	a|A)
            		selected_packages=("${all_packages[@]}")
            		print_success "Seleccionados todos los paquetes" >&2
            		;;
        	q|Q)
            		print_warning "Instalación cancelada" >&2
            		exit 0
            		;;
        	*)
            		for num in $choice; do
                		if [[ $num =~ ^[0-9]+$ && $num -ge 1 && $num -le ${#all_packages[@]} ]]; then
                    			pkg="${all_packages[$((num - 1))]}"

                    			# Verificar si ya está en el array antes de agregar
                    			if [[ ! " ${selected_packages[*]} " =~ " $pkg " ]]; then
                        			selected_packages+=("$pkg")
                    			else
                        			print_warning "Paquete ya seleccionado: $pkg" >&2
                    			fi
                		else
                    			print_warning "Opción inválida: $num" >&2
                		fi
            		done
            		;;
    	esac

    	if [[ ${#selected_packages[@]} -eq 0 ]]; then
        	print_error "No se seleccionó ningún paquete" >&2
        	exit 1
    	fi

    	echo "" >&2
    	print_info "Paquetes seleccionados: ${selected_packages[*]}" >&2
    	echo "" >&2


    	# Solo los nombres seleccionados van a stdout (salida limpia)
    	printf "%s\n" "${selected_packages[@]}"
}

# ============================================================================
# SISTEMA DE BACKUP
# ============================================================================

create_backup() {
    print_header "Creando backup" >&2

    local packages=("$@")
    local files_backed_up=0
    local stow_dir="${PWD}"  # Directorio desde donde se ejecuta (~/dotfiles)

    # Validar que estamos en el directorio correcto
    if [[ ! -d "$stow_dir" ]]; then
        print_error "Directorio stow no válido: $stow_dir" >&2
        echo "error"
        return 1
    fi

    mkdir -p "$BACKUP_DIR"

    for package in "${packages[@]}"; do
        local package_path="$stow_dir/$package"

        # Verificar que el paquete existe
        if [[ ! -d "$package_path" ]]; then
            print_warning "Paquete no encontrado: $package" >&2
            continue
        fi

        print_info "Analizando conflictos de: $package" >&2

        # Recorrer recursivamente todos los archivos y directorios del paquete
        while IFS= read -r -d '' source_item; do
            # Calcular ruta relativa al paquete (quitando el prefijo del paquete)
            local rel_path="${source_item#$package_path/}"
            
            # Ruta destino en $HOME
            local target_path="$HOME/$rel_path"

            # Verificar si existe algo en el destino
            if [[ -e "$target_path" || -L "$target_path" ]]; then
                # Verificar si es un symlink que apunta correctamente a nuestro paquete
                if [[ -L "$target_path" ]]; then
                    local link_target
                    link_target=$(readlink "$target_path")
                    local absolute_link_target
                    absolute_link_target=$(cd "$(dirname "$target_path")" && cd "$(dirname "$link_target")" 2>/dev/null && pwd)/$(basename "$link_target")
                    
                    # Si el symlink ya apunta a nuestro paquete, no hay conflicto
                    if [[ "$absolute_link_target" == "$source_item" ]]; then
                        continue
                    fi
                fi

                # HAY CONFLICTO: el destino existe y no es nuestro symlink correcto
                print_info "Respaldando: $target_path" >&2

                # Calcular ruta de backup
                local backup_path="$BACKUP_DIR/$(dirname "$rel_path")"
                mkdir -p "$backup_path"

                # Respaldar preservando todo (symlinks, permisos, timestamps)
                if cp -a "$target_path" "$backup_path/" 2>/dev/null; then
                    ((files_backed_up++)) || true

					# Eliminar el archivo/directorio conflictivo para que stow pueda trabajar
					if [[ -f "$target_path" || -L "$target_path" ]]; then
						print_info "  → Eliminado: $target_path" >&2
					else
						print_warning "  → No se pudo eliminar: $target_path" >&2
					fi
                else
                    print_warning "No se pudo respaldar: $target_path" >&2
                fi
            fi

		done < <(find "$package_path" -type f -print0)  # CORRECCIÓN: Solo buscar archivos (-type f)

    done

    # Resultado final a stdout
    if [[ $files_backed_up -eq 0 ]]; then
        print_info "No hay archivos para respaldar" >&2
        rmdir "$BACKUP_DIR" 2>/dev/null || true
        echo "none"
    else
        print_success "Backup completado: $files_backed_up objeto(s) respaldado(s)" >&2
        echo "$BACKUP_DIR"
    fi
}

# ============================================================================
# INSTALACIÓN
# ============================================================================

install_packages() {
    print_header "Instalando paquetes"

    local backup_dir="${!#}"
    local packages=("${@:1:$(( $# - 1 ))}")

    local installed=()
    local failed=()

    cd "$DOTFILES_DIR"

    for package in "${packages[@]}"; do
        print_info "Instalando: $package"

        local stow_output
        local stow_status
        
        stow_output=$(stow -v -t "$HOME" "$package" 2>&1)
        stow_status=$?
        
        # Mostrar output indentado
        while IFS= read -r line; do
            echo "  $line"
        done <<< "$stow_output"

        if [ $stow_status -eq 0 ]; then
            installed+=("$package")
            print_success "✓ $package instalado correctamente"
        else
            failed+=("$package")
            print_error "✗ Error al instalar $package"
        fi
        echo ""
    done

    if [ ${#installed[@]} -gt 0 ]; then
        save_metadata "$backup_dir" "${installed[@]}"
    fi

    print_header "Resumen de instalación"

    if [ ${#installed[@]} -gt 0 ]; then
        print_success "Instalados (${#installed[@]}): ${installed[*]}"
    fi

    if [ ${#failed[@]} -gt 0 ]; then
        print_error "Fallidos (${#failed[@]}): ${failed[*]}"
    fi
}

# ============================================================================
# METADATA
# ============================================================================

save_metadata() {
    local backup_dir=$1
    shift
    local packages=("$@")

    print_header "Guardando metadata de instalación"

    if ! cat > "$METADATA_FILE" << EOF
# Metadata de instalación
# Generado: $(date)
INSTALL_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=$backup_dir
INSTALLED_PACKAGES=${packages[*]}
EOF
    then
        print_error "No se pudo guardar metadata en $METADATA_FILE"
        return 1
    fi

    print_success "Metadata guardada correctamente"
}

# ============================================================================
# MAIN
# ============================================================================

main() {

	[[ -t 1 ]] && clear
	print_header "🚀 Instalador de Dotfiles"

	if [ ! -d "$DOTFILES_DIR" ]; then
		print_error "Directorio $DOTFILES_DIR no encontrado"
		exit 1
	fi

	# 1. Verificar dependencias
	check_dependencies

	# 2. Detectar paquetes disponibles
	mapfile -t all_packages < <(detect_packages)

	# 3. Selección interactiva
	mapfile -t selected_packages < <(select_packages "${all_packages[@]}")

	# 4. Confirmación final
	echo ""
	read -p "¿Deseas continuar con la instalación? (Y/n): " -n 1 -r
	echo ""
	if [[ -n "$REPLY" && ! "$REPLY" =~ ^[Yy]$ ]]; then
		print_warning "Instalación cancelada"
		exit 0
	fi

	# 5. Crear backup
	backup_location=$(create_backup "${selected_packages[@]}")

	# 6. Instalar paquetes
    install_packages "${selected_packages[@]}" "$backup_location"

	# 7. Mensaje final
    print_header "✅ Instalación completada"

    echo ""
    print_info "Para aplicar los cambios ejecuta:"
    echo -e "  ${CYAN}source ~/.bashrc${NC}"
    echo ""

    # Mostrar backup solo si existe
    if [[ "$backup_location" != "none" ]]; then
        print_info "Backup guardado en:"
        echo -e "  ${CYAN}$backup_location${NC}"
        echo ""
    fi

    print_info "Para desinstalar ejecuta:"
    echo -e "  ${CYAN}./uninstall.sh${NC}"
    echo ""
}

# Ejecutar
main