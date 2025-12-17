#!/bin/bash
# ECS Task Connection Script
# Handles AWS authentication and connects to ECS tasks via AWS Systems Manager Session Manager

# Enable DEBUG mode if DEBUG environment variable is set to 1 or script is run with --debug
if [ "$1" == "--debug" ] || [ "$1" == "-d" ] || [ "${DEBUG:-0}" == "1" ]; then
    export DEBUG=1
    set -x  # Print commands and their arguments as they are executed
    echo "🔍 DEBUG MODE ENABLED"
    echo "===================="
    echo ""
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Debug logging function
debug_log() {
    if [ "${DEBUG:-0}" == "1" ]; then
        echo -e "${CYAN}[DEBUG] $1${NC}" >&2
    fi
}

# Debug command execution
debug_cmd() {
    if [ "${DEBUG:-0}" == "1" ]; then
        echo -e "${CYAN}[DEBUG] Executing: $@${NC}" >&2
    fi
    "$@"
}

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# AWS CLI wrapper function - handles aws-vault if enabled
AWS_VAULT_ENABLED=false
AWS_VAULT_PROFILE=""

aws_cmd() {
    if [ "$AWS_VAULT_ENABLED" == "true" ] && [ ! -z "$AWS_VAULT_PROFILE" ]; then
        aws-vault exec "$AWS_VAULT_PROFILE" -- aws "$@"
    else
        aws "$@"
    fi
}

# Helper function to read input and clean carriage returns
read_input() {
    local prompt="$1"
    local var_name="$2"
    IFS= read -r -p "$prompt" "$var_name"
    # Remove carriage returns and newlines
    eval "$var_name=\$(echo \"\$$var_name\" | tr -d '\r\n')"
}

# Function to check and install Session Manager plugin
check_and_install_session_manager_plugin() {
    if command_exists session-manager-plugin; then
        return 0
    fi
    
    print_warning "Session Manager plugin not found."
    echo ""
    print_info "The Session Manager plugin is required to connect to ECS tasks via SSM."
    echo ""
    
    OS_TYPE=$(uname -s)
    
    if [ "$OS_TYPE" == "Darwin" ]; then
        # macOS
        if command_exists brew; then
            print_info "Detected macOS with Homebrew. Installing Session Manager plugin..."
            echo ""
            read_input "Install Session Manager plugin now? (y/n, default: y): " INSTALL_PLUGIN
            if [ "$INSTALL_PLUGIN" != "n" ] && [ "$INSTALL_PLUGIN" != "N" ]; then
                print_info "Running: brew install --cask session-manager-plugin"
                if brew install --cask session-manager-plugin; then
                    print_success "Session Manager plugin installed successfully!"
                    return 0
                else
                    print_error "Failed to install Session Manager plugin via Homebrew."
                    print_info "Please install manually:"
                    echo "  brew install --cask session-manager-plugin"
                    return 1
                fi
            else
                print_info "Skipping installation. You can install it later with:"
                echo "  brew install --cask session-manager-plugin"
                return 1
            fi
        else
            print_info "Homebrew not found. Please install Session Manager plugin manually:"
            echo ""
            echo "Option 1: Install Homebrew first, then:"
            echo "  brew install --cask session-manager-plugin"
            echo ""
            echo "Option 2: Download and install manually:"
            echo "  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
            return 1
        fi
    elif [ "$OS_TYPE" == "Linux" ]; then
        # Linux
        print_info "Detected Linux. Please install Session Manager plugin manually:"
        echo ""
        echo "Download and install from:"
        echo "  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
        return 1
    else
        print_error "Unsupported operating system: $OS_TYPE"
        return 1
    fi
}

echo "=========================================="
echo "  AWS ECS Task Connection Tool"
echo "=========================================="
echo ""

# Check if region is set via environment variable, otherwise use default
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-1"
fi

print_info "Step 1: AWS Credentials Configuration"
echo ""

# Check for existing AWS profiles first
AWS_CREDENTIALS_FILE="$HOME/.aws/credentials"
AWS_CONFIG_FILE="$HOME/.aws/config"
HAS_PROFILES=false

if [ -f "$AWS_CREDENTIALS_FILE" ] || [ -f "$AWS_CONFIG_FILE" ]; then
    # Extract profile names from credentials file
    if [ -f "$AWS_CREDENTIALS_FILE" ]; then
        PROFILES=$(grep -E "^\[.*\]" "$AWS_CREDENTIALS_FILE" | sed 's/\[//g' | sed 's/\]//g' | grep -v "^default$" || echo "")
    fi
    
    # Also check config file for profiles
    if [ -f "$AWS_CONFIG_FILE" ]; then
        CONFIG_PROFILES=$(grep -E "^\[profile .*\]" "$AWS_CONFIG_FILE" | sed 's/\[profile //g' | sed 's/\]//g' || echo "")
        if [ ! -z "$CONFIG_PROFILES" ]; then
            if [ ! -z "$PROFILES" ]; then
                PROFILES="$PROFILES"$'\n'"$CONFIG_PROFILES"
            else
                PROFILES="$CONFIG_PROFILES"
            fi
        fi
    fi
    
    # Check for default profile
    if [ -f "$AWS_CREDENTIALS_FILE" ] && grep -q "^\[default\]" "$AWS_CREDENTIALS_FILE"; then
        if [ -z "$PROFILES" ]; then
            PROFILES="default"
        else
            PROFILES="default"$'\n'"$PROFILES"
        fi
    fi
    
    # Remove duplicates and sort
    if [ ! -z "$PROFILES" ]; then
        PROFILES=$(echo "$PROFILES" | sort -u)
        HAS_PROFILES=true
    fi
fi

# Unified authentication menu
USE_AWS_VAULT=false
AWS_VAULT_ENABLED=false
USE_MANUAL_CREDS=false
REGION_FROM_PROFILE=false

echo "How would you like to authenticate?"
OPTION_NUM=1

# Check if aws-vault is available
if command_exists aws-vault; then
    echo "$OPTION_NUM) Use aws-vault (recommended for security)"
    OPTION_NUM=$((OPTION_NUM + 1))
    HAS_AWS_VAULT=true
else
    HAS_AWS_VAULT=false
fi

# Check if AWS profiles are available
if [ "$HAS_PROFILES" == "true" ]; then
    echo "$OPTION_NUM) Use AWS Profile (from ~/.aws/credentials or ~/.aws/config)"
    OPTION_NUM=$((OPTION_NUM + 1))
fi

echo "$OPTION_NUM) Enter credentials manually (Access Key, Secret Key, Session Token)"
echo ""

# Show installation advice if aws-vault is not installed
if [ "$HAS_AWS_VAULT" == "false" ]; then
    print_info "💡 Tip: aws-vault is not installed. For more secure credential management, install it:"
    OS_TYPE=$(uname -s)
    if [ "$OS_TYPE" == "Darwin" ]; then
        echo "   brew install aws-vault"
    elif [ "$OS_TYPE" == "Linux" ]; then
        echo "   See: https://github.com/99designs/aws-vault#installation"
    else
        echo "   See: https://github.com/99designs/aws-vault#installation"
    fi
    echo ""
fi

# Determine max option number
if [ "$HAS_AWS_VAULT" == "true" ] && [ "$HAS_PROFILES" == "true" ]; then
    MAX_OPTION=3
    while true; do
        read_input "Select option (1, 2, or 3): " AUTH_CHOICE
        # Validate AUTH_CHOICE - must be numeric only
        if [ -z "$AUTH_CHOICE" ]; then
            print_error "Input cannot be empty. Please select 1, 2, or 3."
            continue
        fi
        if [[ ! "$AUTH_CHOICE" =~ ^[0-9]+$ ]]; then
            print_error "Invalid input: '$AUTH_CHOICE'. Please enter only numbers (1, 2, or 3)."
            continue
        fi
        if [ "$AUTH_CHOICE" -lt 1 ] || [ "$AUTH_CHOICE" -gt 3 ]; then
            print_error "Invalid option: '$AUTH_CHOICE'. Please select 1, 2, or 3."
            continue
        fi
        break
    done
elif [ "$HAS_AWS_VAULT" == "true" ] && [ "$HAS_PROFILES" == "false" ]; then
    MAX_OPTION=2
    while true; do
        read_input "Select option (1 or 2): " AUTH_CHOICE
        # Validate AUTH_CHOICE - must be numeric only
        if [ -z "$AUTH_CHOICE" ]; then
            print_error "Input cannot be empty. Please select 1 or 2."
            continue
        fi
        if [[ ! "$AUTH_CHOICE" =~ ^[0-9]+$ ]]; then
            print_error "Invalid input: '$AUTH_CHOICE'. Please enter only numbers (1 or 2)."
            continue
        fi
        if [ "$AUTH_CHOICE" -lt 1 ] || [ "$AUTH_CHOICE" -gt 2 ]; then
            print_error "Invalid option: '$AUTH_CHOICE'. Please select 1 or 2."
            continue
        fi
        break
    done
    # Adjust choice: if they select 2, it means manual (which would be 3 in full menu)
    if [ "$AUTH_CHOICE" == "2" ]; then
        AUTH_CHOICE="3"
    fi
elif [ "$HAS_AWS_VAULT" == "false" ] && [ "$HAS_PROFILES" == "true" ]; then
    MAX_OPTION=2
    while true; do
        read_input "Select option (1 or 2): " AUTH_CHOICE
        # Validate AUTH_CHOICE - must be numeric only
        if [ -z "$AUTH_CHOICE" ]; then
            print_error "Input cannot be empty. Please select 1 or 2."
            continue
        fi
        if [[ ! "$AUTH_CHOICE" =~ ^[0-9]+$ ]]; then
            print_error "Invalid input: '$AUTH_CHOICE'. Please enter only numbers (1 or 2)."
            continue
        fi
        if [ "$AUTH_CHOICE" -lt 1 ] || [ "$AUTH_CHOICE" -gt 2 ]; then
            print_error "Invalid option: '$AUTH_CHOICE'. Please select 1 or 2."
            continue
        fi
        break
    done
    # Adjust choice number: AWS Profile is option 2 when aws-vault is available
    AUTH_CHOICE=$((AUTH_CHOICE + 1))
else
    print_info "No AWS profiles found. Please enter credentials manually."
    AUTH_CHOICE="3"
fi

# Handle authentication choice (same as EC2 script)
if [ "$AUTH_CHOICE" == "1" ]; then
    # Use aws-vault
    USE_AWS_VAULT=true
    AWS_VAULT_ENABLED=true
    print_info "Using aws-vault for secure credential management"
    echo ""
    
    # List aws-vault profiles
    VAULT_PROFILES=$(aws-vault list 2>/dev/null | grep -v "Profile" | grep -v "===" | awk '{print $1}' | grep -v "^$" || echo "")
    
    if [ ! -z "$VAULT_PROFILES" ]; then
        echo "Available aws-vault profiles:"
        echo "$VAULT_PROFILES" | nl -w2 -s'. '
        echo ""
        read_input "Select profile number (or enter profile name): " VAULT_PROFILE_INPUT
        
        # Validate input is not empty
        if [ -z "$VAULT_PROFILE_INPUT" ]; then
            print_error "Profile selection cannot be empty!"
            exit 1
        fi
        
        # Check if input is a number
        if [[ "$VAULT_PROFILE_INPUT" =~ ^[0-9]+$ ]]; then
            # Validate number is within range
            PROFILE_COUNT=$(echo "$VAULT_PROFILES" | wc -l | tr -d ' ')
            if [ "$VAULT_PROFILE_INPUT" -lt 1 ] || [ "$VAULT_PROFILE_INPUT" -gt "$PROFILE_COUNT" ]; then
                print_error "Invalid profile number: $VAULT_PROFILE_INPUT. Please select a number between 1 and $PROFILE_COUNT."
                exit 1
            fi
            AWS_VAULT_PROFILE=$(echo "$VAULT_PROFILES" | sed -n "${VAULT_PROFILE_INPUT}p")
        else
            AWS_VAULT_PROFILE="$VAULT_PROFILE_INPUT"
        fi
        
        if [ -z "$AWS_VAULT_PROFILE" ]; then
            print_error "Invalid profile selection!"
            exit 1
        fi
        
        # Test aws-vault access
        print_info "Testing aws-vault access..."
        if aws-vault exec "$AWS_VAULT_PROFILE" -- aws sts get-caller-identity > /dev/null 2>&1; then
            ACCOUNT_INFO=$(aws-vault exec "$AWS_VAULT_PROFILE" -- aws sts get-caller-identity 2>/dev/null)
            ACCOUNT_ID=$(echo "$ACCOUNT_INFO" | jq -r '.Account' 2>/dev/null || echo "unknown")
            print_success "aws-vault profile '$AWS_VAULT_PROFILE' is working"
            echo "  Account: $ACCOUNT_ID"
            
            # Get region from aws-vault config or default
            AWS_REGION=$(aws-vault exec "$AWS_VAULT_PROFILE" -- aws configure get region 2>/dev/null || echo "us-east-1")
            export AWS_REGION
            export AWS_DEFAULT_REGION=$AWS_REGION
            
            if [ "$AWS_REGION" != "us-east-1" ]; then
                print_info "Using region from aws-vault config: $AWS_REGION"
            fi
        else
            print_error "Failed to access AWS with aws-vault profile: $AWS_VAULT_PROFILE"
            print_info "Make sure the profile exists and credentials are valid"
            exit 1
        fi
    else
        print_warning "No aws-vault profiles found."
        print_info "You can add a profile with: aws-vault add <profile-name>"
        echo ""
        read_input "Enter aws-vault profile name to use: " AWS_VAULT_PROFILE
        if [ -z "$AWS_VAULT_PROFILE" ]; then
            print_error "Profile name is required!"
            exit 1
        fi
    fi
    
    # Skip to permission checks
    SKIP_TO_PERMISSIONS=true
elif [ "$AUTH_CHOICE" == "2" ] && [ "$HAS_PROFILES" == "true" ]; then
    # Use AWS Profile
    USE_AWS_VAULT=false
    AWS_VAULT_ENABLED=false
    
    echo ""
    echo "Available AWS Profiles:"
    echo "$PROFILES" | nl -w2 -s'. '
    echo ""
    read_input "Select profile number (or enter profile name): " PROFILE_INPUT
    
    # Validate input is not empty
    if [ -z "$PROFILE_INPUT" ]; then
        print_error "Profile selection cannot be empty!"
        exit 1
    fi
    
    # Check if input is a number
    if [[ "$PROFILE_INPUT" =~ ^[0-9]+$ ]]; then
        # Validate number is within range
        PROFILE_COUNT=$(echo "$PROFILES" | wc -l | tr -d ' ')
        if [ "$PROFILE_INPUT" -lt 1 ] || [ "$PROFILE_INPUT" -gt "$PROFILE_COUNT" ]; then
            print_error "Invalid profile number: $PROFILE_INPUT. Please select a number between 1 and $PROFILE_COUNT."
            exit 1
        fi
        SELECTED_PROFILE=$(echo "$PROFILES" | sed -n "${PROFILE_INPUT}p")
    else
        SELECTED_PROFILE="$PROFILE_INPUT"
    fi
    
    if [ -z "$SELECTED_PROFILE" ]; then
        print_error "Invalid profile selection!"
        exit 1
    fi
    
    export AWS_PROFILE="$SELECTED_PROFILE"
    print_success "Using AWS Profile: $SELECTED_PROFILE"
    
    # Note: aws-vault can also be used with profiles
    if command_exists aws-vault; then
        echo ""
        print_info "💡 Tip: You can use aws-vault for more secure credential storage"
        print_info "   Run: aws-vault add $SELECTED_PROFILE"
    fi
    
    # Get region from ~/.aws/config file
    PROFILE_REGION=""
    if [ -f "$AWS_CONFIG_FILE" ]; then
        # Check for [profile profile-name] format (standard AWS config format)
        if grep -q "^\[profile $SELECTED_PROFILE\]" "$AWS_CONFIG_FILE"; then
            REGION_LINE=$(sed -n "/^\[profile $SELECTED_PROFILE\]/,/^\[/p" "$AWS_CONFIG_FILE" | grep -i "^region" | head -1)
            if [ ! -z "$REGION_LINE" ]; then
                PROFILE_REGION=$(echo "$REGION_LINE" | cut -d'=' -f2 | xargs)
            fi
        elif grep -q "^\[$SELECTED_PROFILE\]" "$AWS_CONFIG_FILE"; then
            REGION_LINE=$(sed -n "/^\[$SELECTED_PROFILE\]/,/^\[/p" "$AWS_CONFIG_FILE" | grep -i "^region" | head -1)
            if [ ! -z "$REGION_LINE" ]; then
                PROFILE_REGION=$(echo "$REGION_LINE" | cut -d'=' -f2 | xargs)
            fi
        fi
        
        # Clean up any remaining whitespace
        if [ ! -z "$PROFILE_REGION" ]; then
            PROFILE_REGION=$(echo "$PROFILE_REGION" | xargs)
        fi
        
        if [ ! -z "$PROFILE_REGION" ] && [ "$PROFILE_REGION" != "None" ] && [ "$PROFILE_REGION" != "" ]; then
            AWS_REGION="$PROFILE_REGION"
            REGION_FROM_PROFILE=true
        fi
    fi
    
    # Unset credential environment variables to use profile
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    
    REGION_FROM_PROFILE=true
else
    # Manual credentials entry
    USE_MANUAL_CREDS=true
    REGION_FROM_PROFILE=false
fi

# Manual credentials entry
if [ "$USE_MANUAL_CREDS" == "true" ]; then
    echo ""
    print_info "Note: If you're using AWS IAM Identity Center, you'll need Access Key, Secret Key, and Session Token"
    echo ""
    
    read_input "Enter AWS Access Key ID: " AWS_ACCESS_KEY_ID
    read -sp "Enter AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
    echo ""
    read -sp "Enter AWS Session Token (optional, press Enter to skip if not using IAM Identity Center): " AWS_SESSION_TOKEN
    AWS_SESSION_TOKEN=$(echo "$AWS_SESSION_TOKEN" | tr -d '\r\n')
    echo ""
    
    # Validate inputs
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        print_error "Access Key ID and Secret Access Key are required!"
        exit 1
    fi
    
    # Export AWS credentials
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_DEFAULT_REGION=$AWS_REGION
    export AWS_REGION
    
    # Export session token if provided (for IAM Identity Center)
    if [ ! -z "$AWS_SESSION_TOKEN" ]; then
        export AWS_SESSION_TOKEN
        print_info "Session token provided (IAM Identity Center credentials detected)"
    else
        # Unset session token if not provided (in case it was set before)
        unset AWS_SESSION_TOKEN
        export AWS_SESSION_TOKEN=""
    fi
fi

# Handle region configuration
if [ "$REGION_FROM_PROFILE" == "true" ]; then
    # Region is already set from profile, don't ask
    export AWS_DEFAULT_REGION=$AWS_REGION
    export AWS_REGION
    echo ""
else
    # No region in profile, ask user
    echo ""
    print_info "Default region: $AWS_REGION"
    read_input "Enter AWS Region (press Enter to use $AWS_REGION): " INPUT_REGION
    
    if [ ! -z "$INPUT_REGION" ]; then
        AWS_REGION="$INPUT_REGION"
    fi
    
    export AWS_DEFAULT_REGION=$AWS_REGION
    export AWS_REGION
    echo ""
fi

# Test AWS credentials and permissions
if [ "$SKIP_TO_PERMISSIONS" != "true" ]; then
    print_info "Testing AWS credentials..."
    if ! aws_cmd sts get-caller-identity > /dev/null 2>&1; then
        print_error "Failed to authenticate with AWS"
        print_error "Please check your credentials and try again"
        exit 1
    fi
    
    ACCOUNT_INFO=$(aws_cmd sts get-caller-identity 2>/dev/null)
    ACCOUNT_ID=$(echo "$ACCOUNT_INFO" | jq -r '.Account' 2>/dev/null || echo "unknown")
    USER_ARN=$(echo "$ACCOUNT_INFO" | jq -r '.Arn' 2>/dev/null || echo "unknown")
    print_success "AWS credentials are valid"
    echo "  Account: $ACCOUNT_ID"
    echo "  User: $USER_ARN"
    echo ""
fi

# Check for required permissions
print_info "Checking required permissions..."
MISSING_PERMS=()

# Check ECS permissions
if ! aws_cmd ecs list-clusters --max-items 1 > /dev/null 2>&1; then
    MISSING_PERMS+=("ecs:ListClusters")
fi

if [ ${#MISSING_PERMS[@]} -gt 0 ]; then
    print_warning "Some permissions may be missing:"
    for perm in "${MISSING_PERMS[@]}"; do
        echo "  - $perm"
    done
    echo ""
    print_info "The script will attempt to proceed, but some features may not work."
    echo ""
fi

# Step 2: List and select ECS cluster
print_info "Step 2: Select ECS Cluster"
echo ""

print_info "Fetching ECS clusters..."
ECS_CLUSTERS=$(aws_cmd ecs list-clusters \
    --query 'clusterArns[*]' \
    --output text 2>/dev/null || echo "")

if [ -z "$ECS_CLUSTERS" ]; then
    print_error "No ECS clusters found or unable to list clusters."
    print_error "Please check your permissions: ecs:ListClusters"
    exit 1
fi

# Parse cluster ARNs to get cluster names
declare -a CLUSTER_ARRAY
COUNT=0

for CLUSTER_ARN in $ECS_CLUSTERS; do
    CLUSTER_NAME=$(echo "$CLUSTER_ARN" | awk -F'/' '{print $NF}')
    CLUSTER_ARRAY[$COUNT]="$CLUSTER_NAME|$CLUSTER_ARN"
    ((COUNT++))
done

if [ $COUNT -eq 0 ]; then
    print_error "No ECS clusters found in region: $AWS_REGION"
    exit 1
fi

echo "Available ECS Clusters:"
echo "======================="
echo ""
for i in $(seq 0 $((COUNT-1))); do
    IFS='|' read -r CLUSTER_NAME CLUSTER_ARN <<< "${CLUSTER_ARRAY[$i]}"
    echo "$((i+1)). $CLUSTER_NAME"
done

echo ""
read_input "Select cluster number (or enter cluster name): " CLUSTER_SELECTION

# Validate and parse selection
if [ -z "$CLUSTER_SELECTION" ]; then
    print_error "Cluster selection cannot be empty!"
    exit 1
fi

# Check if input is a number
if [[ "$CLUSTER_SELECTION" =~ ^[0-9]+$ ]]; then
    # Validate number is within range
    if [ "$CLUSTER_SELECTION" -lt 1 ] || [ "$CLUSTER_SELECTION" -gt "$COUNT" ]; then
        print_error "Invalid cluster number: $CLUSTER_SELECTION. Please select a number between 1 and $COUNT."
        exit 1
    fi
    SELECTED_CLUSTER="${CLUSTER_ARRAY[$((CLUSTER_SELECTION-1))]}"
    SELECTED_CLUSTER_NAME=$(echo "$SELECTED_CLUSTER" | cut -d'|' -f1)
    SELECTED_CLUSTER_ARN=$(echo "$SELECTED_CLUSTER" | cut -d'|' -f2)
else
    # Assume it's a cluster name
    SELECTED_CLUSTER_NAME="$CLUSTER_SELECTION"
    # Try to find the cluster ARN
    SELECTED_CLUSTER_ARN=$(aws_cmd ecs describe-clusters \
        --clusters "$SELECTED_CLUSTER_NAME" \
        --query 'clusters[0].clusterArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$SELECTED_CLUSTER_ARN" ] || [ "$SELECTED_CLUSTER_ARN" == "None" ]; then
        print_error "Cluster '$SELECTED_CLUSTER_NAME' not found in region: $AWS_REGION"
        exit 1
    fi
fi

print_success "Selected cluster: $SELECTED_CLUSTER_NAME"
echo ""

# Step 3: List and select service or task
print_info "Step 3: Select Service or Task"
echo ""

echo "How would you like to connect?"
echo "1) Select from running tasks"
echo "2) Select from services (then pick a task)"
echo "3) Enter task ARN manually"
echo ""
while true; do
    read_input "Select option (1, 2, or 3): " CONNECTION_TYPE
    # Validate CONNECTION_TYPE - must be numeric only
    if [ -z "$CONNECTION_TYPE" ]; then
        print_error "Input cannot be empty. Please select 1, 2, or 3."
        continue
    fi
    if [[ ! "$CONNECTION_TYPE" =~ ^[0-9]+$ ]]; then
        print_error "Invalid input: '$CONNECTION_TYPE'. Please enter only numbers (1, 2, or 3)."
        continue
    fi
    if [ "$CONNECTION_TYPE" -lt 1 ] || [ "$CONNECTION_TYPE" -gt 3 ]; then
        print_error "Invalid option: '$CONNECTION_TYPE'. Please select 1, 2, or 3."
        continue
    fi
    break
done

TASK_ARN=""
TASK_ID=""
CONTAINER_NAME=""

case $CONNECTION_TYPE in
    1)
        # List running tasks
        print_info "Fetching running tasks..."
        RUNNING_TASKS=$(aws_cmd ecs list-tasks \
            --cluster "$SELECTED_CLUSTER_NAME" \
            --desired-status RUNNING \
            --query 'taskArns[*]' \
            --output text 2>/dev/null || echo "")
        
        if [ -z "$RUNNING_TASKS" ]; then
            print_error "No running tasks found in cluster: $SELECTED_CLUSTER_NAME"
            exit 1
        fi
        
        # Get task details
        declare -a TASK_ARRAY
        TASK_COUNT=0
        
        for TASK_ARN_ITEM in $RUNNING_TASKS; do
            TASK_DETAILS=$(aws_cmd ecs describe-tasks \
                --cluster "$SELECTED_CLUSTER_NAME" \
                --tasks "$TASK_ARN_ITEM" \
                --query 'tasks[0].[taskArn,lastStatus,containers[0].name]' \
                --output text 2>/dev/null || echo "")
            
            if [ ! -z "$TASK_DETAILS" ] && [ "$TASK_DETAILS" != "None" ]; then
                IFS=$'\t' read -r TASK_ARN_FULL TASK_STATUS CONTAINER_NAME_FULL <<< "$TASK_DETAILS"
                TASK_ID_SHORT=$(echo "$TASK_ARN_FULL" | awk -F'/' '{print $NF}')
                TASK_ARRAY[$TASK_COUNT]="$TASK_ARN_FULL|$TASK_ID_SHORT|$TASK_STATUS|$CONTAINER_NAME_FULL"
                ((TASK_COUNT++))
            fi
        done
        
        if [ $TASK_COUNT -eq 0 ]; then
            print_error "No valid running tasks found"
            exit 1
        fi
        
        echo ""
        echo "Available Tasks:"
        echo "================"
        printf "%-3s %-50s %-15s %-30s\n" "#" "Task ID" "Status" "Container"
        echo "--------------------------------------------------------------------------------"
        for i in $(seq 0 $((TASK_COUNT-1))); do
            IFS='|' read -r TASK_ARN_FULL TASK_ID_SHORT TASK_STATUS CONTAINER_NAME_FULL <<< "${TASK_ARRAY[$i]}"
            printf "%-3s %-50s %-15s %-30s\n" \
                "$((i+1))" \
                "$TASK_ID_SHORT" \
                "$TASK_STATUS" \
                "${CONTAINER_NAME_FULL:-N/A}"
        done
        
        echo ""
        while true; do
            read_input "Select task number: " TASK_SELECTION
            # Validate TASK_SELECTION - must be numeric only
            if [ -z "$TASK_SELECTION" ]; then
                print_error "Input cannot be empty. Please enter a number."
                continue
            fi
            if [[ ! "$TASK_SELECTION" =~ ^[0-9]+$ ]]; then
                print_error "Invalid input: '$TASK_SELECTION'. Please enter only numbers."
                continue
            fi
            if [ "$TASK_SELECTION" -lt 1 ] || [ "$TASK_SELECTION" -gt "$TASK_COUNT" ]; then
                print_error "Invalid task number: $TASK_SELECTION. Please select a number between 1 and $TASK_COUNT."
                continue
            fi
            break
        done
        
        SELECTED_TASK="${TASK_ARRAY[$((TASK_SELECTION-1))]}"
        TASK_ARN=$(echo "$SELECTED_TASK" | cut -d'|' -f1)
        TASK_ID=$(echo "$SELECTED_TASK" | cut -d'|' -f2)
        CONTAINER_NAME=$(echo "$SELECTED_TASK" | cut -d'|' -f4)
        ;;
    2)
        # List services
        print_info "Fetching services..."
        SERVICES=$(aws_cmd ecs list-services \
            --cluster "$SELECTED_CLUSTER_NAME" \
            --query 'serviceArns[*]' \
            --output text 2>/dev/null || echo "")
        
        if [ -z "$SERVICES" ]; then
            print_error "No services found in cluster: $SELECTED_CLUSTER_NAME"
            exit 1
        fi
        
        # Parse service ARNs to get service names
        declare -a SERVICE_ARRAY
        SERVICE_COUNT=0
        
        for SERVICE_ARN in $SERVICES; do
            SERVICE_NAME=$(echo "$SERVICE_ARN" | awk -F'/' '{print $NF}')
            SERVICE_ARRAY[$SERVICE_COUNT]="$SERVICE_NAME|$SERVICE_ARN"
            ((SERVICE_COUNT++))
        done
        
        echo ""
        echo "Available Services:"
        echo "==================="
        for i in $(seq 0 $((SERVICE_COUNT-1))); do
            IFS='|' read -r SERVICE_NAME SERVICE_ARN <<< "${SERVICE_ARRAY[$i]}"
            echo "$((i+1)). $SERVICE_NAME"
        done
        
        echo ""
        while true; do
            read_input "Select service number: " SERVICE_SELECTION
            # Validate SERVICE_SELECTION - must be numeric only
            if [ -z "$SERVICE_SELECTION" ]; then
                print_error "Input cannot be empty. Please enter a number."
                continue
            fi
            if [[ ! "$SERVICE_SELECTION" =~ ^[0-9]+$ ]]; then
                print_error "Invalid input: '$SERVICE_SELECTION'. Please enter only numbers."
                continue
            fi
            if [ "$SERVICE_SELECTION" -lt 1 ] || [ "$SERVICE_SELECTION" -gt "$SERVICE_COUNT" ]; then
                print_error "Invalid service number: $SERVICE_SELECTION. Please select a number between 1 and $SERVICE_COUNT."
                continue
            fi
            break
        done
        
        SELECTED_SERVICE="${SERVICE_ARRAY[$((SERVICE_SELECTION-1))]}"
        SELECTED_SERVICE_NAME=$(echo "$SELECTED_SERVICE" | cut -d'|' -f1)
        
        # Get tasks for the service
        print_info "Fetching tasks for service: $SELECTED_SERVICE_NAME"
        SERVICE_TASKS=$(aws_cmd ecs list-tasks \
            --cluster "$SELECTED_CLUSTER_NAME" \
            --service-name "$SELECTED_SERVICE_NAME" \
            --desired-status RUNNING \
            --query 'taskArns[*]' \
            --output text 2>/dev/null || echo "")
        
        if [ -z "$SERVICE_TASKS" ]; then
            print_error "No running tasks found for service: $SELECTED_SERVICE_NAME"
            exit 1
        fi
        
        # Get task details (same as option 1)
        declare -a TASK_ARRAY
        TASK_COUNT=0
        
        for TASK_ARN_ITEM in $SERVICE_TASKS; do
            TASK_DETAILS=$(aws_cmd ecs describe-tasks \
                --cluster "$SELECTED_CLUSTER_NAME" \
                --tasks "$TASK_ARN_ITEM" \
                --query 'tasks[0].[taskArn,lastStatus,containers[0].name]' \
                --output text 2>/dev/null || echo "")
            
            if [ ! -z "$TASK_DETAILS" ] && [ "$TASK_DETAILS" != "None" ]; then
                IFS=$'\t' read -r TASK_ARN_FULL TASK_STATUS CONTAINER_NAME_FULL <<< "$TASK_DETAILS"
                TASK_ID_SHORT=$(echo "$TASK_ARN_FULL" | awk -F'/' '{print $NF}')
                TASK_ARRAY[$TASK_COUNT]="$TASK_ARN_FULL|$TASK_ID_SHORT|$TASK_STATUS|$CONTAINER_NAME_FULL"
                ((TASK_COUNT++))
            fi
        done
        
        if [ $TASK_COUNT -eq 0 ]; then
            print_error "No valid running tasks found for service"
            exit 1
        fi
        
        echo ""
        echo "Available Tasks for Service '$SELECTED_SERVICE_NAME':"
        echo "====================================================="
        printf "%-3s %-50s %-15s %-30s\n" "#" "Task ID" "Status" "Container"
        echo "--------------------------------------------------------------------------------"
        for i in $(seq 0 $((TASK_COUNT-1))); do
            IFS='|' read -r TASK_ARN_FULL TASK_ID_SHORT TASK_STATUS CONTAINER_NAME_FULL <<< "${TASK_ARRAY[$i]}"
            printf "%-3s %-50s %-15s %-30s\n" \
                "$((i+1))" \
                "$TASK_ID_SHORT" \
                "$TASK_STATUS" \
                "${CONTAINER_NAME_FULL:-N/A}"
        done
        
        echo ""
        while true; do
            read_input "Select task number: " TASK_SELECTION
            # Validate TASK_SELECTION - must be numeric only
            if [ -z "$TASK_SELECTION" ]; then
                print_error "Input cannot be empty. Please enter a number."
                continue
            fi
            if [[ ! "$TASK_SELECTION" =~ ^[0-9]+$ ]]; then
                print_error "Invalid input: '$TASK_SELECTION'. Please enter only numbers."
                continue
            fi
            if [ "$TASK_SELECTION" -lt 1 ] || [ "$TASK_SELECTION" -gt "$TASK_COUNT" ]; then
                print_error "Invalid task number: $TASK_SELECTION. Please select a number between 1 and $TASK_COUNT."
                continue
            fi
            break
        done
        
        SELECTED_TASK="${TASK_ARRAY[$((TASK_SELECTION-1))]}"
        TASK_ARN=$(echo "$SELECTED_TASK" | cut -d'|' -f1)
        TASK_ID=$(echo "$SELECTED_TASK" | cut -d'|' -f2)
        CONTAINER_NAME=$(echo "$SELECTED_TASK" | cut -d'|' -f4)
        ;;
    3)
        # Manual task ARN entry
        read_input "Enter task ARN: " TASK_ARN
        
        if [ -z "$TASK_ARN" ]; then
            print_error "Task ARN cannot be empty!"
            exit 1
        fi
        
        TASK_ID=$(echo "$TASK_ARN" | awk -F'/' '{print $NF}')
        
        # Verify task exists
        TASK_DETAILS=$(aws_cmd ecs describe-tasks \
            --cluster "$SELECTED_CLUSTER_NAME" \
            --tasks "$TASK_ARN" \
            --query 'tasks[0].[taskArn,lastStatus,containers[0].name]' \
            --output text 2>/dev/null || echo "")
        
        if [ -z "$TASK_DETAILS" ] || [ "$TASK_DETAILS" == "None" ]; then
            print_warning "Could not verify task. Attempting to connect anyway..."
        else
            IFS=$'\t' read -r TASK_ARN_VERIFIED TASK_STATUS CONTAINER_NAME_VERIFIED <<< "$TASK_DETAILS"
            CONTAINER_NAME="$CONTAINER_NAME_VERIFIED"
            print_success "Task verified: $TASK_ID (Status: $TASK_STATUS)"
        fi
        ;;
esac

if [ -z "$TASK_ARN" ]; then
    print_error "Task ARN is required!"
    exit 1
fi

print_success "Selected task: $TASK_ID"
if [ ! -z "$CONTAINER_NAME" ]; then
    echo "  Container: $CONTAINER_NAME"
fi
echo ""

# Step 4: Check ECS Exec capability and connect
print_info "Step 4: Connect to Task"
echo ""

# Check if Session Manager plugin is installed
if ! check_and_install_session_manager_plugin; then
    print_error "Cannot proceed without Session Manager plugin."
    print_info "Please install it and run the script again."
    exit 1
fi

# Check if ECS Exec is enabled for the task
print_info "Checking ECS Exec capability..."
TASK_DEFINITION_ARN=$(aws_cmd ecs describe-tasks \
    --cluster "$SELECTED_CLUSTER_NAME" \
    --tasks "$TASK_ARN" \
    --query 'tasks[0].taskDefinitionArn' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$TASK_DEFINITION_ARN" ] && [ "$TASK_DEFINITION_ARN" != "None" ]; then
    ENABLE_EXECUTE_COMMAND=$(aws_cmd ecs describe-task-definition \
        --task-definition "$TASK_DEFINITION_ARN" \
        --query 'taskDefinition.enableExecuteCommand' \
        --output text 2>/dev/null || echo "false")
    
    if [ "$ENABLE_EXECUTE_COMMAND" == "true" ]; then
        print_success "ECS Exec is enabled for this task"
    else
        print_warning "ECS Exec may not be enabled for this task definition."
        echo ""
        print_info "To enable ECS Exec, update your task definition with:"
        echo "  enableExecuteCommand: true"
        echo ""
        print_info "Or start new tasks with:"
        echo "  aws ecs update-service --cluster $SELECTED_CLUSTER_NAME --service <service-name> --enable-execute-command"
        echo ""
        read_input "Continue anyway? (y/n, default: y): " CONTINUE_ANYWAY
        if [ "$CONTINUE_ANYWAY" == "n" ] || [ "$CONTINUE_ANYWAY" == "N" ]; then
            print_info "Exiting. Please enable ECS Exec and try again."
            exit 0
        fi
    fi
else
    print_warning "Could not verify ECS Exec capability. Attempting to connect anyway..."
fi

# Determine container name if not set
if [ -z "$CONTAINER_NAME" ]; then
    CONTAINERS=$(aws_cmd ecs describe-tasks \
        --cluster "$SELECTED_CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --query 'tasks[0].containers[*].name' \
        --output text 2>/dev/null || echo "")
    
    CONTAINER_COUNT=$(echo "$CONTAINERS" | wc -w)
    
    if [ $CONTAINER_COUNT -eq 1 ]; then
        CONTAINER_NAME="$CONTAINERS"
        print_info "Using container: $CONTAINER_NAME"
    elif [ $CONTAINER_COUNT -gt 1 ]; then
        echo ""
        echo "Multiple containers found in task:"
        CONTAINER_ARRAY=($CONTAINERS)
        for i in $(seq 0 $((CONTAINER_COUNT-1))); do
            echo "$((i+1)). ${CONTAINER_ARRAY[$i]}"
        done
        echo ""
        while true; do
            read_input "Select container number: " CONTAINER_SELECTION
            # Validate CONTAINER_SELECTION - must be numeric only
            if [ -z "$CONTAINER_SELECTION" ]; then
                print_error "Input cannot be empty. Please enter a number."
                continue
            fi
            if [[ ! "$CONTAINER_SELECTION" =~ ^[0-9]+$ ]]; then
                print_error "Invalid input: '$CONTAINER_SELECTION'. Please enter only numbers."
                continue
            fi
            if [ "$CONTAINER_SELECTION" -lt 1 ] || [ "$CONTAINER_SELECTION" -gt "$CONTAINER_COUNT" ]; then
                print_error "Invalid container number: $CONTAINER_SELECTION. Please select a number between 1 and $CONTAINER_COUNT."
                continue
            fi
            break
        done
        
        CONTAINER_NAME="${CONTAINER_ARRAY[$((CONTAINER_SELECTION-1))]}"
    else
        print_warning "Could not determine container name. Attempting to connect without specifying container..."
    fi
fi

echo ""
print_info "Connecting to task: $TASK_ID"
if [ ! -z "$CONTAINER_NAME" ]; then
    print_info "Container: $CONTAINER_NAME"
fi
print_info "Press Ctrl+D or type 'exit' to disconnect"
echo ""

# Connect via ECS Exec
if [ "$AWS_VAULT_ENABLED" == "true" ] && [ ! -z "$AWS_VAULT_PROFILE" ]; then
    if [ ! -z "$CONTAINER_NAME" ]; then
        aws-vault exec "$AWS_VAULT_PROFILE" -- aws ecs execute-command \
            --cluster "$SELECTED_CLUSTER_NAME" \
            --task "$TASK_ARN" \
            --container "$CONTAINER_NAME" \
            --interactive \
            --command "/bin/sh"
    else
        aws-vault exec "$AWS_VAULT_PROFILE" -- aws ecs execute-command \
            --cluster "$SELECTED_CLUSTER_NAME" \
            --task "$TASK_ARN" \
            --interactive \
            --command "/bin/sh"
    fi
else
    if [ ! -z "$CONTAINER_NAME" ]; then
        aws_cmd ecs execute-command \
            --cluster "$SELECTED_CLUSTER_NAME" \
            --task "$TASK_ARN" \
            --container "$CONTAINER_NAME" \
            --interactive \
            --command "/bin/sh"
    else
        aws_cmd ecs execute-command \
            --cluster "$SELECTED_CLUSTER_NAME" \
            --task "$TASK_ARN" \
            --interactive \
            --command "/bin/sh"
    fi
fi

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    print_success "Session ended successfully"
else
    print_error "Session ended with error code: $EXIT_CODE"
    print_info "Common issues:"
    echo "  - ECS Exec not enabled for the task/service"
    echo "  - Task is not in RUNNING state"
    echo "  - Missing IAM permissions: ecs:ExecuteCommand"
    echo "  - Container does not have a shell available"
    exit $EXIT_CODE
fi

