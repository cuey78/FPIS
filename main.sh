#!/bin/bash

#########################################################################################
#                                                                                       #
# Fedora Post-Install Script (Modernized)                                               #
#                                                                                       #
# Features:                                                                             #
#   - TOML-based configuration system                                                   #
#   - Command-line flags for control                                                    #
#   - Parallel package installation                                                     #
#   - Cached metadata for faster startup                                                #
#   - Modular plugin system with categories                                             #
#                                                                                       #
# Usage:                                                                                #
#   ./main.sh [--no-checks] [--no-banner] [--cache-dir DIR] [--config FILE]             #
#                                                                                       #
# Author: cuey                                                                          #
#                                                                                       #
#########################################################################################

# Global variables
declare -A PLUGIN_MENU_ITEMS
declare -A PLUGIN_CATEGORIES
declare -a PLUGIN_MENU_ORDER
declare -A MENU_CATEGORY_NAMES
declare -r SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -r VERSION="2.0.0"

# Default configuration
CONFIG_FILE="${SCRIPT_DIR}/config.toml"
CACHE_DIR="${SCRIPT_DIR}/.cache"
SKIP_CHECKS=false
SHOW_BANNER=true
PARALLEL_INSTALL=true
MAX_JOBS=4

# Color codes
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_WHITE='\033[1;37m'
readonly COLOR_RESET='\033[0m'

# Load menu categories from config
load_menu_categories() {
    echo -e "${COLOR_CYAN}[DEBUG] Loading menu categories from config...${COLOR_RESET}"
    
    # Clear previous categories
    declare -gA MENU_CATEGORY_NAMES
    MENU_CATEGORY_NAMES=()
    
    # Parse menu_categories section from TOML
    local in_menu_categories=false
    while IFS= read -r line; do
        # Check if we're in the menu_categories section
        if [[ "$line" =~ ^\[menu_categories\] ]]; then
            in_menu_categories=true
            continue
        elif [[ "$line" =~ ^\[ ]] && [[ "$in_menu_categories" == true ]]; then
            # We've moved to another section
            break
        fi
        
        # Parse category lines: "1 = "Main Tools""
        if [[ "$in_menu_categories" == true ]] && [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
            local category_num="${BASH_REMATCH[1]}"
            local category_name="${BASH_REMATCH[2]}"
            MENU_CATEGORY_NAMES["$category_num"]="$category_name"
            echo -e "${COLOR_CYAN}[DEBUG] Loaded category: $category_num = '$category_name'${COLOR_RESET}"
        fi
    done < "$CONFIG_FILE"
    
    # Ensure at least category 1 exists
    if [[ -z "${MENU_CATEGORY_NAMES[1]}" ]]; then
        MENU_CATEGORY_NAMES[1]="Main Tools"
        echo -e "${COLOR_YELLOW}[WARN] No category 1 found in config, using default${COLOR_RESET}"
    fi
    
    echo -e "${COLOR_CYAN}[DEBUG] Loaded ${#MENU_CATEGORY_NAMES[@]} menu categories${COLOR_RESET}"
}

# Initialize configuration
init_config() {
    echo -e "${COLOR_CYAN}[DEBUG] Initializing configuration...${COLOR_RESET}"
    
    # Create config file if it doesn't exist
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
[script]
name = "Fedora Post-Install Script"
version = "2.0.0"
author = "cuey"
repository = "https://github.com/cuey78/Fedora-Post-Install"

[settings]
cache_dir = ".cache"
parallel_install = true
max_jobs = 4
log_file = "fedora-post-install.log"

[dependencies]
required = ["dialog"]

[ui]
banner_color = "cyan"
menu_color = "blue"
progress_color = "green"

[plugins]
directory = "plugins"
pattern = "*.sh"

[menu_categories]
1 = "Main Tools"
2 = "Utilities"
3 = "Advanced Features"
4 = "Development"
EOF
        log_info "Created default configuration: $CONFIG_FILE"
    fi
    
    # Load configuration using simple parsing
    if [[ -f "$CONFIG_FILE" ]]; then
        CONFIG_SCRIPT_NAME=$(grep 'name\s*=' "$CONFIG_FILE" | head -1 | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/' || echo "Fedora Post-Install Script")
        CONFIG_CACHE_DIR=$(grep 'cache_dir\s*=' "$CONFIG_FILE" | head -1 | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/' || echo ".cache")
        CONFIG_LOG_FILE=$(grep 'log_file\s*=' "$CONFIG_FILE" | head -1 | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/' || echo "fedora-post-install.log")
        CONFIG_PLUGINS_DIR=$(grep 'directory\s*=' "$CONFIG_FILE" | head -1 | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/' || echo "plugins")
        CONFIG_PLUGINS_PATTERN=$(grep 'pattern\s*=' "$CONFIG_FILE" | head -1 | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/' || echo "*.sh")
        
        # Load menu categories from config
        load_menu_categories
    fi
    
    CACHE_DIR="${SCRIPT_DIR}/${CONFIG_CACHE_DIR}"
    mkdir -p "$CACHE_DIR"
    log_info "Configuration loaded from: $CONFIG_FILE"
    echo -e "${COLOR_CYAN}[DEBUG] Config: plugins_dir=${CONFIG_PLUGINS_DIR}, pattern=${CONFIG_PLUGINS_PATTERN}${COLOR_RESET}"
}

# Parse command line arguments
parse_args() {
    echo -e "${COLOR_CYAN}[DEBUG] Parsing command line arguments...${COLOR_RESET}"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-checks)
                SKIP_CHECKS=true
                shift
                ;;
            --no-banner)
                SHOW_BANNER=false
                shift
                ;;
            --cache-dir)
                CACHE_DIR="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL_INSTALL=true
                shift
                ;;
            --no-parallel)
                PARALLEL_INSTALL=false
                shift
                ;;
            -v|--version)
                echo "Fedora Post-Install Script v${VERSION}"
                exit 0
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --no-checks       Skip dependency checks
  --no-banner       Don't show banner on startup
  --cache-dir DIR   Use custom cache directory
  --config FILE     Use custom config file
  --parallel        Enable parallel installation (default)
  --no-parallel     Disable parallel installation
  -v, --version     Show version information
  -h, --help        Show this help message

Examples:
  $0 --no-checks --no-banner
  $0 --cache-dir /tmp/cache --config custom.toml
EOF
}

# Modern banner with dynamic sizing
banner() {
    [[ "$SHOW_BANNER" == "false" ]] && return
    
    local color1="$COLOR_CYAN"
    local color2="$COLOR_BLUE"
    local term_width=$(tput cols)
    local padding=$(printf '%*s' $(( (term_width - 58) / 2 )) '')
    
    clear
    echo -e "${color1}${padding}╔══════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${color1}${padding}║${color2}           Fedora Post-Install Script v${VERSION}${color1}              ║${COLOR_RESET}"
    echo -e "${color1}${padding}║${color2}                       2025 Edition${color1}                       ║${COLOR_RESET}"
    echo -e "${color1}${padding}╚══════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo -e "${padding}         ${COLOR_WHITE}Fast • Modular • Configurable • Reliable${COLOR_RESET}"
    echo -e "${padding}       ${color2}https://github.com/cuey78/Fedora-Post-Install${COLOR_RESET}"
    echo
    sleep 2
}

# Enhanced logging system
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="$timestamp - [$level] - $message"
    
    echo "$log_entry" >> "${CONFIG_LOG_FILE:-fedora-post-install.log}"
    
    case "$level" in
        "INFO") echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $message" ;;
        "WARN") echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $message" ;;
        "ERROR") echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $message" ;;
        "DEBUG") [[ "${DEBUG:-false}" == "true" ]] && echo -e "${COLOR_CYAN}[DEBUG]${COLOR_RESET} $message" ;;
    esac
}

log_info() { log "INFO" "$1"; }
log_warn() { log "WARN" "$1"; }
log_error() { log "ERROR" "$1"; }
log_debug() { log "DEBUG" "$1"; }

# Fast dependency checker
check_dependencies() {
    [[ "$SKIP_CHECKS" == "true" ]] && return
    
    echo -e "${COLOR_CYAN}[DEBUG] Checking dependencies...${COLOR_RESET}"
    local deps=("dialog")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null && ! rpm -q "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "Installing missing dependencies: ${missing[*]}"
        install_packages "${missing[@]}"
    else
        echo -e "${COLOR_CYAN}[DEBUG] All dependencies are satisfied${COLOR_RESET}"
    fi
}

# Package installer
install_packages() {
    local packages=("$@")
    log_info "Installing packages: ${packages[*]}"
    
    if dnf install -y --skip-broken "${packages[@]}"; then
        log_info "Successfully installed packages: ${packages[*]}"
        return 0
    else
        log_error "Failed to install packages: ${packages[*]}"
        return 1
    fi
}

# Enhanced metadata extractor - supports both old and new formats
extract_plugin_metadata() {
    local file="$1"
    local menu_title=""
    local menu_function=""
    local menu_order=""
    local menu_category="1"  # Default to category 1 (Main Tools)
    
    # Read the file line by line to extract metadata
    while IFS= read -r line; do
        # NEW FORMAT: TOML-style in comments
        # menu_title = "Title"
        if [[ "$line" =~ [[:space:]]*#.*menu_title[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
            menu_title="${BASH_REMATCH[1]}"
            continue
        fi
        if [[ "$line" =~ [[:space:]]*#.*menu_function[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
            menu_function="${BASH_REMATCH[1]}"
            continue
        fi
        if [[ "$line" =~ [[:space:]]*#.*menu_order[[:space:]]*=[[:space:]]*([0-9]+) ]]; then
            menu_order="${BASH_REMATCH[1]}"
            continue
        fi
        if [[ "$line" =~ [[:space:]]*#.*menu_category[[:space:]]*=[[:space:]]*([0-9]+) ]]; then
            menu_category="${BASH_REMATCH[1]}"
            continue
        fi
        
        # OLD FORMAT: MENU_TITLE: "Title"
        if [[ "$line" =~ MENU_TITLE:[[:space:]]*\"([^\"]+)\" ]]; then
            menu_title="${BASH_REMATCH[1]}"
            continue
        fi
        if [[ "$line" =~ MENU_FUNCTION:[[:space:]]*([a-zA_Z_][a-zA-Z0-9_]*) ]]; then
            menu_function="${BASH_REMATCH[1]}"
            continue
        fi
        if [[ "$line" =~ MENU_ORDER:[[:space:]]*([0-9]+) ]]; then
            menu_order="${BASH_REMATCH[1]}"
            continue
        fi
        
        # Stop reading if we've found all metadata and hit a function definition
        if [[ -n "$menu_function" && "$line" =~ ^$menu_function\(\) ]]; then
            break
        fi
    done < "$file"
    
    echo "$menu_title|$menu_function|$menu_order|$menu_category"
}

# Create a sample plugin if none exist
create_sample_plugin() {
    local plugins_dir="${SCRIPT_DIR}/${CONFIG_PLUGINS_DIR:-plugins}"
    local sample_plugin="$plugins_dir/example.sh"
    
    log_info "Creating sample plugin: $sample_plugin"
    
    cat > "$sample_plugin" << 'EOF'
#!/bin/bash

# Plugin metadata (new format)
# menu_title = "Install Development Tools"
# menu_function = "install_dev_tools" 
# menu_order = 100
# menu_category = 1

install_dev_tools() {
    log_info "Installing development tools..."
    
    local packages=(
        "git"
        "vim"
    )
    
    if install_packages "${packages[@]}"; then
        log_info "Development tools installed successfully"
        dialog --msgbox "Development tools installed successfully!" 10 50
    else
        log_error "Failed to install development tools"
        dialog --msgbox "Error installing development tools!" 10 50
    fi
}
EOF
    chmod +x "$sample_plugin"
    log_info "Sample plugin created: $sample_plugin"
    
    # Process the new sample plugin
    process_plugin_file "$sample_plugin"
}

# Convert old format plugins to new format
convert_old_plugins() {
    local plugins_dir="${SCRIPT_DIR}/${CONFIG_PLUGINS_DIR:-plugins}"
    local pattern="${CONFIG_PLUGINS_PATTERN:-*.sh}"
    local converted_count=0
    
    echo -e "${COLOR_CYAN}[DEBUG] Attempting to convert old plugin format...${COLOR_RESET}"
    
    for file in "$plugins_dir"/$pattern; do
        [[ -f "$file" ]] || continue
        
        local old_metadata=$(extract_plugin_metadata "$file")
        local menu_title=$(echo "$old_metadata" | cut -d'|' -f1)
        local menu_function=$(echo "$old_metadata" | cut -d'|' -f2)
        local menu_order=$(echo "$old_metadata" | cut -d'|' -f3)
        local menu_category=$(echo "$old_metadata" | cut -d'|' -f4)
        
        # If we found old format metadata but no new format, add new format
        if [[ -n "$menu_title" && -n "$menu_function" ]]; then
            echo -e "${COLOR_YELLOW}[CONVERT] Converting $(basename "$file") to new format${COLOR_RESET}"
            
            # Create a temporary file with new metadata
            local temp_file="${file}.new"
            local converted=false
            
            # Read original file and add new metadata
            while IFS= read -r line; do
                # Add new metadata after the shebang
                if [[ "$line" =~ ^#!/bin/bash ]] && ! $converted; then
                    echo "$line" > "$temp_file"
                    echo "" >> "$temp_file"
                    echo "# Plugin metadata (new format)" >> "$temp_file"
                    echo "# menu_title = \"$menu_title\"" >> "$temp_file"
                    echo "# menu_function = \"$menu_function\"" >> "$temp_file"
                    [[ -n "$menu_order" ]] && echo "# menu_order = $menu_order" >> "$temp_file"
                    echo "# menu_category = $menu_category" >> "$temp_file"
                    echo "" >> "$temp_file"
                    converted=true
                else
                    echo "$line" >> "$temp_file"
                fi
            done < "$file"
            
            # Replace original file
            if mv "$temp_file" "$file"; then
                log_info "Converted $(basename "$file") to new metadata format"
                ((converted_count++))
                
                # Now process the converted file
                process_plugin_file "$file"
            else
                log_error "Failed to convert $(basename "$file")"
            fi
        fi
    done
    
    if [[ $converted_count -gt 0 ]]; then
        log_info "Successfully converted $converted_count plugins to new format"
    else
        log_warn "No old format plugins found to convert"
        create_sample_plugin
    fi
}

process_plugin_file() {
    local file="$1"
    echo -e "${COLOR_CYAN}[DEBUG] Processing plugin: $(basename "$file")${COLOR_RESET}"
    
    local metadata
    metadata=$(extract_plugin_metadata "$file")
    local menu_title=$(echo "$metadata" | cut -d'|' -f1)
    local menu_function=$(echo "$metadata" | cut -d'|' -f2)
    local menu_order=$(echo "$metadata" | cut -d'|' -f3)
    local menu_category=$(echo "$metadata" | cut -d'|' -f4)
    
    echo -e "${COLOR_CYAN}[DEBUG] Metadata - Title: '$menu_title', Function: '$menu_function', Order: '$menu_order', Category: '$menu_category'${COLOR_RESET}"
    
    if [[ -n "$menu_title" && -n "$menu_function" ]]; then
        menu_order=${menu_order:-9999}
        menu_category=${menu_category:-1}  # Default to category 1
        
        # Source the plugin file (ALL plugins are sourced, even category 0)
        if source "$file"; then
            # Verify the function exists
            if declare -f "$menu_function" > /dev/null; then
                # Only add to menu if category is not 0 (hidden)
                if [[ "$menu_category" != "0" ]]; then
                    # Store in category-based arrays
                    local category_key="${menu_category}_${menu_order}"
                    PLUGIN_MENU_ITEMS["$category_key"]="$menu_function|$menu_title|$menu_category"
                    PLUGIN_MENU_ORDER+=("$category_key")
                    log_info "Loaded plugin: $menu_title (Category: $menu_category)"
                else
                    log_info "Loaded hidden plugin: $menu_title (Category: $menu_category - not in menu)"
                fi
                return 0
            else
                log_error "Function '$menu_function' not found in $file"
            fi
        else
            log_error "Failed to source plugin: $file"
        fi
    else
        log_warn "Invalid metadata in plugin: $(basename "$file")"
    fi
    return 1
}

# Plugin loader
load_plugins() {
    local plugins_dir="${SCRIPT_DIR}/${CONFIG_PLUGINS_DIR:-plugins}"
    local pattern="${CONFIG_PLUGINS_PATTERN:-*.sh}"
    
    echo -e "${COLOR_CYAN}[DEBUG] Loading plugins from: $plugins_dir${COLOR_RESET}"
    
    # Check if plugins directory exists
    if [[ ! -d "$plugins_dir" ]]; then
        log_warn "Plugins directory not found: $plugins_dir"
        log_info "Creating plugins directory..."
        mkdir -p "$plugins_dir"
        create_sample_plugin
    fi
    
    # Get plugin files
    local plugin_files=()
    if [[ -d "$plugins_dir" ]]; then
        for file in "$plugins_dir"/$pattern; do
            [[ -f "$file" ]] && plugin_files+=("$file")
        done
    fi
    
    if [[ ${#plugin_files[@]} -eq 0 ]]; then
        log_warn "No plugin files found in $plugins_dir"
        create_sample_plugin
        # Refresh plugin files list
        for file in "$plugins_dir"/$pattern; do
            [[ -f "$file" ]] && plugin_files+=("$file")
        done
    fi
    
    log_info "Found ${#plugin_files[@]} plugin files in: $plugins_dir"
    
    # Clear previous menu items
    PLUGIN_MENU_ITEMS=()
    PLUGIN_MENU_ORDER=()
    
    # Process plugins
    local loaded_count=0
    for file in "${plugin_files[@]}"; do
        if [[ -f "$file" ]]; then
            if process_plugin_file "$file"; then
                ((loaded_count++))
            fi
        fi
    done
    
    log_info "Successfully loaded ${loaded_count} plugins"
    echo -e "${COLOR_CYAN}[DEBUG] Plugin menu items: ${loaded_count}${COLOR_RESET}"
    
    # If no plugins loaded with new format, try to convert old plugins
    if [[ $loaded_count -eq 0 ]]; then
        log_info "No plugins with new metadata format found, checking for old format..."
        convert_old_plugins
    fi
}



# Show menu for a specific category
show_category_menu() {
    local category_num="$1"
    local category_name="${MENU_CATEGORY_NAMES[$category_num]:-Category $category_num}"
    
    echo -e "${COLOR_CYAN}[DEBUG] Showing menu for category $category_num: $category_name${COLOR_RESET}"
    
    # Build menu options for this category, sorted by menu_order
    local options=()
    local -A category_functions
    
    # First, collect all plugins for this category with their order
    local -A plugin_orders
    local -A plugin_titles
    local -A plugin_functions
    
    for category_key in "${PLUGIN_MENU_ORDER[@]}"; do
        local item_data="${PLUGIN_MENU_ITEMS[$category_key]}"
        local function_name=$(echo "$item_data" | cut -d'|' -f1)
        local title=$(echo "$item_data" | cut -d'|' -f2)
        local item_category=$(echo "$item_data" | cut -d'|' -f3)
        
        # Extract the order from the category_key (format: category_order)
        local order="${category_key#*_}"
        
        if [[ "$item_category" == "$category_num" ]]; then
            plugin_orders["$function_name"]="$order"
            plugin_titles["$function_name"]="$title"
            plugin_functions["$function_name"]="$function_name"
            echo -e "${COLOR_CYAN}[DEBUG] Found plugin: $title (order: $order)${COLOR_RESET}"
        fi
    done
    
    # Sort plugins by menu_order
    local index=1
    while IFS= read -r function_name; do
        if [[ -n "$function_name" ]]; then
            options+=("$index" "${plugin_titles[$function_name]}")
            category_functions["$index"]="$function_name"
            echo -e "${COLOR_CYAN}[DEBUG] Sorted option $index: ${plugin_titles[$function_name]} -> $function_name (order: ${plugin_orders[$function_name]})${COLOR_RESET}"
            ((index++))
        fi
    done < <(
        for func in "${!plugin_orders[@]}"; do
            printf "%s\t%s\n" "${plugin_orders[$func]}" "$func"
        done | sort -n | cut -f2
    )
    
    if [[ ${#options[@]} -eq 0 ]]; then
        echo -e "${COLOR_YELLOW}No plugins found in category $category_num${COLOR_RESET}"
        read -p "Press Enter to return to category selection..."
        return 0
    fi
    
    # Only show "Back to Categories" if we're NOT in category 1 (main category)
    if [[ "$category_num" != "1" ]]; then
        options+=("B" "Back to Categories")
    fi
    
    options+=("Q" "Quit")
    
    while true; do
        choice=$(dialog --clear \
            --title "Fedora Post-Install Script - $category_name" \
            --menu "Please choose an option:" \
            20 60 10 \
            "${options[@]}" \
            2>&1 >/dev/tty)
        
        local result=$?
        echo -e "${COLOR_CYAN}[DEBUG] Category menu returned: choice='$choice', result='$result'${COLOR_RESET}"
        
        if [[ $result -ne 0 ]]; then
            echo -e "${COLOR_YELLOW}Dialog was cancelled, returning to categories...${COLOR_RESET}"
            return 0
        fi
        
        case "$choice" in
            Q|q)
                echo -e "${COLOR_GREEN}Goodbye!${COLOR_RESET}"
                return 1
                ;;
            B|b)
                # Only allow Back if we're NOT in category 1
                if [[ "$category_num" != "1" ]]; then
                    echo -e "${COLOR_YELLOW}Returning to category selection...${COLOR_RESET}"
                    return 0
                else
                    echo -e "${COLOR_RED}Invalid input!${COLOR_RESET}"
                    read -p "Press Enter to continue..."
                fi
                ;;
            [0-9]*)
                # Calculate total items correctly based on whether Back option is present
                local total_items
                if [[ "$category_num" == "1" ]]; then
                    total_items=$(( (${#options[@]} - 2) / 2 ))  # Only subtract Quit option
                else
                    total_items=$(( (${#options[@]} - 4) / 2 ))  # Subtract Back and Quit options
                fi
                
                if [[ $choice -ge 1 && $choice -le $total_items ]]; then
                    local function_to_call="${category_functions[$choice]}"
                    
                    echo -e "${COLOR_CYAN}[DEBUG] Calling function: $function_to_call${COLOR_RESET}"
                    
                    if declare -f "$function_to_call" > /dev/null; then
                        # Call the function
                        $function_to_call
                    else
                        echo -e "${COLOR_RED}Error: Function $function_to_call not found!${COLOR_RESET}"
                        read -p "Press Enter to continue..."
                    fi
                else
                    echo -e "${COLOR_RED}Invalid selection!${COLOR_RESET}"
                    read -p "Press Enter to continue..."
                fi
                ;;
            *)
                echo -e "${COLOR_RED}Invalid input!${COLOR_RESET}"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Show category selection menu
show_category_selection() {
    local categories=("$@")
    local options=()
    
    # Build category options
    for category_num in "${categories[@]}"; do
        local category_name="${MENU_CATEGORY_NAMES[$category_num]:-Category $category_num}"
        options+=("$category_num" "$category_name")
    done
    
    options+=("Q" "Quit")
    
    while true; do
        choice=$(dialog --clear \
            --title "Fedora Post-Install Script" \
            --menu "Please choose a category:" \
            20 60 10 \
            "${options[@]}" \
            2>&1 >/dev/tty)
        
        local result=$?
        echo -e "${COLOR_CYAN}[DEBUG] Category selection returned: choice='$choice', result='$result'${COLOR_RESET}"
        
        if [[ $result -ne 0 ]]; then
            echo -e "${COLOR_YELLOW}Dialog was cancelled, exiting...${COLOR_RESET}"
            break
        fi
        
        case "$choice" in
            Q|q)
                echo -e "${COLOR_GREEN}Goodbye!${COLOR_RESET}"
                return 1
                ;;
            [0-9]*)
                if [[ " ${categories[@]} " =~ " $choice " ]]; then
                    show_category_menu "$choice"
                    # After returning from category menu, show category selection again
                    # unless we're exiting completely
                    [[ $? -eq 0 ]] || break
                else
                    echo -e "${COLOR_RED}Invalid category selection!${COLOR_RESET}"
                    read -p "Press Enter to continue..."
                fi
                ;;
            *)
                echo -e "${COLOR_RED}Invalid input!${COLOR_RESET}"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Enhanced menu system with categories
show_menu() {
    echo -e "${COLOR_CYAN}[DEBUG] Entering show_menu function${COLOR_RESET}"
    
    # Check if we have any plugins
    if [[ ${#PLUGIN_MENU_ORDER[@]} -eq 0 ]]; then
        log_error "No plugins available for menu"
        echo -e "${COLOR_RED}Error: No plugins available!${COLOR_RESET}"
        echo "Please check that your plugins have proper metadata in the comments."
        echo "Example: # menu_title = \"Plugin Name\""
        echo "Press Enter to exit..."
        read -r
        return 1
    fi
    
    # First, show category selection if we have multiple categories
    local available_categories=()
    for category_key in "${PLUGIN_MENU_ORDER[@]}"; do
        local item_data="${PLUGIN_MENU_ITEMS[$category_key]}"
        local category_num=$(echo "$item_data" | cut -d'|' -f3)
        if [[ ! " ${available_categories[@]} " =~ " $category_num " ]]; then
            available_categories+=("$category_num")
        fi
    done
    
    # Sort categories numerically
    available_categories=($(printf '%s\n' "${available_categories[@]}" | sort -n))
    
    echo -e "${COLOR_CYAN}[DEBUG] Available categories: ${available_categories[*]}${COLOR_RESET}"
    
    # If only one category, skip category selection
    if [[ ${#available_categories[@]} -eq 1 ]]; then
        show_category_menu "${available_categories[0]}"
    else
        show_category_selection "${available_categories[@]}"
    fi
}

# Cleanup handler
cleanup() {
    local user
    user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}" || echo "root")
    local dir="$SCRIPT_DIR"
    
    log_info "Cleaning up permissions..."
    if chown -R "$user:$user" "$dir" "$CACHE_DIR" 2>/dev/null; then
        log_info "Cleanup completed"
    else
        log_warn "Cleanup had some permission issues"
    fi
}

# Signal handlers
setup_handlers() {
    trap cleanup EXIT
    trap 'echo -e "${COLOR_RED}Script interrupted${COLOR_RESET}"; cleanup; exit 1' INT TERM
}

# Main execution flow
main() {
    clear
    echo -e "${COLOR_CYAN}[DEBUG] Starting main function${COLOR_RESET}"
    setup_handlers
    parse_args "$@"
    init_config
    check_dependencies
    
    [[ "$SHOW_BANNER" == "true" ]] && banner
    load_plugins
    
    echo -e "${COLOR_CYAN}[DEBUG] About to call show_menu${COLOR_RESET}"
    show_menu
    echo -e "${COLOR_CYAN}[DEBUG] show_menu completed${COLOR_RESET}"
    
    log_info "Script completed successfully"
    echo -e "${COLOR_GREEN}Script completed successfully!${COLOR_RESET}"
}

# Entry point
if [[ $EUID -eq 0 ]]; then
    echo -e "${COLOR_CYAN}[DEBUG] Script started as root${COLOR_RESET}"
    main "$@"
else
    echo -e "${COLOR_RED}Error: This script must be run as root${COLOR_RESET}"
    echo "Try: sudo $0 $*"
    exit 1
fi
