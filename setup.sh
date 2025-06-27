#!/usr/bin/env bash
# =====================================================================
#  🧙‍♂️ Cloudflare DDNS Wizard - Professional Dynamic DNS Automation
#  Version: 2.0.0
#  Author: Jersk (https://github.com/Jersk)
#  Repository: https://github.com/Jersk/cloudflare-ddns-wizard
#  License: MIT
#  Last Updated: 2025-06-27
# =====================================================================
#
#  DESCRIPTION:
#  🚀 Complete Cloudflare Dynamic DNS solution with guided setup wizard
#  - Creates the cf-ddns.sh script automatically
#  - Provides guided onboarding for first-time setup with intelligent defaults
#  - Configures the API token and execution parameters with validation
#  - Manages the systemd service (creation, activation, monitoring)
#  - This is a self-contained installer - only this file is needed
#
#  ✨ KEY FEATURES:
#  - 🧙‍♂️ Interactive setup wizard with intuitive back navigation
#  - 🎯 Smart DNS record selection with real-time IP comparison
#  - 🛡️ Comprehensive error handling and automatic recovery
#  - 📊 Service management and monitoring dashboard
#  - 💾 Backup and restore functionality for configurations
#  - 🗑️ Complete uninstall capability with cleanup
#  - 🔒 Security-first approach with proper file permissions
#  - 🏠 Perfect for homelab and self-hosted environments
#
# =====================================================================
#
# QUICK START GUIDE:
# ==================
# 
# 📥 1. INSTALLATION:
#    Download this script to your Linux server:
#      wget https://raw.githubusercontent.com/Jersk/cloudflare-ddns-wizard/main/setup.sh
#      chmod +x setup.sh
#      ./setup.sh
#
# 🎯 2. FIRST TIME SETUP:
#    On first run, the wizard will launch automatically and guide you through:
#    - ✅ Check for required dependencies and provide install instructions
#    - 🔑 Walk you through API token configuration with validation
#    - 🌐 Guide you through DNS record selection with IP comparison
#    - 📋 Show you existing records and help you choose which ones to monitor
#    - ⚙️ Allow customization of advanced settings (intervals, retries, etc.)
#    - 🚀 Create and enable systemd services automatically
#    - 🧪 Test the configuration and provide next steps
#
# 📋 3. REQUIREMENTS:
#    - Linux system with systemd (Ubuntu 16+, Debian 8+, CentOS 7+, etc.)
#    - Root/sudo access for systemd service installation
#    - Internet connection for API calls and IP detection
#    - Dependencies: curl, jq, util-linux (flock), bash
#      (The wizard will check and guide you to install missing ones)
#
# 🔑 4. CLOUDFLARE API TOKEN:
#    Create a token at: https://dash.cloudflare.com/profile/api-tokens
#    Required permissions:
#    - Zone:Zone:Read (for all zones) ✅
#    - Zone:DNS:Edit (for all zones) ✅
#
# 🎛️ 5. ONGOING MANAGEMENT:
#    After initial setup, run this script anytime to access the control panel:
#      ./setup.sh
#    Available options:
#    - 🔧 Update configuration (API token, domain, advanced settings)
#    - 📊 Manage the service (enable/disable, view logs, status)
#    - 🔄 Re-run the setup wizard if needed
#    - 📚 View comprehensive documentation
#    - 🗑️ Complete uninstallation with cleanup
#
# 📁 6. FILES CREATED:
#    - cf-ddns.sh (main DDNS updater script)
#    - utils/config.env (configuration file)
#    - utils/.cloudflare_api_token (API token, secure 600 permissions)
#    - utils/cf-ddns.log (execution logs with rotation)
#    - /etc/systemd/system/cf-ddns.service (systemd service)
#    - /etc/systemd/system/cf-ddns.timer (systemd timer)
#
# ⚙️ 7. DEFAULT BEHAVIOR:
#    Once enabled, the service will automatically:
#    - 🔍 Check your public IP every 5 minutes
#    - 🔄 Update Cloudflare DNS records when IP changes
#    - 🚀 Start automatically after system boot
#    - 📝 Log all activities for monitoring and troubleshooting
#
# 🆘 8. SUPPORT & DOCUMENTATION:
#    - GitHub: https://github.com/Jersk/cloudflare-ddns-wizard
#    - Issues: https://github.com/Jersk/cloudflare-ddns-wizard/issues
#    - Wiki: https://github.com/Jersk/cloudflare-ddns-wizard/wiki
#
# =====================================================================

set -euo pipefail

# --- Color Constants ---
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_RESET='\033[0m'

# --- Optional TUI Detection ---
HAS_WHIPTAIL=false
if command -v whiptail >/dev/null 2>&1; then
    HAS_WHIPTAIL=true
fi

# --- Path Calculation ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
UTILS_DIR="${SCRIPT_DIR}/utils"

# --- Configuration Files ---
CONFIG_FILE="${UTILS_DIR}/config.env"
API_TOKEN_FILE="${UTILS_DIR}/.cloudflare_api_token"
CF_DDNS_SCRIPT="${SCRIPT_DIR}/cf-ddns.sh"

# --- Systemd Service Names ---
SERVICE_NAME="cf-ddns.service"
TIMER_NAME="cf-ddns.timer"

# --- Utility Functions ---
print_success() { echo -e "\033[0;32m$1\033[0m"; }
print_error() { echo -e "\033[0;31m$1\033[0m"; }
print_info() { echo -e "\033[0;36m$1\033[0m"; }  # Cyan for better visibility on black background
print_warning() { echo -e "\033[0;33m$1\033[0m"; }
print_question() { echo -ne "\033[0;35m$1\033[0m"; }  # Magenta for questions

# --- Dependencies Check ---
check_dependencies() {
    print_info "Checking system dependencies..."
    local missing_deps=()
    
    # This script is designed for systemd, which is standard on most modern Linux distros.
    # Check for systemd to prevent errors on unsupported systems like older SysV-init ones.
    if ! pgrep -x "systemd" >/dev/null 2>&1; then
        print_error "This script requires systemd, which was not found on your system."
        print_error "Please run this script on a modern Linux distribution (e.g., Ubuntu 16+, Debian 8+, CentOS 7+)."
        exit 1
    fi

    for cmd in curl jq flock bash; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ $HAS_WHIPTAIL == false ]]; then
        print_warning "Optional dependency 'whiptail' not found. TUI menus will be disabled."
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_info "Please install them using your package manager:"
        print_info "  Ubuntu/Debian: sudo apt update && sudo apt install curl jq util-linux bash"
        print_info "  CentOS/RHEL:   sudo yum install curl jq util-linux bash"
        print_info "  Arch Linux:    sudo pacman -S curl jq util-linux bash"
        exit 1
    fi
    print_success "All dependencies are installed."
}

# --- Load Saved Zone and Record Selections ---
# Reads the existing configuration file to restore previously
# selected zones and DNS records for use in TUI menus.
load_saved_selections() {
    PREV_SELECTED_ZONES=()
    PREV_SELECTED_RECORDS=()

    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=utils/config.env
        source "$CONFIG_FILE" >/dev/null 2>&1 || true
        PREV_SELECTED_ZONES=("${SELECTED_ZONES[@]}")
        PREV_SELECTED_RECORDS=("${SELECTED_RECORDS[@]}")
    fi
}

# --- Initial Setup Detection ---
is_first_time_setup() {
    # A setup is considered complete if the onboarding marker exists and critical files are valid.
    # The function returns 0 if setup is needed, and 1 if the configuration is considered complete.

    # 1. Check for the completion marker. If it doesn't exist, it's a first-time setup.
    if [[ ! -f "$UTILS_DIR/.onboarding_complete" ]]; then
        return 0
    fi

    # 2. If marker exists, verify that the installation is not corrupt.
    # This prevents issues if files were manually deleted or corrupted.
    if [[ ! -f "$CF_DDNS_SCRIPT" || ! -x "$CF_DDNS_SCRIPT" ]]; then
        print_warning "Main DDNS script is missing or not executable. Restarting setup..."
        rm -f "$UTILS_DIR/.onboarding_complete" 2>/dev/null
        return 0
    fi

    if [[ ! -f "$API_TOKEN_FILE" || ! -s "$API_TOKEN_FILE" ]]; then
        print_warning "API token file is missing or empty. Restarting setup..."
        rm -f "$UTILS_DIR/.onboarding_complete" 2>/dev/null
        return 0
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_warning "Configuration file is missing. Restarting setup..."
        rm -f "$UTILS_DIR/.onboarding_complete" 2>/dev/null
        return 0
    fi

    # 3. Perform a basic validation of the config file to ensure it's not empty or malformed.
    # shellcheck source=utils/config.env
    source "$CONFIG_FILE" >/dev/null 2>&1
    if [[ -z "${DOMAIN_MODE:-}" ]]; then
        print_warning "Configuration file appears to be corrupted (missing DOMAIN_MODE). Restarting setup..."
        rm -f "$UTILS_DIR/.onboarding_complete" 2>/dev/null
        return 0
    fi

    # If all checks pass, the setup is considered complete and valid.
    return 1
}

# --- Guided Onboarding Process ---
guided_onboarding() {
    # Replace ASCII banner with script info
    local script_info="Cloudflare DDNS Wizard - Professional Dynamic DNS Automation
Version: 2.0.0
Repository: https://github.com/Jersk/cloudflare-ddns-wizard
Author: Jersk (https://github.com/Jersk)
License: MIT"

    if [[ $HAS_WHIPTAIL == true ]]; then
        whiptail --title "Cloudflare DDNS Wizard" --msgbox "${script_info}\n\nWelcome to Cloudflare DDNS Wizard!\\nThis wizard will guide you through the initial setup." 20 70
    else
        print_info "=========================================="
        print_info "🧙‍♂️ CLOUDFLARE DDNS WIZARD - ONBOARDING"
        print_info "=========================================="
        echo ""
        print_info "$script_info"
        echo ""
        print_info "Welcome to Cloudflare DDNS Wizard! 🚀"
        print_info "This wizard will guide you through the initial setup process."
        print_info "You can customize each setting or use our intelligent defaults."
        echo ""
        read -p "Press Enter to continue..."
        echo ""
    fi

    # Step 1: Create main script
    print_info "Step 1/6: Creating main DDNS script..."
    create_ddns_script
    echo ""

    # Step 2: Configure API token
    configure_api_token_tui
    echo ""

    # Step 3: Configure settings
    configure_domain_settings_tui
    echo ""

    # Step 4: Create systemd services
    print_info "Step 4/6: Creating systemd services..."
    create_systemd_files
    echo ""

    # Step 5: Enable service
    configure_service_tui
    echo ""

    # Summary
    show_completion_summary_tui
    
    # Mark onboarding as complete
    touch "$UTILS_DIR/.onboarding_complete"
}

# --- Domain and DNS Record Configuration ---
configure_domain_settings() {
    load_saved_selections
    print_info "=========================================="
    print_info "🌐 DNS RECORD CONFIGURATION WIZARD"
    print_info "=========================================="
    echo ""
    
    print_info "This guided setup will help you:"
    print_info "  • Select which domains you want to manage"
    print_info "  • Choose specific DNS records to monitor and update"
    print_info "  • Compare current record IPs with your public IP"
    print_info "  • Configure automatic updates when your IP changes"
    echo ""
    
    # First, check if API token is working and fetch zones
    if ! test_api_connectivity; then
        print_error "❌ Cannot fetch your domains. Please check your API token first."
        return 1
    fi
    
    # Get current public IP for comparison
    print_info "Getting your current public IP address..."
    local current_public_ip=""
    if current_public_ip=$(get_current_public_ip); then
        print_success "Current public IP: $current_public_ip"
    else
        print_warning "Could not determine current public IP. Proceeding without IP comparison."
    fi
    echo ""
    
    print_info "Fetching your Cloudflare domains..."
    
    # Get zones from Cloudflare
    local zones_data
    if ! zones_data=$(get_cloudflare_zones); then
        print_error "Failed to fetch domains from Cloudflare."
        return 1
    fi
    
    # Parse zones into arrays
    local zone_ids=()
    local zone_names=()
    
    while IFS=$'\t' read -r id name; do
        zone_ids+=("$id")
        zone_names+=("$name")
    done <<< "$zones_data"
    
    if [[ ${#zone_names[@]} -eq 0 ]]; then
        print_error "No domains found in your Cloudflare account."
        print_info "Please add your domains to Cloudflare first:"
        print_info "https://dash.cloudflare.com/"
        return 1
    fi
    
    print_success "Found ${#zone_names[@]} domain(s) in your Cloudflare account!"
    echo ""
    
    # Let user select zones
    if ! select_target_zones "${zone_names[@]}"; then
        print_info "Returning to configuration menu..."
        return 1
    fi
    
    # Initialize global arrays for selected records
    SELECTED_RECORDS=()
    
    # For each selected zone, let user select DNS records with IP verification
    for zone_name in "${SELECTED_ZONES[@]}"; do
        echo ""
        print_info "Configuring DNS records for: $zone_name"
        print_info "----------------------------------------"
        
        # Get zone ID for this zone name
        local zone_id=""
        for i in "${!zone_names[@]}"; do
            if [[ "${zone_names[$i]}" == "$zone_name" ]]; then
                zone_id="${zone_ids[$i]}"
                break
            fi
        done
        
        if [[ -n "$zone_id" ]]; then
            if select_dns_records_for_zone_with_ip_check "$zone_id" "$zone_name" "$current_public_ip"; then
                continue  # Selection successful, continue to next zone
            else
                local exit_code=$?
                if [[ $exit_code -eq 2 ]]; then
                    print_info "Returning to zone selection..."
                    return 0  # Let user restart the process
                fi
                # For other errors (exit code 1), just continue
            fi
        fi
    done
    
    # Generate configuration
    generate_advanced_config
    
    # Regenerate the main DDNS script with updated configuration
    print_info "Updating main DDNS script with new configuration..."
    if create_ddns_script; then
        print_success "✅ Main DDNS script updated successfully!"
    else
        print_warning "⚠️ Failed to update main script. Please regenerate it manually from the configuration menu."
    fi
    
    echo ""
    print_success "🎉 Domain and DNS record configuration complete!"
    show_configuration_summary
}

# --- Onboarding Settings Configuration ---
configure_onboarding_settings() {
    print_info "Let's configure your DDNS settings. You can use defaults or customize."
    echo ""

    # IP Service URLs
    print_info "IP Detection Services:"
    print_info "Multiple services ensure reliability if one is down."
    read -p "Use default IP services? (Y/n): " use_default_services
    if [[ "$use_default_services" =~ ^[Nn]$ ]]; then
        configure_custom_ip_services
    fi

    # Check interval
    print_info ""
    print_info "Update Frequency:"
    print_info "How often should we check for IP changes?"
    print_info "Current default: 5min (recommended for most users)"
    read -p "Use default check interval (5min)? (Y/n): " use_default_interval
    if [[ "$use_default_interval" =~ ^[Nn]$ ]]; then
        while true; do
            read -p "Enter interval (e.g., 2min, 10min, 1h): " custom_interval
            if [[ "$custom_interval" =~ ^[0-9]+(s|sec|m|min|h|hour|d|day)$ ]]; then
                RUN_INTERVAL="$custom_interval"
                break
            else
                print_error "Invalid format. Use: 30s, 5min, 1h, etc."
            fi
        done
    else
        RUN_INTERVAL="5min"
    fi

    # Retry settings
    print_info ""
    print_info "Retry Configuration:"
    print_info "How many times to retry if a DNS update fails?"
    print_info "Current default: 3 retries (recommended)"
    read -p "Use default retry settings? (Y/n): " use_default_retries
    if [[ "$use_default_retries" =~ ^[Nn]$ ]]; then
        read -p "Number of retries (1-10): " custom_retries
        if [[ "$custom_retries" =~ ^([1-9]|10)$ ]]; then
            MAX_RETRIES="$custom_retries"
        else
            print_info "Invalid input, using default (3)."
            MAX_RETRIES=3
        fi
        
        read -p "Seconds between retries (1-30): " custom_sleep
        if [[ "$custom_sleep" =~ ^([1-9]|[12][0-9]|30)$ ]]; then
            SLEEP_BETWEEN_RETRIES="$custom_sleep"
        else
            print_info "Invalid input, using default (5)."
            SLEEP_BETWEEN_RETRIES=5
        fi
    else
        MAX_RETRIES=3
        SLEEP_BETWEEN_RETRIES=5
    fi

    # Error handling settings
    print_info ""
    print_info "Error Handling Configuration:"
    print_info "Configure how the system behaves when errors occur."
    read -p "Enable detailed error logging? (Y/n): " enable_detailed_logging
    if [[ "$enable_detailed_logging" =~ ^[Nn]$ ]]; then
        DETAILED_LOGGING="false"
    else
        DETAILED_LOGGING="true"
    fi

    read -p "Continue processing other records if one fails? (Y/n): " continue_on_error
    if [[ "$continue_on_error" =~ ^[Nn]$ ]]; then
        CONTINUE_ON_ERROR="false"
    else
        CONTINUE_ON_ERROR="true"
    fi

    # Network timeout settings
    print_info ""
    print_info "Network Timeout Configuration:"
    print_info "Maximum time to wait for network connectivity."
    read -p "Use default network timeout (300s)? (Y/n): " use_default_timeout
    if [[ "$use_default_timeout" =~ ^[Nn]$ ]]; then
        while true; do
            read -p "Enter network timeout in seconds (60-900): " custom_timeout
            if [[ "$custom_timeout" =~ ^[0-9]+$ ]] && [[ $custom_timeout -ge 60 && $custom_timeout -le 900 ]]; then
                MAX_WAIT_FOR_NET="$custom_timeout"
                break
            else
                print_error "Invalid timeout. Please enter a value between 60 and 900 seconds."
            fi
        done
    else
        MAX_WAIT_FOR_NET=300
    fi

    # Create config file with chosen settings
    create_config_file_with_settings
    print_success "Configuration saved!"
}

# --- Custom IP Services Configuration ---
configure_custom_ip_services() {
    print_info ""
    print_info "Default IP services:"
    print_info "  1. https://api.ipify.org"
    print_info "  2. https://checkip.amazonaws.com"
    print_info "  3. https://ifconfig.me/ip"
    print_info "  4. https://api.ip.sb/ip"
    print_info "  5. https://ipv4.icanhazip.com"
    echo ""
    print_info "You can keep these or add your own."
    print_info "Services must return only the IP address in plain text."
    echo ""
    
    read -p "Add custom IP service URL (or press Enter to use defaults): " custom_service
    if [[ -n "$custom_service" ]]; then
        CUSTOM_IP_SERVICE="$custom_service"
        print_info "Custom service will be added to the list."
    fi
}

# --- Create Config File with Onboarding Settings ---
create_config_file_with_settings() {
    # Ensure utils directory exists
    mkdir -p "$UTILS_DIR"
    
    local ip_services='IP_SERVICES=(
    "https://api.ipify.org"
    "https://checkip.amazonaws.com"
    "https://ifconfig.me/ip"
    "https://api.ip.sb/ip"
    "https://ipv4.icanhazip.com"'
    
    # Add custom service if provided
    if [[ -n "${CUSTOM_IP_SERVICE:-}" ]]; then
        ip_services+=$'\n    "'"$CUSTOM_IP_SERVICE"'"'
    fi
    ip_services+=$'\n)'

    # Serialize arrays properly for the config file
    local zones_line="SELECTED_ZONES=("
    for zone in "${SELECTED_ZONES[@]}"; do
        zones_line+="\"$zone\" "
    done
    zones_line+=")"
    
    local records_line="SELECTED_RECORDS=("
    for record in "${SELECTED_RECORDS[@]}"; do
        records_line+="\"$record\" "
    done
    records_line+=")"

    cat > "$CONFIG_FILE" <<EOF
# Configuration file for cf-ddns.sh

# Domain Configuration Mode
# SIMPLE: Single domain/subdomain (legacy mode)
# SPECIFIC: Selected specific domains and records
# ALL: Manage all domains and records automatically
DOMAIN_MODE="${DOMAIN_MODE:-SIMPLE}"

# Simple Mode Configuration (used when DOMAIN_MODE=SIMPLE)
# The domain/zone to update (e.g., example.com)
DOMAIN="${DOMAIN:-}"
# The subdomain/record to update (e.g., home, vpn, or @ for root domain)
SUBDOMAIN="${SUBDOMAIN:-}"

# Advanced Mode Configuration (used when DOMAIN_MODE=SPECIFIC or ALL)
# Selected zones (domains) - empty means all zones
$zones_line
# Selected records in format: "zone_id:record_id:record_name:record_type"
$records_line

# Services to get the public IP (must return only the IP in plain text)
# Multiple services for redundancy - will try each one in order until success
$ip_services

# Retry and Error Handling Configuration
# Maximum number of retries to update a DNS record
MAX_RETRIES=${MAX_RETRIES:-3}
# Seconds to wait between retries
SLEEP_BETWEEN_RETRIES=${SLEEP_BETWEEN_RETRIES:-5}
# Maximum time (in seconds) to wait for a valid network connection
MAX_WAIT_FOR_NET=${MAX_WAIT_FOR_NET:-300}
# Interval (in seconds) between network connection checks
WAIT_INTERVAL=10
# Enable detailed error logging (true/false)
DETAILED_LOGGING=${DETAILED_LOGGING:-true}
# Continue processing other records if one fails (true/false)
CONTINUE_ON_ERROR=${CONTINUE_ON_ERROR:-true}
# Skip verification step after updates (faster but less reliable) (true/false)
SKIP_VERIFICATION=${SKIP_VERIFICATION:-false}

# Service Configuration
# Timer execution interval (systemd format, e.g., 5min, 1h, etc.)
RUN_INTERVAL="${RUN_INTERVAL:-5min}"
# Maximum lines to keep in log file (automatic rotation)
LOG_MAX_LINES=1000

# Advanced Error Recovery Settings
# Number of consecutive failures before alerting (future feature)
MAX_CONSECUTIVE_FAILURES=5
# Exponential backoff multiplier for retries
RETRY_BACKOFF_MULTIPLIER=2
# Maximum delay between retries (seconds)
MAX_RETRY_DELAY=300
EOF
}

# =====================================================================
#  🔐 IMPORTANT NOTES ABOUT PERMISSIONS AND SUDO
# =====================================================================
# 
# 🛡️ SECURITY-FIRST APPROACH:
# This wizard follows security best practices and requires sudo access ONLY for:
# - Creating/managing systemd service files in /etc/systemd/system/
# - Running systemctl commands (start, stop, enable, disable services)
# - Reading systemd logs with journalctl
#
# ⚠️ IMPORTANT: You don't need to run the entire script as sudo. 
# Running as sudo is NOT recommended for security reasons.
# The script will prompt for sudo when needed.
#
# 🔄 INTERRUPTION RECOVERY:
# If the setup process is interrupted at any point:
# - Partial configuration files are automatically detected and cleaned
# - You can safely re-run the script to start fresh
# - Menu option "Reset Configuration" manually cleans everything
# - Menu option "Uninstall Service" removes everything completely
#
# 🔒 FILES PERMISSION SECURITY:
# - API token file has 600 permissions (owner read/write only)
# - Configuration files are protected from other users
# - Main script is executable only by owner
# - Lock files prevent concurrent execution
#
# =====================================================================

# --- Test API Connectivity ---
test_api_connectivity() {
    # This function quietly tests the API token and returns a status code.
    # It is used by other functions to validate the token before proceeding.
    # Returns 0 on success, 1 on failure.
    
    local test_token
    if [[ ! -f "$API_TOKEN_FILE" || ! -s "$API_TOKEN_FILE" ]]; then
        # No error message here, as the calling function should handle it.
        return 1
    fi
    
    # Read token and remove potential newlines
    test_token=$(tr -d '\n\r' < "$API_TOKEN_FILE")
    
    # The API call to verify the token.
    # It must have both Zone:Read and DNS:Edit permissions.
    local response
    response=$(curl --silent --show-error --connect-timeout 15 \
         -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
         -H "Authorization: Bearer $test_token" \
         -H "Content-Type:application/json")

    # Check if curl command itself failed (e.g., network error)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Check if the response indicates success (jq -e returns 0 if the expression is true)
    if echo "$response" | jq -e '.success == true' > /dev/null 2>&1; then
        return 0 # Success
    fi
    
    return 1 # Failure
}
create_ddns_script() {
    print_info "Creating cf-ddns.sh script..."
    
    # Ensure utils directory exists
    mkdir -p "$UTILS_DIR"
    
    cat > "$CF_DDNS_SCRIPT" << 'DDNS_SCRIPT_EOF'
#!/usr/bin/env bash
# =====================================================================
#  Cloudflare Dynamic DNS Updater - Enhanced Error Handling
#  - This script updates DNS 'A' records on Cloudflare.
#  - It is designed to be run by a systemd service, managed by setup.sh.
#  - Dependencies: curl, jq, flock.
#  - Features: Comprehensive error handling, non-blocking execution
# =====================================================================

set -euo pipefail

# --- Dynamic Path Calculation ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
UTILS_DIR="${SCRIPT_DIR}/utils"
LOG_FILE="${UTILS_DIR}/cf-ddns.log"

# --- Configuration Files ---
CONFIG_FILE="${UTILS_DIR}/config.env"
API_TOKEN_FILE="${UTILS_DIR}/.cloudflare_api_token"

# --- Global Variables Declaration ---
declare -g CF_API_TOKEN=""
declare -g CURRENT_IP=""

# --- Error Tracking ---
declare -i ERROR_COUNT=0
declare -i SUCCESS_COUNT=0
declare -a FAILED_OPERATIONS=()

# --- Default IP Services (fallback if config fails) ---
declare -a DEFAULT_IP_SERVICES=(
    "https://api.ipify.org"
    "https://checkip.amazonaws.com"
    "https://ifconfig.me/ip"
    "https://api.ip.sb/ip"
    "https://ipv4.icanhazip.com"
)

# --- Directory and Log File Creation ---
mkdir -p "$UTILS_DIR"
touch "$LOG_FILE"

# --- Enhanced Logging Function ---
log() {
    local level="${1:-INFO}"
    shift
    local message="$*"
    local timestamp
    timestamp=$(printf '[%(%F %T)T]' -1)
    
    case "$level" in
        "ERROR")
            echo -e "${timestamp} [cf-ddns] ❌ ERROR: $message" | tee -a "$LOG_FILE"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            ;;
        "WARN")
            echo -e "${timestamp} [cf-ddns] ⚠️ WARNING: $message" | tee -a "$LOG_FILE"
            ;;
        "SUCCESS")
            echo -e "${timestamp} [cf-ddns] ✅ SUCCESS: $message" | tee -a "$LOG_FILE"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            ;;
        "INFO"|*)
            echo -e "${timestamp} [cf-ddns] ℹ️ INFO: $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# --- Error Handler ---
handle_error() {
    local operation="$1"
    local error_msg="$2"
    local is_critical="${3:-false}"
    
    log "ERROR" "$operation failed: $error_msg"
    FAILED_OPERATIONS+=("$operation: $error_msg")
    
    if [[ "$is_critical" == "true" ]]; then
        log "ERROR" "Critical error encountered. Exiting..."
        exit 1
    fi
    
    return 1
}

# --- Log Rotation Function ---
rotate_log() {
    local max_lines=${LOG_MAX_LINES:-1000}
    # Ensure max_lines is a positive integer to prevent errors.
    if ! [[ "$max_lines" =~ ^[0-9]+$ ]] || [[ "$max_lines" -eq 0 ]]; then
        max_lines=1000
    fi

    if [[ -f "$LOG_FILE" ]] && [[ $(wc -l < "$LOG_FILE") -gt $max_lines ]]; then
        log "INFO" "Log file exceeds $max_lines lines. Rotating..."
        # Use tail to keep the last N lines and overwrite the log file.
        # A temporary file is used for a safe atomic move operation.
        local temp_log
        temp_log=$(mktemp)
        if tail -n "$max_lines" "$LOG_FILE" > "$temp_log"; then
            mv "$temp_log" "$LOG_FILE"
        else
            # If tail fails, just remove the temp file.
            rm -f "$temp_log"
        fi
    fi
}

# --- Configuration Loading with Error Handling ---
load_configuration() {
    log "INFO" "Loading configuration from $CONFIG_FILE"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        handle_error "CONFIG_LOAD" "Configuration file not found: $CONFIG_FILE" true
    fi
    
    if [[ ! -f "$API_TOKEN_FILE" ]]; then
        handle_error "CONFIG_LOAD" "API token file not found: $API_TOKEN_FILE" true
    fi
    
    # Check file permissions and readability
    if [[ ! -r "$API_TOKEN_FILE" ]]; then
        handle_error "CONFIG_LOAD" "API token file is not readable: $API_TOKEN_FILE (check permissions)" true
    fi
    
    if [[ ! -r "$CONFIG_FILE" ]]; then
        handle_error "CONFIG_LOAD" "Config file is not readable: $CONFIG_FILE (check permissions)" true
    fi
    
    # Load configuration file
    log "INFO" "Sourcing configuration file: $CONFIG_FILE"
    # shellcheck source=utils/config.env
    if ! source "$CONFIG_FILE" 2>/dev/null; then
        handle_error "CONFIG_LOAD" "Failed to load configuration file" true
    fi
    
    # Validate that arrays are properly loaded for SPECIFIC mode
    if [[ "${DOMAIN_MODE:-}" == "SPECIFIC" ]] && [[ ${#SELECTED_RECORDS[@]} -eq 0 ]]; then
        log "WARN" "DOMAIN_MODE is SPECIFIC, but no records are selected in SELECTED_RECORDS."
    fi
    
    # Set IP_SERVICES to default if not loaded from config
    if [[ -z "${IP_SERVICES:-}" || "${#IP_SERVICES[@]}" -eq 0 ]]; then
        IP_SERVICES=("${DEFAULT_IP_SERVICES[@]}")
    fi
    
    log "INFO" "Using ${#IP_SERVICES[@]} IP detection services"
    
    # Read API token with better error handling and multiple methods
    local token_content
    log "INFO" "Reading API token from: $API_TOKEN_FILE"
    
    # Check file readability first
    if [[ ! -r "$API_TOKEN_FILE" ]]; then
        local file_owner file_group file_perms
        if [[ -f "$API_TOKEN_FILE" ]]; then
            file_perms=$(ls -la "$API_TOKEN_FILE" 2>/dev/null | awk '{print $1, $3, $4}')
            log "ERROR" "Cannot read API token file (permissions issue)"
            log "ERROR" "File details: $file_perms"
            log "ERROR" "Current user: $(whoami), groups: $(groups)"
        fi
        handle_error "CONFIG_LOAD" "API token file is not readable: $API_TOKEN_FILE" true
    fi
    
    # Try multiple methods to read the token
    if ! token_content=$(head -n1 "$API_TOKEN_FILE" 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//'); then
        # Fallback method
        if ! token_content=$(<"$API_TOKEN_FILE" 2>/dev/null); then
            handle_error "CONFIG_LOAD" "Failed to read API token file: $API_TOKEN_FILE" true
        fi
        # Remove newlines, carriage returns, and trailing whitespace more reliably
        token_content=$(echo "$token_content" | tr -d '\n\r' | sed 's/[[:space:]]*$//')
    fi
    
    CF_API_TOKEN="$token_content"
    
    if [[ -z "$CF_API_TOKEN" ]]; then
        log "ERROR" "Token file exists but content is empty or only whitespace"
        log "ERROR" "File size: $(wc -c < "$API_TOKEN_FILE" 2>/dev/null || echo 'unknown') bytes"
        log "ERROR" "Raw content length: ${#token_content} chars"
        log "ERROR" "Processed token length: ${#CF_API_TOKEN} chars"
        log "ERROR" "File content (hex): $(xxd -l 50 "$API_TOKEN_FILE" 2>/dev/null || echo 'cannot read')"
        handle_error "CONFIG_LOAD" "API token is empty after reading from: $API_TOKEN_FILE" true
    fi
    
    log "INFO" "Configuration loaded successfully (token length: ${#CF_API_TOKEN}, mode: ${DOMAIN_MODE:-SIMPLE})"
}

# --- Concurrency Lock with Error Handling ---
acquire_lock() {
    local lock_dir="${UTILS_DIR}/lock"
    local lock_file="${lock_dir}/cf-ddns.lock"
    
    if ! mkdir -p "$lock_dir" 2>/dev/null; then
        handle_error "LOCK" "Cannot create lock directory: $lock_dir" true
    fi
    
    exec 200>"$lock_file" 2>/dev/null || {
        handle_error "LOCK" "Cannot create lock file: $lock_file" true
    }
    
    if ! flock -n 200; then
        log "INFO" "Another instance is already running. Exiting gracefully."
        exit 0
    fi
    
    log "INFO" "Lock acquired successfully"
}

# --- Enhanced API Wrapper ---
cf_api() {
    local method="$1"
    local url="$2"
    local data="${3:-}"
    local max_retries=3
    local attempt=1
    
    # Write log directly to file to avoid contaminating stdout during command substitution
    echo "$(printf '[%(%F %T)T]' -1) [cf-ddns] ℹ️ INFO: API call: $method $url" >> "$LOG_FILE"
    
    while [[ $attempt -le $max_retries ]]; do
        local response
        if data="$data" response=$(safe_curl -sS -X "$method" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            ${data:+--data "$data"} \
            "$url"); then
            
            # Validate JSON response
            if ! echo "$response" | jq empty 2>/dev/null; then
                echo "$(printf '[%(%F %T)T]' -1) [cf-ddns] ⚠️ WARNING: Invalid JSON response from API (attempt $attempt/$max_retries): ${response:0:200}..." >> "$LOG_FILE"
                attempt=$((attempt + 1))
                continue
            fi
            
            # Check for Cloudflare API errors
            local success
            success=$(echo "$response" | jq -r '.success // false' 2>/dev/null)
            
            if [[ "$success" == "true" ]]; then
                echo "$(printf '[%(%F %T)T]' -1) [cf-ddns] ℹ️ INFO: API call successful" >> "$LOG_FILE"
                echo "$response"  # Only return clean JSON to stdout
                return 0
            else
                local errors
                errors=$(echo "$response" | jq -r '.errors[]?.message // "Unknown error"' 2>/dev/null | head -3 | tr '\n' '; ')
                echo "$(printf '[%(%F %T)T]' -1) [cf-ddns] ⚠️ WARNING: API returned error (attempt $attempt/$max_retries): $errors" >> "$LOG_FILE"
                echo "$(printf '[%(%F %T)T]' -1) [cf-ddns] ⚠️ WARNING: Full response: ${response:0:500}..." >> "$LOG_FILE"
                
                # Check for rate limiting
                if echo "$response" | jq -e '.errors[]? | select(.code == 10013)' >/dev/null 2>&1; then
                    echo "$(printf '[%(%F %T)T]' -1) [cf-ddns] ⚠️ WARNING: Rate limit detected, waiting longer..." >> "$LOG_FILE"
                    sleep $((attempt * 10))
                fi
            fi
        else
            echo "$(printf '[%(%F %T)T]' -1) [cf-ddns] ⚠️ WARNING: curl failed for API call (attempt $attempt/$max_retries)" >> "$LOG_FILE"
        fi

        attempt=$((attempt + 1))
        sleep $((attempt * 2))  # Progressive delay
    done
    
    echo "$(printf '[%(%F %T)T]' -1) [cf-ddns] ❌ ERROR: API call failed after $max_retries attempts" >> "$LOG_FILE"
    return 1
}

# --- Token Verification with Error Handling ---
verify_token() {
    log "INFO" "Verifying API token..."
    
    if cf_api GET "https://api.cloudflare.com/client/v4/user/tokens/verify" >/dev/null; then
        log "SUCCESS" "API token is valid"
        return 0
    else
        handle_error "TOKEN_VERIFY" "API token verification failed - token may be invalid, expired, or permissions insufficient"
        return 1
    fi
}

# --- Enhanced IP Detection with Comprehensive Error Handling ---
get_public_ip() {
    local ip
    local service_count=0
    local working_services=0
    
    for service in "${IP_SERVICES[@]}"; do
        service_count=$((service_count + 1))
        # Write logs directly to file to avoid contaminating the returned IP
        echo "$(printf '[%(%F %T)T]' -1) [cf-ddns] ℹ️ INFO: Attempting to get public IP from: $service" >> "$LOG_FILE"
        
        if ip=$(safe_curl -s --max-time 10 --connect-timeout 5 "$service"); then
            # Validate IPv4 format
            if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                # Additional validation for valid IP ranges
                IFS='.' read -r a b c d <<< "$ip"
                if [[ $a -le 255 && $b -le 255 && $c -le 255 && $d -le 255 && $a -ne 0 ]]; then
                    echo "$(printf '[%(%F %T)T]' -1) [cf-ddns] ✅ SUCCESS: Successfully obtained IP: $ip from $service" >> "$LOG_FILE"
                    echo "$ip"  # Only return the IP, no log output to stdout
                    return 0
                else
                    echo "$(printf '[%(%F %T)T]' -1) [cf-ddns] ⚠️ WARNING: Invalid IP range received from $service: '$ip'" >> "$LOG_FILE"
                fi
            else
                echo "$(printf '[%(%F %T)T]' -1) [cf-ddns] ⚠️ WARNING: Invalid IP format received from $service: '$ip'" >> "$LOG_FILE"
            fi
        else
            echo "$(printf '[%(%F %T)T]' -1) [cf-ddns] ⚠️ WARNING: Failed to connect to $service" >> "$LOG_FILE"
        fi
    done
    
    echo "$(printf '[%(%F %T)T]' -1) [cf-ddns] ❌ ERROR: All $service_count IP detection services failed" >> "$LOG_FILE"
    return 1
}

# --- Network Wait with Timeout ---
wait_for_network() {
    local elapsed=0
    local max_wait=${MAX_WAIT_FOR_NET:-300}
    local interval=${WAIT_INTERVAL:-10}
    
    log "INFO" "Waiting for stable network connection..."
    
    while true; do
        if CURRENT_IP=$(get_public_ip); then
            log "SUCCESS" "Network connection established, public IP: $CURRENT_IP"
            return 0
        fi

        if [[ $elapsed -ge $max_wait ]]; then
            handle_error "NETWORK" "Timed out waiting for network connection after ${max_wait}s"
            return 1
        fi

        log "INFO" "Retrying network connection in ${interval}s (elapsed: ${elapsed}s)"
        sleep "$interval"
        ((elapsed+=interval))
    done
}

# --- Enhanced Record Update with Error Recovery ---
update_record() {
    local zone_id="$1"
    local record_id="$2"
    local record_name="$3"
    local record_type="$4"
    local max_retries=${MAX_RETRIES:-3}
    local retry_delay=${SLEEP_BETWEEN_RETRIES:-5}
    
    log "INFO" "Updating record: $record_name ($record_type) in zone $zone_id"
    
    # First, get the current record settings to preserve proxied status
    local current_record
    if ! current_record=$(cf_api GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${record_id}"); then
        log "WARN" "Could not fetch current record settings, using defaults"
        current_record=""
    fi
    
    # Extract current proxied status and TTL with robust error handling
    local current_proxied current_ttl
    if [[ -n "$current_record" ]]; then
        current_proxied=$(echo "$current_record" | jq -r '.result.proxied // false' 2>/dev/null)
        current_ttl=$(echo "$current_record" | jq -r '.result.ttl // 1' 2>/dev/null)
        
        # Validate and sanitize the values
        if [[ "$current_proxied" != "true" && "$current_proxied" != "false" ]]; then
            current_proxied="false"
        fi
        if [[ ! "$current_ttl" =~ ^[0-9]+$ ]] || [[ "$current_ttl" -eq 0 ]]; then
            current_ttl="1"
        fi
    else
        current_proxied="false"
        current_ttl="1"
    fi
    
    log "INFO" "Preserving current settings: proxied='$current_proxied', ttl='$current_ttl'"
    
    # Additional validation before JSON creation
    if [[ -z "$current_proxied" ]]; then
        current_proxied="false"
        log "WARN" "Empty proxied value detected, using default: false"
    fi
    if [[ -z "$current_ttl" ]]; then
        current_ttl="1"
        log "WARN" "Empty TTL value detected, using default: 1"
    fi
    
    for ((try=1; try<=max_retries; try++)); do
        local payload
        # First try with extracted settings
        if ! payload=$(jq -nc \
            --arg type "$record_type" \
            --arg name "$record_name" \
            --arg content "$CURRENT_IP" \
            --argjson proxied "$current_proxied" \
            --argjson ttl "$current_ttl" \
            '{"type":$type,"name":$name,"content":$content,"ttl":$ttl,"proxied":$proxied}' 2>/dev/null); then
            
            # Debug information for payload creation failure
            log "ERROR" "JSON payload creation failed with values:"
            log "ERROR" "  type='$record_type', name='$record_name', content='$CURRENT_IP'"
            log "ERROR" "  proxied='$current_proxied', ttl='$current_ttl'"
            
            # Fallback to simple payload with default values
            log "WARN" "Falling back to simple payload with default values"
            if ! payload=$(jq -nc \
                --arg type "$record_type" \
                --arg name "$record_name" \
                --arg content "$CURRENT_IP" \
                '{"type":$type,"name":$name,"content":$content,"ttl":1,"proxied":false}' 2>/dev/null); then
                
                handle_error "UPDATE_RECORD" "Failed to create even simple JSON payload for $record_name"
                return 1
            fi
            log "INFO" "Using fallback payload: $payload"
        else
            log "INFO" "Generated payload: $payload"
        fi

        log "INFO" "Sending update request for $record_name (attempt $try/$max_retries)"
        
        # Store API response for debugging
        local api_response
        if api_response=$(cf_api PUT "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${record_id}" "$payload"); then
            log "SUCCESS" "API call successful for $record_name"
            
            # Skip verification if configured to do so
            if [[ "${SKIP_VERIFICATION:-false}" == "true" ]]; then
                log "INFO" "Verification skipped for $record_name (SKIP_VERIFICATION=true)"
                return 0
            fi
            
            # Verify the update
            local verification_delay=5  # Increased delay for better propagation
            sleep $verification_delay
            log "INFO" "Verifying update for $record_name (after ${verification_delay}s delay)..."
            
            local verification_response current_ip
            if verification_response=$(cf_api GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${record_id}"); then
                if current_ip=$(echo "$verification_response" | jq -r '.result.content // ""' 2>/dev/null) && [[ -n "$current_ip" ]]; then
                    if [[ "$current_ip" == "$CURRENT_IP" ]]; then
                        log "SUCCESS" "$record_name updated successfully to $CURRENT_IP (verified)"
                        return 0
                    else
                        log "WARN" "Update verification failed for $record_name: expected '$CURRENT_IP', got '$current_ip' (attempt $try/$max_retries)"
                        log "WARN" "This may be due to DNS propagation delay - the update might still be successful"
                        # On last attempt, consider it a success if API call was successful
                        if [[ $try -eq $max_retries ]]; then
                            log "INFO" "Considering update successful based on API response (verification failed but API call succeeded)"
                            return 0
                        fi
                    fi
                else
                    log "WARN" "Failed to parse verification response for $record_name (attempt $try/$max_retries)"
                    log "WARN" "Response: ${verification_response:0:200}..."
                    # On last attempt, consider it a success if API call was successful
                    if [[ $try -eq $max_retries ]]; then
                        log "INFO" "Considering update successful based on API response (verification parsing failed but API call succeeded)"
                        return 0
                    fi
                fi
            else
                log "WARN" "Failed to verify update for $record_name - API call failed (attempt $try/$max_retries)"
                # On last attempt, consider it a success if API call was successful
                if [[ $try -eq $max_retries ]]; then
                    log "INFO" "Considering update successful based on API response (verification API failed but update API call succeeded)"
                    return 0
                fi
            fi
        else
            log "WARN" "API call failed for $record_name (attempt $try/$max_retries)"
        fi

        if [[ $try -lt $max_retries ]]; then
            log "INFO" "Retrying $record_name update in ${retry_delay}s..."
            sleep "$retry_delay"
        fi
    done

    handle_error "UPDATE_RECORD" "Failed to update $record_name after $max_retries attempts"
    return 1
}

# --- Enhanced Zone Processing with Error Recovery ---
process_zones() {
    # Check configuration mode and process accordingly
    case "${DOMAIN_MODE:-SIMPLE}" in
        "SIMPLE")
            process_simple_mode
            ;;
        "SPECIFIC")
            process_specific_mode
            ;;
        "ALL")
            process_all_zones_mode
            ;;
        *)
            log "ERROR" "Invalid DOMAIN_MODE: ${DOMAIN_MODE:-SIMPLE}"
            return 1
            ;;
    esac
}

# --- Process Simple Mode (Single Domain/Subdomain) ---
process_simple_mode() {
    # Validate required variables for simple mode
    if [[ -z "${DOMAIN:-}" || -z "${SUBDOMAIN:-}" ]]; then
        handle_error "CONFIG" "Simple mode requires DOMAIN and SUBDOMAIN to be configured"
        return 1
    fi
    
    log "INFO" "Processing simple mode for $SUBDOMAIN.$DOMAIN"
    
    # Get zone ID for the domain
    local zone_data
    if ! zone_data=$(cf_api GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN"); then
        handle_error "ZONE_FETCH" "Failed to retrieve zone for $DOMAIN"
        return 1
    fi
    
    local zone_id
    zone_id=$(echo "$zone_data" | jq -r '.result[0].id // empty')
    if [[ -z "$zone_id" ]]; then
        handle_error "ZONE_FETCH" "Zone not found for domain $DOMAIN"
        return 1
    fi
    
    # Get the specific record name
    local record_name="$SUBDOMAIN.$DOMAIN"
    if [[ "$SUBDOMAIN" == "@" ]]; then
        record_name="$DOMAIN"
    fi
    
    # Fetch ALL A records for this specific name (there might be multiple)
    local record_data
    if ! record_data=$(cf_api GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=A&name=$record_name"); then
        handle_error "RECORD_FETCH" "Failed to retrieve record for $record_name"
        return 1
    fi
    
    # Check how many records we found
    local record_count
    record_count=$(echo "$record_data" | jq -r '.result | length' 2>/dev/null || echo "0")
    
    if [[ "$record_count" -eq 0 ]]; then
        handle_error "RECORD_FETCH" "No A records found for: $record_name"
        return 1
    fi
    
    log "INFO" "Found $record_count A record(s) for $record_name"
    
    local updated_count=0
    local skipped_count=0
    local failed_count=0
    
    # Process ALL matching records
    while read -r record_json; do
        if [[ -z "$record_json" ]]; then
            continue
        fi
        
        local record_id current_dns_ip
        if ! record_id=$(echo "$record_json" | jq -r '.id' 2>/dev/null) || [[ -z "$record_id" ]]; then
            log "WARN" "Invalid record ID for $record_name"
            failed_count=$((failed_count + 1))
            continue
        fi
        
        if ! current_dns_ip=$(echo "$record_json" | jq -r '.content' 2>/dev/null); then
            log "WARN" "Cannot read current content for record $record_name (ID: $record_id)"
            failed_count=$((failed_count + 1))
            continue
        fi
        
        # Check if this record needs updating
        if [[ -n "$current_dns_ip" && "$current_dns_ip" == "$CURRENT_IP" ]]; then
            log "INFO" "Record $record_name (ID: $record_id) already has correct IP: $current_dns_ip - skipping"
            skipped_count=$((skipped_count + 1))
        else
            if [[ -n "$current_dns_ip" ]]; then
                log "INFO" "Record $record_name (ID: $record_id) needs update: $current_dns_ip → $CURRENT_IP"
            else
                log "WARN" "Record $record_name (ID: $record_id) has no current IP - updating to be safe"
            fi
            
            # Update the record
            if update_record "$zone_id" "$record_id" "$record_name" "A"; then
                log "SUCCESS" "Successfully updated record $record_name (ID: $record_id)"
                updated_count=$((updated_count + 1))
            else
                log "ERROR" "Failed to update record $record_name (ID: $record_id)"
                failed_count=$((failed_count + 1))
            fi
        fi
    done < <(echo "$record_data" | jq -c '.result[]' 2>/dev/null)
    
    log "INFO" "Simple mode completed for $record_name: $updated_count updated, $skipped_count already correct, $failed_count failed"
    
    # Update global counters
    TOTAL_UPDATED=$((TOTAL_UPDATED + updated_count))
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + skipped_count))
    TOTAL_FAILED=$((TOTAL_FAILED + failed_count))
    
    # Return success if at least some records were processed without total failure
    if [[ $((updated_count + skipped_count)) -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# --- Process Specific Mode (Selected Records) ---
process_specific_mode() {
    log "INFO" "Processing specific mode with ${#SELECTED_RECORDS[@]} selected records"
    
    if [[ ${#SELECTED_RECORDS[@]} -eq 0 ]]; then
        log "WARN" "No records selected for specific mode"
        return 0
    fi
    
    # Debug: Show all records that will be processed
    log "INFO" "Records to process:"
    for i in "${!SELECTED_RECORDS[@]}"; do
        log "INFO" "  [$((i+1))/${#SELECTED_RECORDS[@]}] ${SELECTED_RECORDS[$i]}"
    done
    
    local updated_count=0
    local failed_count=0
    local skipped_count=0
    
    for record_entry in "${SELECTED_RECORDS[@]}"; do
        log "INFO" "Processing record entry: '$record_entry'"
        
        # Parse record entry: "zone_id:record_id:record_name:record_type"
        IFS=':' read -r zone_id record_id record_name record_type <<< "$record_entry"
        
        if [[ -z "$zone_id" || -z "$record_id" || -z "$record_name" || -z "$record_type" ]]; then
            log "WARN" "Invalid record entry: $record_entry"
            log "WARN" "  zone_id='$zone_id' record_id='$record_id' record_name='$record_name' record_type='$record_type'"
            failed_count=$((failed_count + 1))
            continue
        fi
        
        log "INFO" "Checking record: $record_name ($record_type)"
        
        # Check current DNS record value first
        local current_record_response
        log "INFO" "Fetching current record data for $record_name..."
        if current_record_response=$(cf_api GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${record_id}"); then
            local current_dns_ip
            current_dns_ip=$(echo "$current_record_response" | jq -r '.result.content // empty' 2>/dev/null)
            
            if [[ -n "$current_dns_ip" ]]; then
                if [[ "$current_dns_ip" == "$CURRENT_IP" ]]; then
                    log "INFO" "Record $current_dns_ip already has correct IP: $current_dns_ip - skipping"
                    log "INFO" "About to increment skipped_count (current value: $skipped_count)"
                    skipped_count=$((skipped_count + 1))
                    log "INFO" "Incremented skipped_count to: $skipped_count"
                    log "INFO" "Record $record_name processing complete (skipped)"
                else
                    log "INFO" "Record $record_name needs update: $current_dns_ip → $CURRENT_IP"
                    log "INFO" "Proceeding to update record $record_name..."
                    
                    # Update the record
                    if update_record "$zone_id" "$record_id" "$record_name" "$record_type"; then
                        log "SUCCESS" "Successfully updated record $record_name"
                        updated_count=$((updated_count + 1))
                    else
                        log "ERROR" "Failed to update record $record_name"
                        failed_count=$((failed_count + 1))
                    fi
                    log "INFO" "Record $record_name processing complete (update attempted)"
                fi
            else
                log "WARN" "Could not read current IP for record $record_name - will update to be safe"
                log "INFO" "Proceeding to update record $record_name..."
                
                # Update the record
                if update_record "$zone_id" "$record_id" "$record_name" "$record_type"; then
                    log "SUCCESS" "Successfully updated record $record_name"
                    updated_count=$((updated_count + 1))
                else
                    log "ERROR" "Failed to update record $record_name"
                    failed_count=$((failed_count + 1))
                fi
                log "INFO" "Record $record_name processing complete (update attempted - no current IP)"
            fi
        else
            log "WARN" "Could not check current value for record $record_name - will update to be safe"
            log "INFO" "Proceeding to update record $record_name..."
            
            # Update the record
            if update_record "$zone_id" "$record_id" "$record_name" "$record_type"; then
                log "SUCCESS" "Successfully updated record $record_name"
                updated_count=$((updated_count + 1))
            else
                log "ERROR" "Failed to update record $record_name"
                failed_count=$((failed_count + 1))
            fi
            log "INFO" "Record $record_name processing complete (update attempted - API check failed)"
        fi
        
        log "INFO" "Moving to next record in the list..."
        log "INFO" "End of iteration for record: $record_name"
    done
    
    log "INFO" "Finished processing all records in specific mode"
    
    log "INFO" "Specific mode completed: $updated_count updated, $skipped_count already correct, $failed_count failed"
    
    # Update global counters
    TOTAL_UPDATED=$((TOTAL_UPDATED + updated_count))
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + skipped_count))
    TOTAL_FAILED=$((TOTAL_FAILED + failed_count))
    
    return 0
}

# --- Process All Zones Mode (Legacy behavior) ---
process_all_zones_mode() {
    log "INFO" "Fetching zones from Cloudflare..."
    
    local zone_data
    if ! zone_data=$(cf_api GET "https://api.cloudflare.com/client/v4/zones"); then
        handle_error "ZONE_FETCH" "Failed to retrieve zones from Cloudflare"
        return 1
    fi
    
    local zone_count
    zone_count=$(echo "$zone_data" | jq -r '.result | length' 2>/dev/null || echo "0")
    log "INFO" "Found $zone_count zone(s) to process"
    
    if [[ "$zone_count" -eq 0 ]]; then
        log "WARN" "No zones found in Cloudflare account"
        return 0
    fi
    
    # Process each zone with error isolation
    echo "$zone_data" | jq -r '.result[] | "\(.id) \(.name)"' 2>/dev/null | while IFS=' ' read -r zone_id zone_name; do
        if [[ -z "$zone_id" || -z "$zone_name" ]]; then
            log "WARN" "Skipping invalid zone data"
            continue
        fi
        
        log "INFO" "Processing zone: $zone_name ($zone_id)"
        
        # Fetch records for this zone
        local record_data
        if ! record_data=$(cf_api GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?type=A"); then
            handle_error "RECORD_FETCH" "Failed to retrieve records for zone $zone_name"
            continue  # Continue with next zone
        fi
        
        local record_count
        record_count=$(echo "$record_data" | jq -r '.result | length' 2>/dev/null || echo "0")
        log "INFO" "Found $record_count A record(s) in zone $zone_name"
        
        if [[ "$record_count" -eq 0 ]]; then
            log "INFO" "No A records to process in zone $zone_name"
            continue
        fi
        
        # Process all A records and check if they need updating
        local updated_records=0
        local skipped_records=0
        local failed_records=0
        
        log "INFO" "Checking all A records in zone $zone_name for current IP: $CURRENT_IP"
        
        # Use process substitution instead of pipe to avoid subshell variable issues
        while read -r record_json; do
            if [[ -z "$record_json" ]]; then
                continue
            fi
            
            local rec_id rec_name rec_type current_content
            if ! rec_id=$(echo "$record_json" | jq -r '.id' 2>/dev/null) || [[ -z "$rec_id" ]]; then
                log "WARN" "Invalid record ID in zone $zone_name"
                failed_records=$((failed_records + 1))
                continue
            fi
            
            if ! rec_name=$(echo "$record_json" | jq -r '.name' 2>/dev/null) || [[ -z "$rec_name" ]]; then
                log "WARN" "Invalid record name for ID $rec_id in zone $zone_name"
                failed_records=$((failed_records + 1))
                continue
            fi
            
            if ! rec_type=$(echo "$record_json" | jq -r '.type' 2>/dev/null) || [[ -z "$rec_type" ]]; then
                log "WARN" "Invalid record type for $rec_name in zone $zone_name"
                failed_records=$((failed_records + 1))
                continue
            fi
            
            if ! current_content=$(echo "$record_json" | jq -r '.content' 2>/dev/null); then
                log "WARN" "Cannot read current content for $rec_name in zone $zone_name"
                failed_records=$((failed_records + 1))
                continue
            fi

            # Check if this record needs updating
            if [[ "$current_content" == "$CURRENT_IP" ]]; then
                log "INFO" "Record $rec_name already has correct IP: $current_content - skipping"
                skipped_records=$((skipped_records + 1))
            else
                log "INFO" "Record $rec_name needs update: $current_content → $CURRENT_IP"
                
                # Update the record
                if update_record "$zone_id" "$rec_id" "$rec_name" "$rec_type"; then
                    log "SUCCESS" "Successfully updated record $rec_name in zone $zone_name"
                    updated_records=$((updated_records + 1))
                else
                    log "ERROR" "Failed to update record $rec_name in zone $zone_name"
                    failed_records=$((failed_records + 1))
                fi
            fi
        done < <(echo "$record_data" | jq -c '.result[]' 2>/dev/null)
        
        log "INFO" "Zone $zone_name processing complete: $updated_records updated, $skipped_records skipped, $failed_records failed"
        
        # Update global counters for this zone
        TOTAL_UPDATED=$((TOTAL_UPDATED + updated_records))
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + skipped_records))
        TOTAL_FAILED=$((TOTAL_FAILED + failed_records))
        
        log "INFO" "Completed processing zone $zone_name"
    done
}

# --- Main Execution with Comprehensive Error Handling ---
main() {
    log "INFO" "=== Starting DDNS update cycle ==="
    
    # Initialize global variables
    declare -g CURRENT_IP=""
    
    # Initialize error tracking
    ERROR_COUNT=0
    SUCCESS_COUNT=0
    FAILED_OPERATIONS=()
    
    # Initialize global DNS update tracking
    declare -g TOTAL_UPDATED=0
    declare -g TOTAL_SKIPPED=0
    declare -g TOTAL_FAILED=0
    
    # Step 1: Basic setup
    rotate_log
    load_configuration || exit 1
    acquire_lock || exit 1
    
    # Step 2: Network and API verification
    if ! wait_for_network; then
        log "ERROR" "Cannot proceed without network connection"
        exit 1
    fi
    
    if ! verify_token; then
        log "ERROR" "Cannot proceed with invalid API token"
        exit 1
    fi
    
    # Step 3: Verify we have current IP before proceeding
    if [[ -z "$CURRENT_IP" ]]; then
        log "ERROR" "No current public IP available - cannot proceed with DNS updates"
        exit 1
    fi
    
    log "INFO" "Checking which DNS records need updating to current IP: $CURRENT_IP"
    
    # Log current mode for debugging
    case "${DOMAIN_MODE:-SIMPLE}" in
        "SIMPLE")
            log "INFO" "Operating in SIMPLE mode: will update record $SUBDOMAIN.$DOMAIN"
            ;;
        "SPECIFIC")
            log "INFO" "Operating in SPECIFIC mode: will check ${#SELECTED_RECORDS[@]} selected records"
            ;;
        "ALL")
            log "INFO" "Operating in ALL ZONES mode: will check all A records in all zones"
            ;;
        *)
            log "WARN" "Unknown domain mode: ${DOMAIN_MODE:-SIMPLE}, defaulting to SIMPLE"
            ;;
    esac
    
    # Step 4: Process DNS updates based on mode
    process_zones
    
    # Step 5: Final summary
    log "INFO" "=== Update cycle summary ==="
    log "INFO" "DNS Records: $TOTAL_UPDATED updated, $TOTAL_SKIPPED already correct, $TOTAL_FAILED failed"
    log "INFO" "API Operations: $SUCCESS_COUNT successful, $ERROR_COUNT failed"
    
    if [[ ${#FAILED_OPERATIONS[@]} -gt 0 ]]; then
        log "WARN" "Failed operations details:"
        for failure in "${FAILED_OPERATIONS[@]}"; do
            log "WARN" "  - $failure"
        done
    fi
    
    log "INFO" "=== Update cycle complete ==="
    
    # Exit with appropriate code
    if [[ $ERROR_COUNT -gt 0 || $TOTAL_FAILED -gt 0 ]]; then
        exit 2  # Partial failure
    else
        exit 0  # Complete success
    fi
}

# --- Execute main function ---
main "$@"
DDNS_SCRIPT_EOF

    chmod +x "$CF_DDNS_SCRIPT"
    print_success "Main DDNS script created successfully!"
}

# --- Show Main Menu ---
show_menu() {
    if [[ $HAS_WHIPTAIL == true ]]; then
        local status_msg=""
        if systemctl is-active --quiet $TIMER_NAME 2>/dev/null; then
            status_msg="Service: ACTIVE"
        else
            status_msg="Service: INACTIVE"
        fi
        local cfg_msg=""
        if [[ -f "$CONFIG_FILE" && -f "$API_TOKEN_FILE" && -s "$API_TOKEN_FILE" ]]; then
            cfg_msg="Configuration: READY"
        else
            cfg_msg="Configuration: INCOMPLETE"
        fi

        local choice
        choice=$(whiptail --title "Cloudflare DDNS Wizard" --menu "${status_msg}\n${cfg_msg}" 20 70 10 \
            1 "Configuration Management" \
            2 "Service Management" \
            3 "View Logs" \
            4 "Manual Test Run" \
            5 "System Resilience Test" \
            6 "Backup & Restore" \
            7 "Complete Uninstall" \
            8 "Reset Configuration" \
            9 "Help" \
            0 "Exit" 3>&1 1>&2 2>&3)
        local exit_status=$?
        [[ $exit_status -ne 0 ]] && return 1
        MENU_CHOICE="$choice"
    else
        clear
        print_info "=========================================="
        print_info "🧙‍♂️ CLOUDFLARE DDNS WIZARD - CONTROL PANEL"
        print_info "=========================================="
        echo ""
        print_info "📊 Current Status:"

        if systemctl is-active --quiet $TIMER_NAME 2>/dev/null; then
            print_success "✅ Service: ACTIVE"
            source "$CONFIG_FILE" 2>/dev/null || true
            print_info "   Interval: ${RUN_INTERVAL:-5min}"
        else
            print_warning "⚠️ Service: INACTIVE"
        fi

        if [[ -f "$CONFIG_FILE" && -f "$API_TOKEN_FILE" && -s "$API_TOKEN_FILE" ]]; then
            print_success "✅ Configuration: READY"
        else
            print_warning "⚠️ Configuration: INCOMPLETE"
        fi

        echo ""
        print_info "Management Options:"
        echo "  [1] 🔧 Configuration Management"
        echo "  [2] ⚙️ Service Management"
        echo "  [3] 📋 View Logs"
        echo "  [4] 🧪 Manual Test Run"
        echo "  [5] 🔍 System Resilience Test"
        echo "  [6] 💾 Backup & Restore"
        echo "  [7] 🗑️ Complete Uninstall (removes everything)"
        echo "  [8] 🔄 Reset Configuration (Start Over)"
        echo "  [9] 📖 Help & Documentation"
        echo "  [0] 🚪 Exit"
        echo ""
        read -p "Choose an option (0-9): " MENU_CHOICE
    fi
    return 0
}

# --- Menu Functions ---

# --- Configuration Management ---
edit_config() {
    while true; do
        if [[ $HAS_WHIPTAIL == true ]]; then
            local choice
            choice=$(whiptail --title "Configuration" --menu "Choose an option" 20 70 10 \
                1 "Update API Token" \
                2 "Configure DNS Records" \
                3 "Advanced Settings" \
                4 "Fix File Permissions" \
                5 "View Current Configuration" \
                6 "Regenerate Main Script" \
                0 "Return" 3>&1 1>&2 2>&3)
            local exit_status=$?
            [[ $exit_status -ne 0 ]] && return
            config_choice="$choice"
        else
            print_info "--- Configuration Menu ---"
            echo "1. Update API Token"
            echo "2. Configure DNS Records (guided setup)"
            echo "3. Advanced Settings (intervals, retries, etc.)"
            echo "4. Fix File Permissions"
            echo "5. View Current Configuration"
            echo "6. Regenerate Main Script (fixes token parsing issues)"
            echo "0. Return to main menu"
            read -p "Choose an option (0-6): " config_choice
        fi
        
        case $config_choice in
            1) 
                if ! update_api_token; then
                    # User went back, continue config menu loop
                    continue
                fi
                ;;
            2) 
                if ! configure_domain_settings; then
                    # User went back, continue config menu loop  
                    continue
                fi
                ;;
            3) configure_advanced_settings ;;
            4) 
                fix_file_permissions || {
                    print_info "No permission issues found or unable to fix."
                }
                ;;
            5) view_current_config ;;
            6) 
                print_info "Regenerating main DDNS script with latest fixes..."
                if create_ddns_script; then
                    print_success "✅ Main script regenerated successfully!"
                    print_info "The token parsing issue should now be fixed."
                else
                    print_error "❌ Failed to regenerate script."
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            0) return ;;
            *) print_error "Invalid option. Please choose 0-6." ;;
        esac
        
        # Add a pause except when returning or for functions that handle their own pause
        if [[ "$config_choice" != "0" && "$config_choice" != "3" && "$config_choice" != "5" && "$config_choice" != "6" ]]; then
            echo ""
            read -p "Press Enter to continue..."
            echo ""
        fi
    done
}

# --- Get Cloudflare Zones ---
get_cloudflare_zones() {
    local api_token
    if [[ -f "$API_TOKEN_FILE" ]]; then
        api_token=$(<"$API_TOKEN_FILE")
    else
        return 1
    fi
    
    local response
    if response=$(curl -sS -X GET \
        -H "Authorization: Bearer ${api_token}" \
        -H "Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones" 2>/dev/null); then
        
        if echo "$response" | jq -e '.success' >/dev/null 2>&1; then
            echo "$response" | jq -r '.result[] | "\(.id)\t\(.name)"' 2>/dev/null
            return 0
        fi
    fi
    
    return 1
}

# --- Get Current Public IP ---
get_current_public_ip() {
    local ip=""
    local services=(
        "https://ipv4.icanhazip.com"
        "https://api.ipify.org"
        "https://ipinfo.io/ip"
        "https://checkip.amazonaws.com"
    )
    
    for service in "${services[@]}"; do
        if ip=$(curl -s --max-time 10 "$service" 2>/dev/null); then
            # Validate that we got a valid IP address
            if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                # Additional validation: check each octet is 0-255
                local valid=true
                IFS='.' read -ra octets <<< "$ip"
                for octet in "${octets[@]}"; do
                    if ! [[ "$octet" -ge 0 && "$octet" -le 255 ]]; then
                        valid=false
                        break
                    fi
                done
                
                if $valid; then
                    echo "$ip"
                    return 0
                fi
            fi
        fi
    done
    
    return 1
}

# --- Update API Token ---
update_api_token() {
    print_info "Current API token status:"
    if [[ -f "$API_TOKEN_FILE" && -s "$API_TOKEN_FILE" ]]; then
        if test_api_connectivity >/dev/null 2>&1; then
            print_success "✅ Current token is valid"
        else
            print_error "❌ Current token is invalid"
        fi
    else
        print_warning "⚠️ No token configured"
    fi
    
    echo ""
    print_info "Enter new Cloudflare API token (or type '0' to cancel):"
    print_info "Create one at: https://dash.cloudflare.com/profile/api-tokens"
    echo ""
    
    while true; do
        read -p "API Token (or '0' to cancel): " new_token
        if [[ "$new_token" == "0" ]]; then
            print_info "Token update cancelled."
            return 1
        elif [[ -n "$new_token" && ${#new_token} -gt 10 ]]; then
            # Backup old token
            [[ -f "$API_TOKEN_FILE" ]] && cp "$API_TOKEN_FILE" "${API_TOKEN_FILE}.bak" 2>/dev/null
            
            # Determine the correct user for ownership
            local target_user target_group
            if [[ -n "${SUDO_USER:-}" ]]; then
                # Script was run with sudo, use the original user
                target_user="$SUDO_USER"
                target_group="$SUDO_USER"
                print_info "Detected sudo execution, setting ownership to: $target_user"
            else
                # Script run directly by user
                target_user="$USER"
                target_group="$USER"
                print_info "Setting ownership to current user: $target_user"
            fi
            
            # Create directory structure with correct ownership
            mkdir -p "$UTILS_DIR"
            if [[ "$EUID" -eq 0 ]]; then
                # Running as root, set proper ownership
                chown "$target_user:$target_group" "$UTILS_DIR" 2>/dev/null || true
            fi
            chmod 755 "$UTILS_DIR"
            
            # Save token - be very careful about whitespace
            printf '%s' "$new_token" > "$API_TOKEN_FILE"
            
            # Set permissions and ownership
            chmod 600 "$API_TOKEN_FILE"
            if [[ "$EUID" -eq 0 ]]; then
                # Running as root, set proper ownership
                chown "$target_user:$target_group" "$API_TOKEN_FILE" 2>/dev/null || true
            fi
            
            # Verify the token was saved correctly
            local saved_token_length
            if [[ -f "$API_TOKEN_FILE" ]]; then
                saved_token_length=$(wc -c < "$API_TOKEN_FILE" 2>/dev/null | tr -d '[:space:]')
                print_info "Token saved successfully:"
                print_info "  File: $API_TOKEN_FILE"
                print_info "  Length: $saved_token_length characters"
                print_info "  Permissions: $(ls -la "$API_TOKEN_FILE" 2>/dev/null | awk '{print $1, $3, $4}' || echo 'Failed to check')"
            else
                print_error "Failed to save token file"
                return 1
            fi
            
            # Test new token
            if test_api_connectivity; then
                print_success "✅ New API token is valid and saved!"
                return 0
            else
                print_error "❌ New token is invalid."
                read -p "Keep it anyway? (y/N): " keep_invalid
                if [[ "$keep_invalid" =~ ^[Yy]$ ]]; then
                    print_warning "Invalid token saved. You'll need to fix it later."
                    return 0
                else
                    # Restore backup if available
                    if [[ -f "${API_TOKEN_FILE}.bak" ]]; then
                        mv "${API_TOKEN_FILE}.bak" "$API_TOKEN_FILE"
                        print_info "Previous token restored."
                    else
                        rm -f "$API_TOKEN_FILE"
                        print_info "Token removed."
                    fi
                fi
            fi
        else
            print_error "Invalid token. Please enter a valid Cloudflare API token."
        fi
    done
}

# --- View Current Configuration ---
view_current_config() {
    print_info "--- Current Configuration ---"
    
    # Load config if available
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=utils/config.env
        source "$CONFIG_FILE" 2>/dev/null || true
    fi
    
    # Display configuration
    print_info "Configuration Mode: ${DOMAIN_MODE:-SIMPLE}"
    echo ""
    
    case "${DOMAIN_MODE:-SIMPLE}" in
        "SIMPLE")
            print_info "Domain: '${DOMAIN:-Not configured}'"
            print_info "Subdomain: '${SUBDOMAIN:-Not configured}'"
            if [[ -n "${DOMAIN:-}" && -n "${SUBDOMAIN:-}" ]]; then
                if [[ "$SUBDOMAIN" == "@" ]]; then
                    print_info "Target: $DOMAIN"
                else
                    print_info "Target: $SUBDOMAIN.$DOMAIN"
                fi
            else
                print_info "Target: Not configured"
            fi
            ;;
        "SPECIFIC")
            # Check if SELECTED_ZONES is an array and get its count safely
            local zones_count=0
            if declare -p SELECTED_ZONES 2>/dev/null | grep -q '^declare -a'; then
                zones_count=${#SELECTED_ZONES[@]}
            elif [[ -n "${SELECTED_ZONES:-}" ]]; then
                zones_count=1
            fi
            
            # Check if SELECTED_RECORDS is an array and get its count safely
            local records_count=0
            if declare -p SELECTED_RECORDS 2>/dev/null | grep -q '^declare -a'; then
                records_count=${#SELECTED_RECORDS[@]}
            elif [[ -n "${SELECTED_RECORDS:-}" ]]; then
                records_count=1
            fi
            
            print_info "Selected Zones: $zones_count"
            print_info "Selected Records: $records_count"
            ;;
        "ALL")
            print_info "Mode: Update all domains and records"
            ;;
    esac
    
    echo ""
    print_info "Update Interval: ${RUN_INTERVAL:-5min}"
    print_info "Max Retries: ${MAX_RETRIES:-3}"
    print_info "Retry Delay: ${SLEEP_BETWEEN_RETRIES:-5}s"
    print_info "Network Timeout: ${MAX_WAIT_FOR_NET:-300}s"
    print_info "Detailed Logging: ${DETAILED_LOGGING:-true}"
    print_info "Continue on Error: ${CONTINUE_ON_ERROR:-true}"
    
    echo ""
    if [[ -f "$API_TOKEN_FILE" && -s "$API_TOKEN_FILE" ]]; then
        if test_api_connectivity >/dev/null 2>&1; then
            print_success "API Token: ✅ Valid"
        else
            print_error "API Token: ❌ Invalid"
        fi
    else
        print_error "API Token: ❌ Not configured"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# --- Advanced Settings Configuration ---
configure_advanced_settings() {
    while true; do
        print_info "--- Advanced Settings ---"
        
        # Load current config
        if [[ -f "$CONFIG_FILE" ]]; then
            # shellcheck source=utils/config.env
            source "$CONFIG_FILE" 2>/dev/null || true
        fi
        
        echo "1. Update Interval (current: ${RUN_INTERVAL:-5min})"
        echo "2. Retry Settings (current: ${MAX_RETRIES:-3} retries, ${SLEEP_BETWEEN_RETRIES:-5}s delay)"
        echo "3. Network Timeout (current: ${MAX_WAIT_FOR_NET:-300}s)"
        echo "4. Logging Settings"
        echo "5. Save and return"
        echo "0. Back without saving"
        
        read -p "Choose setting to modify (0-5): " setting_choice
        
        case $setting_choice in
            1)
                read -p "Enter new interval (e.g., 2min, 10min, 1h): " new_interval
                if [[ "$new_interval" =~ ^[0-9]+(s|sec|m|min|h|hour|d|day)$ ]]; then
                    RUN_INTERVAL="$new_interval"
                    print_success "Update interval set to: $RUN_INTERVAL"
                else
                    print_error "Invalid format. Use: 30s, 5min, 1h, etc."
                fi
                ;;
            2)
                read -p "Max retries (1-10): " new_retries
                if [[ "$new_retries" =~ ^([1-9]|10)$ ]]; then
                    MAX_RETRIES="$new_retries"
                fi
                read -p "Delay between retries (1-30s): " new_delay
                if [[ "$new_delay" =~ ^([1-9]|[12][0-9]|30)$ ]]; then
                    SLEEP_BETWEEN_RETRIES="$new_delay"
                fi
                print_success "Retry settings updated"
                ;;
            3)
                read -p "Network timeout (60-900s): " new_timeout
                if [[ "$new_timeout" =~ ^[0-9]+$ ]] && [[ $new_timeout -ge 60 && $new_timeout -le 900 ]]; then
                    MAX_WAIT_FOR_NET="$new_timeout"
                    print_success "Network timeout set to: ${new_timeout}s"
                else
                    print_error "Invalid timeout. Use 60-900 seconds."
                fi
                ;;
            4)
                read -p "Enable detailed logging? (y/N): " detailed_log
                DETAILED_LOGGING=$([[ "$detailed_log" =~ ^[Yy]$ ]] && echo "true" || echo "false")
                read -p "Continue on errors? (Y/n): " continue_err
                CONTINUE_ON_ERROR=$([[ "$continue_err" =~ ^[Nn]$ ]] && echo "false" || echo "true")
                print_success "Logging settings updated"
                ;;
            5)
                create_config_file_with_settings
                print_success "Settings saved!"
                
                # Regenerate the main DDNS script with updated configuration
                print_info "Updating main DDNS script with new settings..."
                if create_ddns_script; then
                    print_success "✅ Main DDNS script updated successfully!"
                else
                    print_warning "⚠️ Failed to update main script. Please regenerate it manually from the configuration menu."
                fi
                return
                ;;
            0)
                print_info "Changes discarded."
                return
                ;;
            *)
                print_error "Invalid option. Please choose 0-5."
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
        echo ""
    done
}

# --- Service Management ---
manage_service() {
    print_info "--- Service Management ---"
    
    # Check current status
    local service_active=false
    local timer_active=false
    
    if systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
        service_active=true
    fi
    
    if systemctl is-active --quiet $TIMER_NAME 2>/dev/null; then
        timer_active=true
    fi
    
    # Display status
    local status_text=""
    if $timer_active; then
        status_text="Timer: ACTIVE"
    else
        status_text="Timer: INACTIVE"
    fi

    if $service_active; then
        status_text+="\nService: RUNNING"
    else
        status_text+="\nService: STOPPED"
    fi

    if [[ $HAS_WHIPTAIL == true ]]; then
        service_choice=$(whiptail --title "Service Management" --menu "$status_text" 20 70 10 \
            1 "Enable/Start Timer" \
            2 "Disable/Stop Timer" \
            3 "Restart Timer" \
            4 "View Timer Status" \
            0 "Return" 3>&1 1>&2 2>&3)
        local exit_status=$?
        [[ $exit_status -ne 0 ]] && return
    else
        echo "Current Status:"
        if $timer_active; then
            print_success "✅ Timer: ACTIVE"
        else
            print_warning "⚠️ Timer: INACTIVE"
        fi

        if $service_active; then
            print_success "✅ Service: RUNNING"
        else
            print_info "ℹ️ Service: STOPPED (normal - runs on timer)"
        fi

        echo ""
        echo "Actions:"
        echo "1. Enable/Start Timer"
        echo "2. Disable/Stop Timer"
        echo "3. Restart Timer"
        echo "4. View Timer Status"
        echo "0. Return to main menu"
        read -p "Choose action (0-4): " service_choice
    fi
    
    case $service_choice in
        1)
            print_info "Enabling and starting DDNS timer..."
            if sudo systemctl daemon-reload && sudo systemctl enable --now $TIMER_NAME; then
                print_success "✅ Timer enabled and started!"
            else
                print_error "❌ Failed to enable timer"
            fi
            ;;
        2)
            print_info "Disabling and stopping DDNS timer..."
            if sudo systemctl disable --now $TIMER_NAME; then
                print_success "✅ Timer disabled and stopped!"
            else
                print_error "❌ Failed to disable timer"
            fi
            ;;
        3)
            print_info "Restarting DDNS timer..."
            if sudo systemctl restart $TIMER_NAME; then
                print_success "✅ Timer restarted!"
            else
                print_error "❌ Failed to restart timer"
            fi
            ;;
        4)
            print_info "Timer Status:"
            sudo systemctl status $TIMER_NAME || true
            echo ""
            print_info "Next run times:"
            sudo systemctl list-timers $TIMER_NAME || true
            ;;
        0) return ;;
        *) print_error "Invalid option. Please choose 0-4." ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
}

# --- View Logs ---
view_logs() {
    print_info "--- DDNS Logs ---"
    echo "1. View recent systemd journal"
    echo "2. View application log file"
    echo "3. Follow live logs"
    echo "0. Return to main menu"
    
    read -p "Choose option (0-3): " log_choice
    
    case $log_choice in
        1)
            print_info "Recent systemd journal:"
            sudo journalctl -u $SERVICE_NAME --no-pager -n 50 || true
            ;;
        2)
            if [[ -f "${UTILS_DIR}/cf-ddns.log" ]]; then
                print_info "Application log (last 50 lines):"
                tail -n 50 "${UTILS_DIR}/cf-ddns.log" || true
            else
                print_warning "No application log file found yet."
            fi
            ;;
        3)
            print_info "Following live logs (Press Ctrl+C to stop):"
            sudo journalctl -u $SERVICE_NAME -f || true
            ;;
        0) return ;;
        *) print_error "Invalid option. Please choose 0-3." ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
}

# --- Fix File Permissions ---
fix_file_permissions() {
    local fixed_something=false
    
    print_info "Checking and fixing file permissions..."
    
    # Determine target user
    local target_user target_group
    if [[ -n "${SUDO_USER:-}" ]]; then
        target_user="$SUDO_USER"
        target_group="$SUDO_USER"
    else
        target_user="$USER"
        target_group="$USER"
    fi
    
    print_info "Target user: $target_user"
    
    # Check utils directory
    if [[ -d "$UTILS_DIR" ]]; then
        local current_owner
        current_owner=$(ls -ld "$UTILS_DIR" 2>/dev/null | awk '{print $3}')
        if [[ "$current_owner" != "$target_user" ]]; then
            print_warning "⚠️ Utils directory has wrong owner: $current_owner (should be $target_user)"
            if [[ "$EUID" -eq 0 ]]; then
                chown "$target_user:$target_group" "$UTILS_DIR" 2>/dev/null && {
                    print_success "✅ Fixed utils directory ownership"
                    fixed_something=true
                }
            else
                print_error "❌ Cannot fix (need sudo): sudo chown $target_user:$target_group $UTILS_DIR"
            fi
        fi
    fi
    
    # Check API token file
    if [[ -f "$API_TOKEN_FILE" ]]; then
        local current_owner current_perms
        current_owner=$(ls -l "$API_TOKEN_FILE" 2>/dev/null | awk '{print $3}')
        current_perms=$(ls -l "$API_TOKEN_FILE" 2>/dev/null | awk '{print $1}')
        
        if [[ "$current_owner" != "$target_user" ]]; then
            print_warning "⚠️ API token file has wrong owner: $current_owner (should be $target_user)"
            if [[ "$EUID" -eq 0 ]]; then
                chown "$target_user:$target_group" "$API_TOKEN_FILE" 2>/dev/null && {
                    print_success "✅ Fixed API token file ownership"
                    fixed_something=true
                }
            else
                print_error "❌ Cannot fix (need sudo): sudo chown $target_user:$target_group $API_TOKEN_FILE"
            fi
        fi
        
        if [[ "$current_perms" != "-rw-------" ]]; then
            print_warning "⚠️ API token file has wrong permissions: $current_perms (should be -rw-------)"
            chmod 600 "$API_TOKEN_FILE" 2>/dev/null && {
                print_success "✅ Fixed API token file permissions"
                fixed_something=true
            }
        fi
    fi
    
    # Check config file
    if [[ -f "$CONFIG_FILE" ]]; then
        local current_owner
        current_owner=$(ls -l "$CONFIG_FILE" 2>/dev/null | awk '{print $3}')
        if [[ "$current_owner" != "$target_user" ]]; then
            print_warning "⚠️ Config file has wrong owner: $current_owner (should be $target_user)"
            if [[ "$EUID" -eq 0 ]]; then
                chown "$target_user:$target_group" "$CONFIG_FILE" 2>/dev/null && {
                    print_success "✅ Fixed config file ownership"
                    fixed_something=true
                }
            else
                print_error "❌ Cannot fix (need sudo): sudo chown $target_user:$target_group $CONFIG_FILE"
            fi
        fi
    fi
    
    if [[ "$fixed_something" == "true" ]]; then
        print_success "✅ File permissions have been corrected"
        return 0
    else
        print_info "ℹ️ All file permissions are correct"
        return 1
    fi
}

# --- Manual Test Run ---
run_manual_test() {
    print_info "--- Manual Test Run ---"
    
    if [[ ! -f "$CF_DDNS_SCRIPT" ]]; then
        print_error "DDNS script not found. Please run configuration first."
        return 1
    fi
    
    if [[ ! -x "$CF_DDNS_SCRIPT" ]]; then
        print_error "DDNS script is not executable."
        return 1
    fi
    
    # Preliminary checks
    print_info "Performing preliminary checks..."
    
    print_info "1. Checking configuration files..."
    if [[ -f "$CONFIG_FILE" ]]; then
        print_success "✅ Config file exists: $CONFIG_FILE"
    else
        print_error "❌ Config file missing: $CONFIG_FILE"
        return 1
    fi
    
    if [[ -f "$API_TOKEN_FILE" ]]; then
        print_success "✅ API token file exists: $API_TOKEN_FILE"
        local file_perms current_owner
        file_perms=$(ls -la "$API_TOKEN_FILE" 2>/dev/null | awk '{print $1, $3, $4}')
        current_owner=$(ls -l "$API_TOKEN_FILE" 2>/dev/null | awk '{print $3}')
        print_info "   File permissions: $file_perms"
        
        # Check if permissions are problematic
        if [[ "$current_owner" == "root" && "$USER" != "root" ]]; then
            print_warning "⚠️ API token is owned by root but service runs as $USER"
            read -p "Do you want to fix file permissions? (Y/n): " fix_perms
            if [[ ! "$fix_perms" =~ ^[Nn]$ ]]; then
                fix_file_permissions
            fi
        fi
        
        if [[ -s "$API_TOKEN_FILE" ]]; then
            local token_length
            token_length=$(wc -c < "$API_TOKEN_FILE" 2>/dev/null | tr -d '[:space:]')
            print_success "   Token length: $token_length characters"
        else
            print_error "❌ API token file is empty"
            return 1
        fi
    else
        print_error "❌ API token file missing: $API_TOKEN_FILE"
        return 1
    fi
    
    print_info "2. Testing API connectivity..."
    if test_api_connectivity; then
        print_success "✅ API token is valid and working"
    else
        print_error "❌ API token validation failed"
        
        # Additional debug info for token issues
        print_info "Debugging token format..."
        if [[ -f "$API_TOKEN_FILE" ]]; then
            local token_content token_clean token_hex
            token_content=$(<"$API_TOKEN_FILE" 2>/dev/null)
            token_clean=$(printf '%s' "$token_content" | tr -d '\n\r')
            token_hex=$(xxd -l 50 "$API_TOKEN_FILE" 2>/dev/null | head -3)
            
            print_info "Raw token length: ${#token_content} chars"
            print_info "Clean token length: ${#token_clean} chars"
            print_info "First 50 bytes (hex):"
            echo "$token_hex"
            
            if [[ ${#token_clean} -eq 40 ]]; then
                print_info "Token appears to be correct length for Cloudflare API token"
            else
                print_warning "Token length is unusual (expected 40 characters)"
            fi
        fi
        
        return 1
    fi
    
    echo ""
    print_info "Running manual DDNS update..."
    echo "========================================"
    
    if "$CF_DDNS_SCRIPT"; then
        echo "========================================"
        print_success "✅ Manual test completed successfully!"
    else
        local exit_code=$?
        echo "========================================"
        print_error "❌ Manual test failed with exit code: $exit_code"
        print_info "Check the logs above for error details."
        
        # Suggest checking systemd logs if this fails
        echo ""
        print_info "💡 Troubleshooting tips:"
        print_info "   • Check recent logs with: journalctl -u $SERVICE_NAME -n 20"
        print_info "   • Verify file permissions with: ls -la $UTILS_DIR/"
        print_info "   • Test API token directly with the configuration menu"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# --- System Resilience Test ---
test_system_resilience() {
    print_info "--- System Resilience Test ---"
    print_warning "This feature is not yet implemented."
    print_info "This would test various failure scenarios and recovery mechanisms."
    echo ""
    read -p "Press Enter to continue..."
}

# --- Backup & Restore ---
backup_restore() {
    print_info "--- Backup & Restore ---"
    echo "1. Create backup"
    echo "2. Restore from backup"
    echo "3. List backups"
    echo "0. Return to main menu"
    
    read -p "Choose option (0-3): " backup_choice
    
    case $backup_choice in
        1)
            local backup_dir="${SCRIPT_DIR}/backups"
            local backup_name
            backup_name="ddns-backup-$(date +%Y%m%d-%H%M%S)"
            local backup_path="${backup_dir}/${backup_name}"
            
            print_info "Creating backup..."
            mkdir -p "$backup_dir"
            mkdir -p "$backup_path"
            
            # Backup files
            [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "$backup_path/"
            [[ -f "$API_TOKEN_FILE" ]] && cp "$API_TOKEN_FILE" "$backup_path/"
            [[ -f "$CF_DDNS_SCRIPT" ]] && cp "$CF_DDNS_SCRIPT" "$backup_path/"
            [[ -f "${UTILS_DIR}/cf-ddns.log" ]] && cp "${UTILS_DIR}/cf-ddns.log" "$backup_path/"
            
            # Create backup info
            cat > "$backup_path/backup_info.txt" <<EOF
Backup created: $(date)
Script version: cf-ddns setup script
Files included:
- config.env
- .cloudflare_api_token
- cf-ddns.sh
- cf-ddns.log
EOF
            
            print_success "✅ Backup created: $backup_name"
            ;;
        2)
            local backup_dir="${SCRIPT_DIR}/backups"
            if [[ ! -d "$backup_dir" ]]; then
                print_error "No backups directory found."
                return 1
            fi
            
            print_info "Available backups:"
            local backups=()
            # Use proper glob pattern instead of ls | grep
            for backup in "$backup_dir"/ddns-backup-*; do
                if [[ -d "$backup" ]]; then
                    backups+=("$(basename "$backup")")
                fi
            done
            
            if [[ ${#backups[@]} -eq 0 ]]; then
                print_error "No backups found."
                return 1
            fi
            
            for i in "${backups[@]}"; do
                echo "  - $i"
            done
            
            read -p "Select backup to restore (1-${#backups[@]}): " restore_choice
            if [[ "$restore_choice" =~ ^[0-9]+$ ]] && [[ $restore_choice -ge 1 && $restore_choice -le ${#backups[@]} ]]; then
                local selected_backup="${backups[$((restore_choice-1))]}"
                local restore_path="${backup_dir}/${selected_backup}"
                
                print_warning "This will overwrite current configuration!"
                read -p "Continue? (y/N): " confirm_restore
                
                if [[ "$confirm_restore" =~ ^[Yy]$ ]]; then
                    print_info "Restoring from backup: $selected_backup"
                    
                    # Restore files
                    [[ -f "$restore_path/config.env" ]] && cp "$restore_path/config.env" "$CONFIG_FILE"
                    [[ -f "$restore_path/.cloudflare_api_token" ]] && cp "$restore_path/.cloudflare_api_token" "$API_TOKEN_FILE"
                    [[ -f "$restore_path/cf-ddns.sh" ]] && cp "$restore_path/cf-ddns.sh" "$CF_DDNS_SCRIPT"
                    
                    # Set permissions
                    chmod 600 "$API_TOKEN_FILE" 2>/dev/null
                    chmod +x "$CF_DDNS_SCRIPT" 2>/dev/null
                    
                    print_success "✅ Backup restored successfully!"
                else
                    print_info "Restore cancelled."
                fi
            else
                print_error "Invalid selection."
            fi
            ;;
        3)
            local backup_dir="${SCRIPT_DIR}/backups"
            if [[ -d "$backup_dir" ]]; then
                print_info "Available backups:"
                local found_backups=false
                for backup in "$backup_dir"/ddns-backup-*; do
                    if [[ -d "$backup" ]]; then
                        ls -la "$backup"
                        found_backups=true
                    fi
                done
                if ! $found_backups; then
                    print_info "No backups found."
                fi
            else
                print_info "No backups directory found."
            fi
            ;;
        0) return ;;
        *) print_error "Invalid option. Please choose 0-3." ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
}

# --- Enhanced Complete Uninstall with Verification ---
uninstall_service() {
    if [[ $HAS_WHIPTAIL == true ]]; then
        local warning_text="⚠️ COMPLETE UNINSTALL WARNING ⚠️

This will completely remove EVERYTHING:
• Systemd service and timer files
• Configuration files and API token
• Log files and IP history
• Main DDNS script and utils directory
• All backup files
• Lock files and temporary files

This action CANNOT be undone!

After uninstall, you'll need to re-download
the setup script to reinstall the service.

TIP: Use 'Reset Configuration' instead if you
just want to reconfigure existing installation."

        if ! whiptail --title "Complete Uninstall" --yesno "$warning_text" 22 70; then
            whiptail --title "Uninstall Cancelled" --msgbox "Uninstall operation cancelled." 8 50
            return
        fi
        
        if ! whiptail --title "Final Confirmation" --yesno "Are you absolutely sure?\n\nType confirmation will be required next." 10 50; then
            whiptail --title "Uninstall Cancelled" --msgbox "Uninstall operation cancelled." 8 50
            return
        fi
        
        local confirmation
        if ! confirmation=$(whiptail --title "Type YES to Confirm" --inputbox "Type 'YES' (all caps) to confirm complete uninstall:" 10 60 3>&1 1>&2 2>&3); then
            whiptail --title "Uninstall Cancelled" --msgbox "Uninstall operation cancelled." 8 50
            return
        fi
        
        if [[ "$confirmation" != "YES" ]]; then
            whiptail --title "Invalid Confirmation" --msgbox "Invalid confirmation. Uninstall cancelled.\n\nYou must type 'YES' exactly." 10 50
            return
        fi
    else
        print_warning "--- Complete Uninstall ---"
        print_warning "This will completely remove EVERYTHING including this setup script access."
        print_warning "This action cannot be undone!"
        echo ""
        print_info "What will be removed:"
        print_info "• Systemd service and timer files"
        print_info "• Configuration files and API token"
        print_info "• Log files and IP history"
        print_info "• Main DDNS script"
        print_info "• Utils directory"
        print_info "• Backup files"
        print_info "• Lock files and temporary files"
        echo ""
        print_warning "NOTE: After uninstall, you'll need to re-download the setup script"
        print_warning "      if you want to reinstall the service."
        echo ""
        print_info "TIP: If you just want to reconfigure, use option 8 'Reset Configuration' instead."
        echo ""
        
        read -p "Are you absolutely sure? Type 'YES' to confirm: " confirm_uninstall
        
        if [[ "$confirm_uninstall" != "YES" ]]; then
            print_info "Uninstall cancelled."
            echo ""
            read -p "Press Enter to continue..."
            return
        fi
    fi
    
    # Perform comprehensive uninstall
    perform_complete_uninstall
}

# --- Complete Uninstall Implementation ---
perform_complete_uninstall() {
    print_info "🗑️ Performing complete system uninstall..."
    
    local uninstall_steps=()
    local failed_steps=()
    local critical_failures=()
    
    # Step 1: Stop all running processes and services
    print_info "Step 1/10: Stopping all processes and services..."
    
    # Stop timer first
    if sudo systemctl stop "$TIMER_NAME" 2>/dev/null; then
        uninstall_steps+=("Timer stopped")
    else
        failed_steps+=("Timer stop failed (may not exist)")
    fi
    
    # Stop service
    if sudo systemctl stop "$SERVICE_NAME" 2>/dev/null; then
        uninstall_steps+=("Service stopped")
    else
        failed_steps+=("Service stop failed (may not exist)")
    fi
    
    # Kill any running DDNS processes
    local ddns_pids
    ddns_pids=$(pgrep -f "cf-ddns.sh" 2>/dev/null || true)
    if [[ -n "$ddns_pids" ]]; then
        # shellcheck disable=SC2086
        kill $ddns_pids 2>/dev/null && uninstall_steps+=("Running DDNS processes terminated")
    fi
    
    # Wait a moment for graceful shutdown
    sleep 2
    
    # Force kill if still running
    ddns_pids=$(pgrep -f "cf-ddns.sh" 2>/dev/null || true)
    if [[ -n "$ddns_pids" ]]; then
        # shellcheck disable=SC2086
        kill -9 $ddns_pids 2>/dev/null && uninstall_steps+=("Forced termination of stubborn processes")
    fi
    
    # Step 2: Disable services
    print_info "Step 2/10: Disabling systemd services..."
    
    if sudo systemctl disable "$TIMER_NAME" 2>/dev/null; then
        uninstall_steps+=("Timer disabled")
    else
        failed_steps+=("Timer disable failed (may not be enabled)")
    fi
    
    if sudo systemctl disable "$SERVICE_NAME" 2>/dev/null; then
        uninstall_steps+=("Service disabled")
    else
        failed_steps+=("Service disable failed (may not be enabled)")
    fi
    
    # Step 3: Remove systemd files with verification
    print_info "Step 3/10: Removing systemd files..."
    
    local service_path="/etc/systemd/system/$SERVICE_NAME"
    local timer_path="/etc/systemd/system/$TIMER_NAME"
    
    if [[ -f "$service_path" ]]; then
        if sudo rm -f "$service_path" 2>/dev/null; then
            if [[ ! -f "$service_path" ]]; then
                uninstall_steps+=("Service file removed")
            else
                critical_failures+=("Service file still exists after removal attempt")
            fi
        else
            critical_failures+=("Failed to remove service file")
        fi
    fi
    
    if [[ -f "$timer_path" ]]; then
        if sudo rm -f "$timer_path" 2>/dev/null; then
            if [[ ! -f "$timer_path" ]]; then
                uninstall_steps+=("Timer file removed")
            else
                critical_failures+=("Timer file still exists after removal attempt")
            fi
        else
            critical_failures+=("Failed to remove timer file")
        fi
    fi
    
    # Step 4: Reload systemd and reset failed states
    print_info "Step 4/10: Cleaning systemd configuration..."
    
    if sudo systemctl daemon-reload 2>/dev/null; then
        uninstall_steps+=("Systemd daemon reloaded")
    else
        failed_steps+=("Failed to reload systemd daemon")
    fi
    
    # Reset any failed states
    sudo systemctl reset-failed 2>/dev/null || true
    uninstall_steps+=("Failed service states reset")
    
    # Step 5: Remove main script
    print_info "Step 5/10: Removing main DDNS script..."
    
    if [[ -f "$CF_DDNS_SCRIPT" ]]; then
        if rm -f "$CF_DDNS_SCRIPT" 2>/dev/null; then
            if [[ ! -f "$CF_DDNS_SCRIPT" ]]; then
                uninstall_steps+=("Main DDNS script removed")
            else
                critical_failures+=("Main script still exists after removal")
            fi
        else
            critical_failures+=("Failed to remove main script")
        fi
    fi
    
    # Step 6: Remove utils directory with all contents
    print_info "Step 6/10: Removing configuration and data directory..."
    
    if [[ -d "$UTILS_DIR" ]]; then
        # First, try to unlock any locked files
        if [[ -d "${UTILS_DIR}/lock" ]]; then
            rm -rf "${UTILS_DIR}/lock" 2>/dev/null || true
        fi
        
        # Remove the entire utils directory
        if rm -rf "$UTILS_DIR" 2>/dev/null; then
            if [[ ! -d "$UTILS_DIR" ]]; then
                uninstall_steps+=("Utils directory completely removed")
            else
                critical_failures+=("Utils directory still exists after removal")
            fi
        else
            critical_failures+=("Failed to remove utils directory")
        fi
    fi
    
    # Step 7: Remove backup files
    print_info "Step 7/10: Removing backup files..."
    
    local backup_dir="${SCRIPT_DIR}/backups"
    if [[ -d "$backup_dir" ]]; then
        local backup_count
        backup_count=$(find "$backup_dir" -name "ddns-backup-*" -type d 2>/dev/null | wc -l)
        
        if rm -rf "$backup_dir" 2>/dev/null; then
            if [[ ! -d "$backup_dir" ]]; then
                uninstall_steps+=("Backup directory removed ($backup_count backups)")
            else
                failed_steps+=("Backup directory still exists after removal")
            fi
        else
            failed_steps+=("Failed to remove backup directory")
        fi
    fi
    
    # Step 8: Clean any remaining temporary files
    print_info "Step 8/10: Cleaning temporary files..."
    
    # Remove any temp files in script directory
    local temp_files_removed=0
    for pattern in "*.tmp" ".cf-ddns*" "cf-ddns.log*"; do
        while IFS= read -r -d '' file; do
            if rm -f "$file" 2>/dev/null; then
                ((temp_files_removed++))
            fi
        done < <(find "$SCRIPT_DIR" -maxdepth 1 -name "$pattern" -print0 2>/dev/null)
    done
    
    if [[ $temp_files_removed -gt 0 ]]; then
        uninstall_steps+=("Temporary files cleaned ($temp_files_removed files)")
    fi
    
    # Step 9: Check for any remaining traces
    print_info "Step 9/10: Scanning for remaining traces..."
    
    local remaining_traces=()
    
    # Check systemd
    if systemctl list-unit-files | grep -q "cf-ddns" 2>/dev/null; then
        remaining_traces+=("Systemd still shows cf-ddns units")
    fi
    
    # Check for any cf-ddns processes
    if pgrep -f "cf-ddns" >/dev/null 2>&1; then
        remaining_traces+=("cf-ddns processes still running")
    fi
    
    # Check for files in /tmp
    if find /tmp -name "*cf-ddns*" -o -name "*cloudflare*ddns*" 2>/dev/null | grep -q .; then
        remaining_traces+=("Temporary files found in /tmp")
        # Clean them
        find /tmp -name "*cf-ddns*" -o -name "*cloudflare*ddns*" -delete 2>/dev/null || true
        uninstall_steps+=("Cleaned temporary files from /tmp")
    fi
    
    # Step 10: Final verification
    print_info "Step 10/10: Final verification..."
    
    local verification_passed=true
    local verification_issues=()
    
    # Verify systemd files are gone
    if [[ -f "/etc/systemd/system/$SERVICE_NAME" ]] || [[ -f "/etc/systemd/system/$TIMER_NAME" ]]; then
        verification_issues+=("Systemd files still exist")
        verification_passed=false
    fi
    
    # Verify services are not running or enabled
    if systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1 || systemctl is-active "$TIMER_NAME" >/dev/null 2>&1; then
        verification_issues+=("Services still active")
        verification_passed=false
    fi
    
    if systemctl is-enabled "$SERVICE_NAME" >/dev/null 2>&1 || systemctl is-enabled "$TIMER_NAME" >/dev/null 2>&1; then
        verification_issues+=("Services still enabled")
        verification_passed=false
    fi
    
    # Verify files are gone
    if [[ -f "$CF_DDNS_SCRIPT" ]] || [[ -d "$UTILS_DIR" ]]; then
        verification_issues+=("Configuration files still exist")
        verification_passed=false
    fi
    
    # Report results
    echo ""
    print_success "🗑️ Complete uninstall finished!"
    echo ""
    
    print_info "📊 Uninstall Summary:"
    print_success "  ✅ Successful operations: ${#uninstall_steps[@]}"
    if [[ ${#failed_steps[@]} -gt 0 ]]; then
        print_warning "  ⚠️ Non-critical issues: ${#failed_steps[@]}"
    fi
    if [[ ${#critical_failures[@]} -gt 0 ]]; then
        print_error "  ❌ Critical failures: ${#critical_failures[@]}"
    fi
    if [[ ${#remaining_traces[@]} -gt 0 ]]; then
        print_warning "  🔍 Remaining traces: ${#remaining_traces[@]}"
    fi
    
    if [[ ${#uninstall_steps[@]} -gt 0 ]]; then
        echo ""
        print_info "✅ Completed operations:"
        for step in "${uninstall_steps[@]}"; do
            print_success "    • $step"
        done
    fi
    
    if [[ ${#failed_steps[@]} -gt 0 ]]; then
        echo ""
        print_warning "⚠️ Non-critical issues:"
        for step in "${failed_steps[@]}"; do
            print_warning "    • $step"
        done
    fi
    
    if [[ ${#critical_failures[@]} -gt 0 ]]; then
        echo ""
        print_error "❌ Critical failures:"
        for failure in "${critical_failures[@]}"; do
            print_error "    • $failure"
        done
        echo ""
        print_warning "Some files may require manual removal with root privileges."
    fi
    
    if [[ ${#remaining_traces[@]} -gt 0 ]]; then
        echo ""
        print_warning "🔍 Remaining traces detected:"
        for trace in "${remaining_traces[@]}"; do
            print_warning "    • $trace"
        done
    fi
    
    echo ""
    if $verification_passed && [[ ${#critical_failures[@]} -eq 0 ]]; then
        print_success "🎉 COMPLETE UNINSTALL SUCCESSFUL!"
        print_info "All DDNS components have been completely removed from your system."
        print_info "You can safely delete this setup script if no longer needed."
        echo ""
        print_info "To reinstall in the future:"
        print_info "  wget https://raw.githubusercontent.com/Jersk/cloudflare-ddns-wizard/main/setup.sh"
        print_info "  chmod +x setup.sh && ./setup.sh"
    elif [[ ${#critical_failures[@]} -eq 0 ]]; then
        print_success "✅ UNINSTALL MOSTLY SUCCESSFUL!"
        print_warning "Minor issues detected but core components removed."
        print_info "The DDNS service is no longer functional."
    else
        print_error "⚠️ UNINSTALL COMPLETED WITH ISSUES!"
        print_warning "Some components may require manual removal."
        print_info "The DDNS service should no longer be functional, but cleanup is incomplete."
        echo ""
        print_info "Manual cleanup commands (run as root):"
        print_info "  systemctl stop cf-ddns.timer cf-ddns.service"
        print_info "  systemctl disable cf-ddns.timer cf-ddns.service"
        print_info "  rm -f /etc/systemd/system/cf-ddns.*"
        print_info "  systemctl daemon-reload"
    fi
    
    echo ""
    if [[ $HAS_WHIPTAIL == true ]]; then
        whiptail --title "Uninstall Complete" --msgbox "Uninstall process completed.\n\nCheck the terminal output for detailed results." 10 60
    else
        read -p "Press Enter to exit..."
    fi
    
    exit 0
}

# --- Reset Configuration ---
reset_configuration() {
    print_warning "--- Reset Configuration (Start Over) ---"
    print_warning "This will remove configuration files and restart the setup wizard."
    print_info "The systemd service files will be kept (no need to reinstall)."
    echo ""
    print_info "What will be removed:"
    print_info "• API token and configuration files"
    print_info "• Log files and IP history"
    print_info "• Onboarding completion marker"
    echo ""
    print_info "What will be kept:"
    print_info "• Systemd service and timer files"
    print_info "• This setup script"
    print_info "• Main DDNS script (will be regenerated)"
    echo ""
    
    read -p "Are you sure? (y/N): " confirm_reset
    
    if [[ "$confirm_reset" =~ ^[Yy]$ ]]; then
        print_info "Resetting configuration..."
        
        # Stop services
        sudo systemctl stop $TIMER_NAME 2>/dev/null || true
        sudo systemctl stop $SERVICE_NAME 2>/dev/null || true
        
        # Remove configuration files but keep systemd files
        rm -f "$CONFIG_FILE" 2>/dev/null || true
        rm -f "$API_TOKEN_FILE" 2>/dev/null || true
        rm -f "${UTILS_DIR}/.onboarding_complete" 2>/dev/null || true
        rm -f "${UTILS_DIR}/cf-ddns.log" 2>/dev/null || true
        
        print_success "✅ Configuration reset complete!"
        print_info "Restarting the onboarding wizard..."
        echo ""
        
        # Restart the script to trigger onboarding
        exec "$0"
    else
        print_info "Reset cancelled."
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# --- Help & Documentation ---
show_help() {
    print_info "--- Help & Documentation ---"
    cat << 'HELP_EOF'

CLOUDFLARE DDNS UPDATER - HELP
==============================

OVERVIEW:
This script automatically updates your Cloudflare DNS records when your public IP changes.
Perfect for home servers, dynamic IP connections, and self-hosted services.

REQUIREMENTS:
• Linux system with systemd
• Root/sudo access for service installation
• Cloudflare account with domains
• API token with appropriate permissions

CLOUDFLARE API TOKEN:
Create at: https://dash.cloudflare.com/profile/api-tokens
Required permissions:
  - Zone:Zone:Read (for all zones)
  - Zone:DNS:Edit (for all zones)

FILES CREATED:
• cf-ddns.sh - Main updater script
• utils/config.env - Configuration file
• utils/.cloudflare_api_token - API token (secure)
• utils/cf-ddns.log - Execution logs
• /etc/systemd/system/cf-ddns.service - Systemd service
• /etc/systemd/system/cf-ddns.timer - Systemd timer

DEFAULT BEHAVIOR:
• Checks IP every 5 minutes
• Updates DNS when IP changes
• Starts automatically on boot
• Logs all activities

COMMON COMMANDS:
• View logs: journalctl -u cf-ddns.service
• Check status: systemctl status cf-ddns.timer
• Manual run: ./cf-ddns.sh
• Stop service: sudo systemctl stop cf-ddns.timer

TROUBLESHOOTING:
1. Check API token permissions
2. Verify domain is in Cloudflare
3. Check network connectivity
4. Review logs for errors
5. Test manual execution

For more help, check the logs or run a manual test.

HELP_EOF
    
    echo ""
    read -p "Press Enter to continue..."
}

# --- Run Onboarding Function ---
run_onboarding() {
    guided_onboarding
}

# --- Create Systemd Files ---
create_systemd_files() {
    local run_interval="${RUN_INTERVAL:-5min}"
    
    print_info "Creating systemd service file..."
    
    # Create the service file
    sudo tee "/etc/systemd/system/$SERVICE_NAME" > /dev/null << SERVICE_EOF
[Unit]
Description=Cloudflare Dynamic DNS Updater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$CF_DDNS_SCRIPT
User=$USER
Group=$USER
WorkingDirectory=$SCRIPT_DIR
Environment=HOME=$HOME
Environment=USER=$USER
StandardOutput=journal
StandardError=journal
UMask=0077

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    print_info "Creating systemd timer file..."
    
    # Create the timer file  
    sudo tee "/etc/systemd/system/$TIMER_NAME" > /dev/null << TIMER_EOF
[Unit]
Description=Run Cloudflare DDNS Updater
Requires=$SERVICE_NAME

[Timer]
OnBootSec=2min
OnUnitActiveSec=$run_interval
Persistent=true

[Install]
WantedBy=timers.target
TIMER_EOF

    # Reload systemd and set permissions
    sudo systemctl daemon-reload
    
    print_success "Systemd files created successfully!"
}

# --- Zone Selection Menu ---
# Presents a checklist of zones and preselects ones from previous
# configurations so they can be easily deselected or updated.
select_target_zones() {
    local zones=("$@")
    local prev_selected=("${PREV_SELECTED_ZONES[@]}")
    SELECTED_ZONES=()

    if [[ $HAS_WHIPTAIL == true ]]; then
        local checklist_args=()
        for i in "${!zones[@]}"; do
            local state=OFF
            for z in "${prev_selected[@]}"; do
                if [[ "$z" == "${zones[$i]}" ]]; then
                    state=ON
                    break
                fi
            done
            checklist_args+=("$((i+1))" "${zones[$i]}" "$state")
        done

        local choices
        choices=$(whiptail --title "Select Zones" --checklist "Choose zones to manage (space to toggle):" 20 70 10 \
            "${checklist_args[@]}" 3>&1 1>&2 2>&3)
        local exit_status=$?
        if [[ $exit_status -ne 0 ]]; then
            return 1
        fi

        for choice in $choices; do
            choice=$(echo "$choice" | tr -d '"')
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 && $choice -le ${#zones[@]} ]]; then
                SELECTED_ZONES+=("${zones[$((choice-1))]}")
            fi
        done
    else
        print_info "Select zones to manage:"
        for i in "${!zones[@]}"; do
            echo "  [$((i+1))] ${zones[$i]}"
        done
        echo "  [0] ⬅️ Back to previous menu"

        read -p "Enter zone numbers (space-separated, 'all', or 0=back): " zone_selection

        if [[ "$zone_selection" == "0" ]]; then
            return 1
        elif [[ "$zone_selection" == "all" ]]; then
            SELECTED_ZONES=("${zones[@]}")
        else
            for num in $zone_selection; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 && $num -le ${#zones[@]} ]]; then
                    SELECTED_ZONES+=("${zones[$((num-1))]}")
                fi
            done
        fi
    fi

    if [[ ${#SELECTED_ZONES[@]} -eq 0 ]]; then
        print_error "No valid zones selected."
        return 1
    fi

    return 0
}

# --- Smart DNS Record Selection with IP Comparison ---
select_dns_records_for_zone_with_ip_check() {
    local zone_id="$1"
    local zone_name="$2"
    local current_public_ip="$3"
    
    print_info "Fetching A records for $zone_name..."
    
    # Load API token
    local api_token
    if [[ -f "$API_TOKEN_FILE" ]]; then
        api_token=$(<"$API_TOKEN_FILE")
    else
        print_error "API token file not found"
        return 1
    fi
    
    # Fetch A records for this zone
    local records_data
    if ! records_data=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=A" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json"); then
        print_error "Failed to fetch DNS records for $zone_name"
        return 1
    fi
    
    # Check if request was successful
    local success
    success=$(echo "$records_data" | jq -r '.success')
    
    if [[ "$success" != "true" ]]; then
        print_error "API request failed for $zone_name:"
        echo "$records_data" | jq -r '.errors[]?.message // "Unknown error"'
        return 1
    fi
    
    # Parse records
    local record_names=()
    local record_ips=()
    local record_ids=()
    
    while IFS=$'\t' read -r id name content; do
        if [[ -n "$id" && -n "$name" && -n "$content" ]]; then
            record_ids+=("$id")
            record_names+=("$name")
            record_ips+=("$content")
        fi
    done < <(echo "$records_data" | jq -r '.result[]? | "\(.id)\t\(.name)\t\(.content)"')
    
    if [[ ${#record_names[@]} -eq 0 ]]; then
        print_warning "No A records found for $zone_name"
        return 0
    fi
    
    print_success "Found ${#record_names[@]} A record(s) for $zone_name"
    echo ""
    
    local records_to_monitor=0
    local different_ip_records=0

    if [[ $HAS_WHIPTAIL == true ]]; then
        local pre_selected_ids=()
        for entry in "${PREV_SELECTED_RECORDS[@]}"; do
            IFS=':' read -r z_id r_id r_name r_type <<< "$entry"
            if [[ "$z_id" == "$zone_id" ]]; then
                pre_selected_ids+=("$r_id")
            fi
        done

        local checklist_args=()
        for i in "${!record_names[@]}"; do
            local label="${record_names[$i]} (${record_ips[$i]})"
            local state=OFF
            for pid in "${pre_selected_ids[@]}"; do
                if [[ "$pid" == "${record_ids[$i]}" ]]; then
                    state=ON
                    break
                fi
            done
            checklist_args+=("$((i+1))" "$label" "$state")
        done

        local choices
        choices=$(whiptail --title "Records for $zone_name" --checklist "Select records to monitor" 20 70 12 \
            "${checklist_args[@]}" 3>&1 1>&2 2>&3)
        local exit_status=$?
        if [[ $exit_status -ne 0 ]]; then
            return 2
        fi

        for choice in $choices; do
            choice=$(echo "$choice" | tr -d '"')
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 && $choice -le ${#record_names[@]} ]]; then
                local idx=$((choice-1))
                SELECTED_RECORDS+=("$zone_id:${record_ids[$idx]}:${record_names[$idx]}:A")
                records_to_monitor=$((records_to_monitor + 1))
                if [[ -n "$current_public_ip" && "${record_ips[$idx]}" != "$current_public_ip" ]]; then
                    different_ip_records=$((different_ip_records + 1))
                fi
            fi
        done
    else
        # CLI fallback
        for i in "${!record_names[@]}"; do
            local record_name="${record_names[$i]}"
            local record_ip="${record_ips[$i]}"
            local record_id="${record_ids[$i]}"

            echo ""
            print_info "Record: $record_name"
            print_info "Current IP: $record_ip"

            local ip_status=""

            if [[ -n "$current_public_ip" ]]; then
                if [[ "$record_ip" == "$current_public_ip" ]]; then
                    ip_status=" ${COLOR_GREEN}[matches current public IP]${COLOR_RESET}"
                    print_success "✓ This record already points to your current public IP ($current_public_ip)"
                else
                    ip_status=" ${COLOR_YELLOW}[different from current public IP: $current_public_ip]${COLOR_RESET}"
                    print_warning "⚠ This record points to a different IP than your current public IP"
                    different_ip_records=$((different_ip_records + 1))
                fi
            else
                ip_status=" ${COLOR_CYAN}[current public IP unknown]${COLOR_RESET}"
            fi

            echo -e "Status:$ip_status"
            echo ""

            while true; do
                print_question "Do you want to monitor and auto-update this record? (y/n/b=back/s=skip all): "
                read -r choice

                case "$choice" in
                    [Yy]|[Yy][Ee][Ss])
                        SELECTED_RECORDS+=("$zone_id:$record_id:$record_name:A")
                        print_success "✓ Added $record_name to monitoring list"
                        records_to_monitor=$((records_to_monitor + 1))
                        break
                        ;;
                    [Nn]|[Nn][Oo])
                        print_info "○ Skipping $record_name"
                        break
                        ;;
                    [Bb]|[Bb][Aa][Cc][Kk])
                        print_info "Going back to zone selection..."
                        return 2
                        ;;
                    [Ss]|[Ss][Kk][Ii][Pp])
                        print_info "Skipping remaining records for $zone_name"
                        return 0
                        ;;
                    *)
                        print_error "Please enter y (yes), n (no), b (back), or s (skip all)"
                        continue
                        ;;
                esac
            done
        done
    fi
    
    echo ""
    if [[ $records_to_monitor -gt 0 ]]; then
        print_success "✓ Selected $records_to_monitor record(s) for monitoring in $zone_name"
        if [[ $different_ip_records -gt 0 ]]; then
            print_info "Note: $different_ip_records record(s) have different IPs and will be updated on first run"
        fi
    else
        print_warning "No records selected for monitoring in $zone_name"
    fi
    
    return 0
}

generate_advanced_config() {
    DOMAIN_MODE="SPECIFIC"
    create_config_file_with_settings
}

show_configuration_summary() {
    print_info "Configuration Summary:"
    print_info "Selected Zones: ${#SELECTED_ZONES[@]}"
    print_info "Selected Records: ${#SELECTED_RECORDS[@]}"
}

# --- Enhanced Cleanup with Comprehensive Detection ---
cleanup_partial_installation() {
    print_info "🔍 Performing comprehensive system analysis..."
    
    local needs_cleanup=false
    local cleanup_items=()
    local critical_issues=()
    local systemd_issues=()
    
    # 1. Check script files integrity
    if [[ -f "$CF_DDNS_SCRIPT" ]]; then
        if [[ ! -x "$CF_DDNS_SCRIPT" ]]; then
            needs_cleanup=true
            cleanup_items+=("Main script exists but is not executable")
        elif [[ ! -s "$CF_DDNS_SCRIPT" ]]; then
            needs_cleanup=true
            cleanup_items+=("Main script is empty or corrupted")
        else
            # Check if script has proper shebang
            local first_line
            first_line=$(head -n1 "$CF_DDNS_SCRIPT" 2>/dev/null)
            if [[ ! "$first_line" =~ ^#!/ ]]; then
                needs_cleanup=true
                cleanup_items+=("Main script has invalid shebang")
            fi
        fi
    fi
    
    # 2. Check API token file integrity
    if [[ -f "$API_TOKEN_FILE" ]]; then
        if [[ ! -s "$API_TOKEN_FILE" ]]; then
            needs_cleanup=true
            cleanup_items+=("API token file exists but is empty")
        else
            # Check token format and permissions
            local token_perms token_owner
            token_perms=$(stat -c "%a" "$API_TOKEN_FILE" 2>/dev/null || echo "000")
            token_owner=$(stat -c "%U" "$API_TOKEN_FILE" 2>/dev/null || echo "unknown")
            
            if [[ "$token_perms" != "600" ]]; then
                needs_cleanup=true
                cleanup_items+=("API token has incorrect permissions ($token_perms instead of 600)")
            fi
            
            # Check token content validity (basic format check)
            local token_content token_length
            token_content=$(tr -d '\n\r[:space:]' < "$API_TOKEN_FILE" 2>/dev/null)
            token_length=${#token_content}
            
            if [[ $token_length -lt 20 || $token_length -gt 100 ]]; then
                needs_cleanup=true
                cleanup_items+=("API token appears to have invalid format (length: $token_length)")
            fi
        fi
    fi
    
    # 3. Check configuration file integrity
    if [[ -f "$CONFIG_FILE" ]]; then
        # Test if config can be sourced
        if ! (source "$CONFIG_FILE" >/dev/null 2>&1); then
            needs_cleanup=true
            cleanup_items+=("Configuration file is corrupted or has syntax errors")
        else
            # Source config and validate required variables
            # shellcheck source=utils/config.env
            source "$CONFIG_FILE" 2>/dev/null || true
            
            # Check domain mode consistency
            case "${DOMAIN_MODE:-SIMPLE}" in
                "SIMPLE")
                    if [[ -z "${DOMAIN:-}" || -z "${SUBDOMAIN:-}" ]]; then
                        needs_cleanup=true
                        cleanup_items+=("SIMPLE mode selected but DOMAIN or SUBDOMAIN not configured")
                    fi
                    ;;
                "SPECIFIC")
                    local records_count=0
                    if declare -p SELECTED_RECORDS 2>/dev/null | grep -q '^declare -a'; then
                        records_count=${#SELECTED_RECORDS[@]}
                    fi
                    if [[ $records_count -eq 0 ]]; then
                        needs_cleanup=true
                        cleanup_items+=("SPECIFIC mode selected but no records configured")
                    fi
                    ;;
                "ALL")
                    # ALL mode doesn't require specific validation
                    ;;
                *)
                    needs_cleanup=true
                    cleanup_items+=("Invalid DOMAIN_MODE: ${DOMAIN_MODE:-undefined}")
                    ;;
            esac
            
            # Check IP services configuration
            if [[ -z "${IP_SERVICES:-}" ]] && ! declare -p IP_SERVICES 2>/dev/null | grep -q '^declare -a'; then
                needs_cleanup=true
                cleanup_items+=("IP_SERVICES not properly configured")
            fi
        fi
    fi
    
    # 4. Check systemd files integrity and consistency
    local service_exists=false
    local timer_exists=false
    local service_enabled=false
    local timer_enabled=false
    local service_active=false
    local timer_active=false
    
    if [[ -f "/etc/systemd/system/$SERVICE_NAME" ]]; then
        service_exists=true
        # Check if service file is valid
        if ! systemctl cat "$SERVICE_NAME" >/dev/null 2>&1; then
            systemd_issues+=("Service file exists but is invalid")
        fi
        
        # Check if service points to correct script
        local exec_start
        exec_start=$(systemctl cat "$SERVICE_NAME" 2>/dev/null | grep "^ExecStart=" | cut -d'=' -f2- | tr -d ' ')
        if [[ "$exec_start" != "$CF_DDNS_SCRIPT" ]]; then
            systemd_issues+=("Service ExecStart points to wrong script: $exec_start")
        fi
    fi
    
    if [[ -f "/etc/systemd/system/$TIMER_NAME" ]]; then
        timer_exists=true
        if ! systemctl cat "$TIMER_NAME" >/dev/null 2>&1; then
            systemd_issues+=("Timer file exists but is invalid")
        fi
    fi
    
    # Check service states
    if systemctl is-enabled "$SERVICE_NAME" >/dev/null 2>&1; then
        service_enabled=true
    fi
    
    if systemctl is-enabled "$TIMER_NAME" >/dev/null 2>&1; then
        timer_enabled=true
    fi
    
    if systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1; then
        service_active=true
    fi
    
    if systemctl is-active "$TIMER_NAME" >/dev/null 2>&1; then
        timer_active=true
    fi
    
    # 5. Check for orphaned systemd files
    if ($service_exists || $timer_exists) && ([[ ! -f "$CONFIG_FILE" ]] || [[ ! -f "$API_TOKEN_FILE" ]] || [[ ! -f "$CF_DDNS_SCRIPT" ]]); then
        needs_cleanup=true
        systemd_issues+=("Systemd files exist but configuration files are missing")
    fi
    
    # 6. Check for inconsistent states
    if $timer_enabled && [[ ! -f "$CF_DDNS_SCRIPT" ]]; then
        needs_cleanup=true
        systemd_issues+=("Timer is enabled but main script doesn't exist")
    fi
    
    if $service_active && [[ ! -f "$API_TOKEN_FILE" ]]; then
        needs_cleanup=true
        critical_issues+=("Service is running but API token is missing")
    fi
    
    # 7. Check for permission issues that could cause failures
    if [[ -d "$UTILS_DIR" ]]; then
        local utils_perms utils_owner
        utils_perms=$(stat -c "%a" "$UTILS_DIR" 2>/dev/null || echo "000")
        utils_owner=$(stat -c "%U" "$UTILS_DIR" 2>/dev/null || echo "unknown")
        
        if [[ "$utils_perms" != "755" ]] && [[ "$utils_perms" != "750" ]]; then
            cleanup_items+=("Utils directory has unusual permissions: $utils_perms")
        fi
    fi
    
    # 8. Check for lock files that might indicate crashed processes
    if [[ -f "${UTILS_DIR}/lock/cf-ddns.lock" ]]; then
        local lock_pid
        if lock_pid=$(lsof "${UTILS_DIR}/lock/cf-ddns.lock" 2>/dev/null | awk 'NR>1 {print $2}' | head -1); then
            if [[ -n "$lock_pid" ]] && ! ps -p "$lock_pid" >/dev/null 2>&1; then
                cleanup_items+=("Stale lock file detected (PID $lock_pid no longer exists)")
            fi
        fi
    fi
    
    # 9. Combine all issues
    if [[ ${#systemd_issues[@]} -gt 0 ]]; then
        needs_cleanup=true
        cleanup_items+=("${systemd_issues[@]}")
    fi
    
    if [[ ${#critical_issues[@]} -gt 0 ]]; then
        needs_cleanup=true
        cleanup_items+=("${critical_issues[@]}")
    fi
    
    # 10. Report findings
    if $needs_cleanup; then
        print_warning "🚨 System integrity issues detected:"
        echo ""
        print_info "📋 Issues found:"
        for item in "${cleanup_items[@]}"; do
            print_warning "  • $item"
        done
        
        echo ""
        print_info "🔧 Recommended actions:"
        print_info "  • Stop all running services"
        print_info "  • Remove corrupted/incomplete files"
        print_info "  • Clean systemd configuration"
        print_info "  • Reset file permissions"
        print_info "  • Remove stale lock files"
        echo ""
        
        if [[ $HAS_WHIPTAIL == true ]]; then
            if whiptail --title "System Cleanup Required" --yesno "System integrity issues detected.\n\nPerform comprehensive cleanup now?\n\nThis will:\n• Stop all services\n• Remove corrupted files\n• Reset permissions\n• Clean systemd files" 15 60; then
                perform_comprehensive_cleanup
            else
                print_warning "⚠️ Cleanup skipped. You may encounter issues during operation."
                return 1
            fi
        else
            read -p "Perform comprehensive cleanup now? (Y/n): " cleanup_choice
            if [[ ! "$cleanup_choice" =~ ^[Nn]$ ]]; then
                perform_comprehensive_cleanup
            else
                print_warning "⚠️ Cleanup skipped. You may encounter issues during operation."
                return 1
            fi
        fi
    else
        print_success "✅ System integrity check passed - no issues detected"
        return 0
    fi
}

# --- Comprehensive Cleanup Implementation ---
perform_comprehensive_cleanup() {
    print_info "🧹 Performing comprehensive system cleanup..."
    
    local cleanup_steps=()
    local failed_steps=()
    
    # Step 1: Stop all services and processes
    print_info "Step 1/8: Stopping services and processes..."
    if sudo systemctl stop "$TIMER_NAME" 2>/dev/null; then
        cleanup_steps+=("Timer stopped")
    else
        failed_steps+=("Failed to stop timer (may not exist)")
    fi
    
    if sudo systemctl stop "$SERVICE_NAME" 2>/dev/null; then
        cleanup_steps+=("Service stopped")
    else
        failed_steps+=("Failed to stop service (may not exist)")
    fi
    
    # Step 2: Disable services
    print_info "Step 2/8: Disabling services..."
    if sudo systemctl disable "$TIMER_NAME" 2>/dev/null; then
        cleanup_steps+=("Timer disabled")
    else
        failed_steps+=("Failed to disable timer (may not be enabled)")
    fi
    
    if sudo systemctl disable "$SERVICE_NAME" 2>/dev/null; then
        cleanup_steps+=("Service disabled")
    else
        failed_steps+=("Failed to disable service (may not be enabled)")
    fi
    
    # Step 3: Remove systemd files
    print_info "Step 3/8: Cleaning systemd files..."
    if sudo rm -f "/etc/systemd/system/$SERVICE_NAME" 2>/dev/null; then
        cleanup_steps+=("Service file removed")
    fi
    
    if sudo rm -f "/etc/systemd/system/$TIMER_NAME" 2>/dev/null; then
        cleanup_steps+=("Timer file removed")
    fi
    
    # Reload systemd daemon
    if sudo systemctl daemon-reload 2>/dev/null; then
        cleanup_steps+=("Systemd daemon reloaded")
    else
        failed_steps+=("Failed to reload systemd daemon")
    fi
    
    # Reset failed services
    sudo systemctl reset-failed 2>/dev/null || true
    
    # Step 4: Remove corrupted configuration files
    print_info "Step 4/8: Removing corrupted files..."
    
    # Remove corrupted main script
    if [[ -f "$CF_DDNS_SCRIPT" ]]; then
        if [[ ! -x "$CF_DDNS_SCRIPT" ]] || [[ ! -s "$CF_DDNS_SCRIPT" ]]; then
            rm -f "$CF_DDNS_SCRIPT" 2>/dev/null && cleanup_steps+=("Corrupted main script removed")
        fi
    fi
    
    # Remove empty or corrupted API token
    if [[ -f "$API_TOKEN_FILE" ]] && [[ ! -s "$API_TOKEN_FILE" ]]; then
        rm -f "$API_TOKEN_FILE" 2>/dev/null && cleanup_steps+=("Empty API token file removed")
    fi
    
    # Test and remove corrupted config
    if [[ -f "$CONFIG_FILE" ]]; then
        if ! (source "$CONFIG_FILE" >/dev/null 2>&1); then
            rm -f "$CONFIG_FILE" 2>/dev/null && cleanup_steps+=("Corrupted config file removed")
        fi
    fi
    
    # Step 5: Clean lock files and temporary files
    print_info "Step 5/8: Cleaning lock and temporary files..."
    if [[ -d "${UTILS_DIR}/lock" ]]; then
        rm -rf "${UTILS_DIR}/lock" 2>/dev/null && cleanup_steps+=("Lock directory cleaned")
    fi
    
    # Remove any temporary files
    find "$UTILS_DIR" -name "*.tmp" -delete 2>/dev/null && cleanup_steps+=("Temporary files removed")
    
    # Step 6: Fix directory permissions
    print_info "Step 6/8: Fixing directory permissions..."
    if [[ -d "$UTILS_DIR" ]]; then
        # Determine correct user
        local target_user target_group
        if [[ -n "${SUDO_USER:-}" ]]; then
            target_user="$SUDO_USER"
            target_group="$SUDO_USER"
        else
            target_user="$USER"
            target_group="$USER"
        fi
        
        # Fix ownership and permissions
        if [[ "$EUID" -eq 0 ]]; then
            chown -R "$target_user:$target_group" "$UTILS_DIR" 2>/dev/null && cleanup_steps+=("Directory ownership fixed")
        fi
        
        chmod 755 "$UTILS_DIR" 2>/dev/null && cleanup_steps+=("Directory permissions fixed")
        
        # Fix file permissions
        if [[ -f "$API_TOKEN_FILE" ]]; then
            chmod 600 "$API_TOKEN_FILE" 2>/dev/null && cleanup_steps+=("API token permissions fixed")
        fi
        
        if [[ -f "$CONFIG_FILE" ]]; then
            chmod 644 "$CONFIG_FILE" 2>/dev/null && cleanup_steps+=("Config file permissions fixed")
        fi
    fi
    
    # Step 7: Remove onboarding completion marker to force fresh setup
    print_info "Step 7/8: Resetting setup state..."
    rm -f "${UTILS_DIR}/.onboarding_complete" 2>/dev/null && cleanup_steps+=("Setup completion marker removed")
    
    # Step 8: Clean log files with rotation
    print_info "Step 8/8: Cleaning and rotating logs..."
    if [[ -f "${UTILS_DIR}/cf-ddns.log" ]]; then
        # Keep only last 100 lines if log is very large
        local log_lines
        log_lines=$(wc -l < "${UTILS_DIR}/cf-ddns.log" 2>/dev/null || echo 0)
        if [[ $log_lines -gt 1000 ]]; then
            tail -n 100 "${UTILS_DIR}/cf-ddns.log" > "${UTILS_DIR}/cf-ddns.log.tmp" 2>/dev/null
            mv "${UTILS_DIR}/cf-ddns.log.tmp" "${UTILS_DIR}/cf-ddns.log" 2>/dev/null
            cleanup_steps+=("Log file rotated and cleaned")
        fi
    fi
    
    # Final verification
    print_info "🔍 Performing post-cleanup verification..."
    local verification_passed=true
    
    # Check that systemd files are gone
    if [[ -f "/etc/systemd/system/$SERVICE_NAME" ]] || [[ -f "/etc/systemd/system/$TIMER_NAME" ]]; then
        failed_steps+=("Some systemd files still exist after cleanup")
        verification_passed=false
    fi
    
    # Check that services are not running
    if systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1 || systemctl is-active "$TIMER_NAME" >/dev/null 2>&1; then
        failed_steps+=("Some services are still running after cleanup")
        verification_passed=false
    fi
    
    # Report results
    echo ""
    print_success "✅ Comprehensive cleanup completed!"
    echo ""
    print_info "📊 Cleanup Summary:"
    print_success "  ✅ Successful operations: ${#cleanup_steps[@]}"
    if [[ ${#failed_steps[@]} -gt 0 ]]; then
        print_warning "  ⚠️ Issues encountered: ${#failed_steps[@]}"
    fi
    
    if [[ ${#cleanup_steps[@]} -gt 0 ]]; then
        echo ""
        print_info "✅ Completed operations:"
        for step in "${cleanup_steps[@]}"; do
            print_success "    • $step"
        done
    fi
    
    if [[ ${#failed_steps[@]} -gt 0 ]]; then
        echo ""
        print_warning "⚠️ Issues encountered:"
        for step in "${failed_steps[@]}"; do
            print_warning "    • $step"
        done
        echo ""
        print_info "💡 These issues are typically non-critical and won't prevent fresh installation."
    fi
    
    echo ""
    if $verification_passed; then
        print_success "🎉 System is now clean and ready for fresh installation!"
    else
        print_warning "⚠️ Some cleanup operations didn't complete perfectly, but you can proceed with installation."
        print_info "If problems persist, you may need to manually remove remaining files with root privileges."
    fi
    
    echo ""
    print_info "🚀 You can now run the onboarding wizard for a fresh installation."
    return 0
}

# Check if we have the necessary dependencies first
check_dependencies

# Load any saved selections for zone and record menus. This allows
# previously configured zones and records to appear preselected when
# re-entering the TUI configuration screens.
load_saved_selections

# Clean up any partial installations before proceeding
cleanup_partial_installation

# Check if this is the first run or configuration is incomplete
if is_first_time_setup; then
    print_info "=========================================="
    print_info "🚀 WELCOME TO CLOUDFLARE DDNS UPDATER"
    print_info "=========================================="
    echo ""
    print_info "This appears to be your first time running this script,"
    print_info "or your previous configuration is incomplete."
    print_info "Let's get you set up with a guided onboarding process!"
    echo ""
    
    # Ask user if they want to run onboarding or go to menu
    echo "Options:"
    echo "  [1] 🚀 Run guided onboarding wizard (recommended)"
    echo "  [2] 🔧 Go to configuration menu (for advanced users)"
    echo ""
    
    while true; do
        read -p "Choose option (1 or 2): " setup_choice
        case $setup_choice in
            1)
                print_info "Starting guided onboarding wizard..."
                echo ""
                if guided_onboarding; then
                    # Onboarding completed successfully
                    echo ""
                    print_success "✅ Onboarding completed successfully!"
                    print_info "You can now manage your DDNS service using the menu below."
                    echo ""
                    break
                else
                    # User chose to go back, restart the main selection
                    echo ""
                    print_info "Restarting main options..."
                    echo ""
                    continue
                fi
                ;;
            2)
                print_info "Going to configuration menu..."
                echo ""
                edit_config
                echo ""
                break
                ;;
            *)
                print_error "Please enter 1 or 2."
                ;;
        esac
    done
fi

# --- Main menu loop ---
while true; do
    if ! show_menu; then
        print_info "Goodbye! 👋"
        exit 0
    fi
    choice="$MENU_CHOICE"
    case $choice in
        1)
            if ! edit_config; then
                # User went back from config menu, continue main loop
                continue
            fi
            ;;
        2) manage_service ;;
        3) view_logs ;;
        4) run_manual_test ;;
        5) test_system_resilience ;;
        6) backup_restore ;;
        7) uninstall_service ;;
        8) reset_configuration ;;
        9) show_help ;;
        0) 
            print_info "Goodbye! 👋"
            exit 0
            ;;
        *)
            print_error "Invalid option. Please choose 0-9."
            ;;
    esac
done
