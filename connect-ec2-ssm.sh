#!/bin/bash
# EC2 Instance SSM Connection Script
# Handles AWS authentication and connects to EC2 instances via AWS Systems Manager Session Manager

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

# Helper function to read file path with tab completion support
read_file_path() {
    local prompt="$1"
    local var_name="$2"
    # Use read -e to enable readline (tab completion)
    IFS= read -e -p "$prompt" "$var_name"
    # Remove carriage returns and newlines
    eval "$var_name=\$(echo \"\$$var_name\" | tr -d '\r\n')"
}

# Helper function to validate numeric input from a list
validate_numeric_selection() {
    local input="$1"
    local min="$2"
    local max="$3"
    local error_msg="$4"
    
    # Check if input is empty
    if [ -z "$input" ]; then
        print_error "Input cannot be empty!"
        return 1
    fi
    
    # Check if input is numeric
    if [[ ! "$input" =~ ^[0-9]+$ ]]; then
        print_error "$error_msg"
        return 1
    fi
    
    # Check if input is within range
    if [ "$input" -lt "$min" ] || [ "$input" -gt "$max" ]; then
        print_error "Invalid selection: $input. Please select a number between $min and $max."
        return 1
    fi
    
    return 0
}

# Function to check and install Session Manager plugin
check_and_install_session_manager_plugin() {
    if command_exists session-manager-plugin; then
        return 0
    fi
    
    print_warning "Session Manager plugin not found."
    echo ""
    print_info "The Session Manager plugin is required to connect to EC2 instances via SSM."
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
echo "  AWS EC2 SSM Connection Tool"
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

# Handle authentication choice
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
            # Extract region line from the profile section (stop at next [ or end of file)
            REGION_LINE=$(sed -n "/^\[profile $SELECTED_PROFILE\]/,/^\[/p" "$AWS_CONFIG_FILE" | grep -i "^region" | head -1)
            if [ ! -z "$REGION_LINE" ]; then
                PROFILE_REGION=$(echo "$REGION_LINE" | cut -d'=' -f2 | xargs)
            fi
        elif grep -q "^\[$SELECTED_PROFILE\]" "$AWS_CONFIG_FILE"; then
            # Check for [profile-name] format (alternative format)
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
    # Manual credentials entry (option 3 if aws-vault available, option 2 if not)
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

# Check EC2 permissions
if ! aws_cmd ec2 describe-instances --max-items 1 > /dev/null 2>&1; then
    MISSING_PERMS+=("ec2:DescribeInstances")
fi

# Check SSM permissions
if ! aws_cmd ssm describe-instance-information --max-items 1 > /dev/null 2>&1; then
    # Only report if it's an explicit access denied, not if there are no instances
    SSM_CHECK=$(aws_cmd ssm describe-instance-information --max-items 1 2>&1)
    if echo "$SSM_CHECK" | grep -qi "AccessDenied\|UnauthorizedOperation"; then
        MISSING_PERMS+=("ssm:DescribeInstanceInformation")
    fi
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

# Step 2: List and select EC2 instance
print_info "Step 2: Select EC2 Instance"
echo ""

print_info "Fetching EC2 instances..."
EC2_INSTANCES=$(aws_cmd ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,PrivateIpAddress,PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' \
    --output text 2>/dev/null || echo "")

if [ -z "$EC2_INSTANCES" ]; then
    print_error "No EC2 instances found or unable to list instances."
    print_error "Please check your permissions: ec2:DescribeInstances"
    exit 1
fi

# Parse instances into array
declare -a INSTANCE_ARRAY
COUNT=0

while IFS=$'\t' read -r INSTANCE_ID STATE INSTANCE_TYPE PRIVATE_IP PUBLIC_IP INSTANCE_NAME; do
    if [ -z "$INSTANCE_NAME" ] || [ "$INSTANCE_NAME" == "None" ]; then
        INSTANCE_NAME="(no name)"
    fi
    INSTANCE_ARRAY[$COUNT]="$INSTANCE_ID|$INSTANCE_NAME|$STATE|$INSTANCE_TYPE|$PRIVATE_IP|$PUBLIC_IP"
    ((COUNT++))
done <<< "$EC2_INSTANCES"

if [ $COUNT -eq 0 ]; then
    print_error "No EC2 instances found in region: $AWS_REGION"
    exit 1
fi

echo "Available EC2 Instances:"
echo "======================="
echo ""
printf "%-3s %-20s %-30s %-10s %-15s %-15s %-15s\n" "#" "Instance ID" "Name" "State" "Type" "Private IP" "Public IP"
echo "------------------------------------------------------------------------------------------------------------------------"

for i in $(seq 0 $((COUNT-1))); do
    IFS='|' read -r INSTANCE_ID INSTANCE_NAME STATE INSTANCE_TYPE PRIVATE_IP PUBLIC_IP <<< "${INSTANCE_ARRAY[$i]}"
    printf "%-3s %-20s %-30s %-10s %-15s %-15s %-15s\n" \
        "$((i+1))" \
        "$INSTANCE_ID" \
        "$INSTANCE_NAME" \
        "$STATE" \
        "$INSTANCE_TYPE" \
        "${PRIVATE_IP:-N/A}" \
        "${PUBLIC_IP:-N/A}"
done

echo ""
read_input "Select instance number (or enter instance ID): " INSTANCE_SELECTION

# Validate and parse selection
if [ -z "$INSTANCE_SELECTION" ]; then
    print_error "Instance selection cannot be empty!"
    exit 1
fi

# Check if input is a number
if [[ "$INSTANCE_SELECTION" =~ ^[0-9]+$ ]]; then
    # Validate number is within range
    if [ "$INSTANCE_SELECTION" -lt 1 ] || [ "$INSTANCE_SELECTION" -gt "$COUNT" ]; then
        print_error "Invalid instance number: $INSTANCE_SELECTION. Please select a number between 1 and $COUNT."
        exit 1
    fi
    SELECTED_INSTANCE="${INSTANCE_ARRAY[$((INSTANCE_SELECTION-1))]}"
    SELECTED_INSTANCE_ID=$(echo "$SELECTED_INSTANCE" | cut -d'|' -f1)
else
    # Assume it's an instance ID
    SELECTED_INSTANCE_ID="$INSTANCE_SELECTION"
    # Verify the instance exists
    if ! echo "$EC2_INSTANCES" | grep -q "$SELECTED_INSTANCE_ID"; then
        print_warning "Instance ID '$SELECTED_INSTANCE_ID' not found in the list above."
        print_info "Attempting to connect anyway..."
    fi
fi

print_success "Selected instance: $SELECTED_INSTANCE_ID"
echo ""

# Function to check user permissions for SSM configuration
check_ssm_config_permissions() {
    print_info "Checking permissions for SSM configuration..."
    local missing_perms=()
    
    # Check IAM permissions - test by creating a temporary role
    # We check if the error is AccessDenied vs other errors (like NoSuchEntity)
    TEST_ROLE_NAME="ssm-config-test-$(date +%s)"
    IAM_CREATE_OUTPUT=$(aws_cmd iam create-role \
        --role-name "$TEST_ROLE_NAME" \
        --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
        2>&1)
    IAM_CREATE_EXIT=$?
    
    if [ $IAM_CREATE_EXIT -ne 0 ]; then
        # Check if it's a permission error vs other error (like role already exists)
        if echo "$IAM_CREATE_OUTPUT" | grep -qi "AccessDenied\|UnauthorizedOperation"; then
            missing_perms+=("iam:CreateRole")
        elif echo "$IAM_CREATE_OUTPUT" | grep -qi "EntityAlreadyExists"; then
            # Role exists, try to delete it and recreate
            aws_cmd iam delete-role --role-name "$TEST_ROLE_NAME" > /dev/null 2>&1
            sleep 1
            # Try again
            if ! aws_cmd iam create-role \
                --role-name "$TEST_ROLE_NAME" \
                --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
                > /dev/null 2>&1; then
                # Check error again
                IAM_CREATE_OUTPUT2=$(aws_cmd iam create-role \
                    --role-name "$TEST_ROLE_NAME" \
                    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
                    2>&1)
                if echo "$IAM_CREATE_OUTPUT2" | grep -qi "AccessDenied\|UnauthorizedOperation"; then
                    missing_perms+=("iam:CreateRole")
                fi
            fi
        fi
    else
        # Successfully created, check attach policy permission
        if ! aws_cmd iam attach-role-policy \
            --role-name "$TEST_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" \
            > /dev/null 2>&1; then
            ATTACH_OUTPUT=$(aws_cmd iam attach-role-policy \
                --role-name "$TEST_ROLE_NAME" \
                --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" \
                2>&1)
            if echo "$ATTACH_OUTPUT" | grep -qi "AccessDenied\|UnauthorizedOperation"; then
                missing_perms+=("iam:AttachRolePolicy")
            fi
        fi
        # Clean up test role
        aws_cmd iam delete-role --role-name "$TEST_ROLE_NAME" > /dev/null 2>&1
    fi
    
    # Check EC2 permissions
    EC2_DESCRIBE_OUTPUT=$(aws_cmd ec2 describe-instances --instance-ids "$SELECTED_INSTANCE_ID" 2>&1)
    if [ $? -ne 0 ]; then
        if echo "$EC2_DESCRIBE_OUTPUT" | grep -qi "AccessDenied\|UnauthorizedOperation"; then
            missing_perms+=("ec2:DescribeInstances")
        fi
    fi
    
    EC2_DESCRIBE_PROFILE_OUTPUT=$(aws_cmd ec2 describe-iam-instance-profile-associations --filters "Name=instance-id,Values=$SELECTED_INSTANCE_ID" 2>&1)
    if [ $? -ne 0 ]; then
        if echo "$EC2_DESCRIBE_PROFILE_OUTPUT" | grep -qi "AccessDenied\|UnauthorizedOperation"; then
            missing_perms+=("ec2:DescribeIamInstanceProfileAssociations")
        fi
    fi
    
    # Test associate permission (this will fail but we check the error type)
    ASSOCIATE_OUTPUT=$(aws_cmd ec2 associate-iam-instance-profile --instance-id "$SELECTED_INSTANCE_ID" --iam-instance-profile Name="test" 2>&1)
    if echo "$ASSOCIATE_OUTPUT" | grep -qi "AccessDenied\|UnauthorizedOperation"; then
        missing_perms+=("ec2:AssociateIamInstanceProfile")
    fi
    
    # Check IAM instance profile permissions
    TEST_PROFILE_NAME="ssm-config-test-profile-$(date +%s)"
    IAM_PROFILE_OUTPUT=$(aws_cmd iam create-instance-profile --instance-profile-name "$TEST_PROFILE_NAME" 2>&1)
    if [ $? -ne 0 ]; then
        if echo "$IAM_PROFILE_OUTPUT" | grep -qi "AccessDenied\|UnauthorizedOperation"; then
            missing_perms+=("iam:CreateInstanceProfile")
        elif echo "$IAM_PROFILE_OUTPUT" | grep -qi "EntityAlreadyExists"; then
            # Profile exists, clean it up
            aws_cmd iam delete-instance-profile --instance-profile-name "$TEST_PROFILE_NAME" > /dev/null 2>&1
        fi
    else
        # Successfully created, clean up
        aws_cmd iam delete-instance-profile --instance-profile-name "$TEST_PROFILE_NAME" > /dev/null 2>&1
    fi
    
    # Export missing permissions to global variable
    MISSING_PERMS=("${missing_perms[@]}")
    
    if [ ${#MISSING_PERMS[@]} -gt 0 ]; then
        return 1
    fi
    return 0
}

# Function to check if AWS credentials are valid
check_aws_credentials() {
    local test_output=$(aws_cmd sts get-caller-identity 2>&1)
    if echo "$test_output" | grep -qi "InvalidClientTokenId\|ExpiredToken\|InvalidAccessKeyId"; then
        return 1
    fi
    return 0
}

# Function to handle alternative connection methods (SSH, etc.)
handle_alternative_connection() {
    local instance_id=$1
    
    echo ""
    print_info "Alternative Connection Methods"
    echo ""
    echo "Available connection methods:"
    echo "  1) SSH (Secure Shell)"
    echo "  2) Exit"
    echo ""
    
    while true; do
        read_input "Select connection method (1 or 2): " CONNECTION_METHOD
        # Validate CONNECTION_METHOD - must be numeric only
        if [ -z "$CONNECTION_METHOD" ]; then
            print_error "Input cannot be empty. Please select 1 or 2."
            continue
        fi
        if [[ ! "$CONNECTION_METHOD" =~ ^[0-9]+$ ]]; then
            print_error "Invalid input: '$CONNECTION_METHOD'. Please enter only numbers (1 or 2)."
            continue
        fi
        if [ "$CONNECTION_METHOD" -lt 1 ] || [ "$CONNECTION_METHOD" -gt 2 ]; then
            print_error "Invalid option: '$CONNECTION_METHOD'. Please select 1 or 2."
            continue
        fi
        break
    done
    
    case $CONNECTION_METHOD in
        1)
            connect_via_ssh "$instance_id"
            ;;
        2)
            print_info "Exiting."
            exit 0
            ;;
    esac
}

# Function to connect via SSH
connect_via_ssh() {
    local instance_id=$1
    
    echo ""
    print_info "SSH Connection Setup"
    echo ""
    
    # Get instance details
    print_info "Fetching instance details..."
    INSTANCE_DETAILS=$(aws_cmd ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress,KeyName,Platform]' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$INSTANCE_DETAILS" ] || [ "$INSTANCE_DETAILS" == "None" ]; then
        print_warning "Could not fetch instance details. You'll need to provide connection information manually."
        PUBLIC_IP=""
        PRIVATE_IP=""
        KEY_NAME=""
        PLATFORM=""
    else
        IFS=$'\t' read -r PUBLIC_IP PRIVATE_IP KEY_NAME PLATFORM <<< "$INSTANCE_DETAILS"
    fi
    
    # Display available IPs
    echo ""
    if [ ! -z "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "None" ]; then
        print_info "Instance Public IP: $PUBLIC_IP"
    fi
    if [ ! -z "$PRIVATE_IP" ] && [ "$PRIVATE_IP" != "None" ]; then
        print_info "Instance Private IP: $PRIVATE_IP"
    fi
    if [ ! -z "$KEY_NAME" ] && [ "$KEY_NAME" != "None" ]; then
        print_info "Instance Key Pair: $KEY_NAME"
    fi
    if [ ! -z "$PLATFORM" ] && [ "$PLATFORM" != "None" ]; then
        print_info "Platform: $PLATFORM"
    fi
    echo ""
    
    # Get IP address to connect to
    if [ ! -z "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "None" ]; then
        DEFAULT_IP="$PUBLIC_IP"
        print_info "Using Public IP (default): $PUBLIC_IP"
        read_input "Enter IP address to connect to (press Enter for $PUBLIC_IP, or enter Private IP $([ ! -z "$PRIVATE_IP" ] && [ "$PRIVATE_IP" != "None" ] && echo "$PRIVATE_IP" || echo "N/A")): " SSH_IP
        if [ -z "$SSH_IP" ]; then
            SSH_IP="$PUBLIC_IP"
        fi
    elif [ ! -z "$PRIVATE_IP" ] && [ "$PRIVATE_IP" != "None" ]; then
        DEFAULT_IP="$PRIVATE_IP"
        print_info "No Public IP available. Using Private IP: $PRIVATE_IP"
        read_input "Enter IP address to connect to (press Enter for $PRIVATE_IP): " SSH_IP
        if [ -z "$SSH_IP" ]; then
            SSH_IP="$PRIVATE_IP"
        fi
    else
        read_input "Enter IP address to connect to: " SSH_IP
        if [ -z "$SSH_IP" ]; then
            print_error "IP address is required!"
            exit 1
        fi
    fi
    
    # Get port (default 22)
    read_input "Enter SSH port (press Enter for default 22): " SSH_PORT
    if [ -z "$SSH_PORT" ]; then
        SSH_PORT=22
    fi
    
    # Validate port is numeric
    if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]]; then
        print_error "Port must be a number!"
        exit 1
    fi
    
    # Get username
    if [ ! -z "$PLATFORM" ] && [ "$PLATFORM" == "Windows" ]; then
        DEFAULT_USER="Administrator"
    else
        # Try to detect default user based on AMI
        DEFAULT_USER="ec2-user"  # Default for Amazon Linux
    fi
    
    read_input "Enter SSH username (press Enter for default '$DEFAULT_USER'): " SSH_USER
    if [ -z "$SSH_USER" ]; then
        SSH_USER="$DEFAULT_USER"
    fi
    
    # Validate username is not empty
    if [ -z "$SSH_USER" ]; then
        print_error "Username is required!"
        exit 1
    fi
    
    # Get authentication method
    echo ""
    print_info "SSH Authentication Method:"
    echo "  1) Password"
    echo "  2) Private Key (PEM file)"
    echo ""
    
    while true; do
        read_input "Select authentication method (1 or 2): " SSH_AUTH_METHOD
        # Validate SSH_AUTH_METHOD - must be numeric only
        if [ -z "$SSH_AUTH_METHOD" ]; then
            print_error "Input cannot be empty. Please select 1 or 2."
            continue
        fi
        if [[ ! "$SSH_AUTH_METHOD" =~ ^[0-9]+$ ]]; then
            print_error "Invalid input: '$SSH_AUTH_METHOD'. Please enter only numbers (1 or 2)."
            continue
        fi
        if [ "$SSH_AUTH_METHOD" -lt 1 ] || [ "$SSH_AUTH_METHOD" -gt 2 ]; then
            print_error "Invalid option: '$SSH_AUTH_METHOD'. Please select 1 or 2."
            continue
        fi
        break
    done
    
    # Handle authentication method
    SSH_PASSWORD=""
    SSH_KEY_FILE=""
    
    case $SSH_AUTH_METHOD in
        1)
            # Password authentication
            print_info "Using password authentication"
            echo ""
            print_warning "Note: SSH password authentication may require additional configuration on the server."
            print_info "If password authentication fails, you may need to use key-based authentication."
            echo ""
            
            # Check if sshpass is available for non-interactive password entry
            if command_exists sshpass; then
                read -sp "Enter SSH password: " SSH_PASSWORD
                echo ""
                if [ -z "$SSH_PASSWORD" ]; then
                    print_error "Password is required!"
                    exit 1
                fi
            else
                print_info "Note: 'sshpass' is not installed. You'll be prompted for password interactively."
                print_info "To install sshpass:"
                OS_TYPE=$(uname -s)
                if [ "$OS_TYPE" == "Darwin" ]; then
                    echo "  brew install hudochenkov/sshpass/sshpass"
                elif [ "$OS_TYPE" == "Linux" ]; then
                    echo "  sudo apt-get install sshpass  # Debian/Ubuntu"
                    echo "  sudo yum install sshpass      # RHEL/CentOS"
                fi
                echo ""
                print_info "Proceeding with interactive password prompt..."
            fi
            ;;
        2)
            # Key-based authentication
            print_info "Using private key authentication"
            echo ""
            
            # Suggest key file if key name is known
            if [ ! -z "$KEY_NAME" ] && [ "$KEY_NAME" != "None" ]; then
                SUGGESTED_KEY="$HOME/.ssh/${KEY_NAME}.pem"
                if [ -f "$SUGGESTED_KEY" ]; then
                    print_info "Found key file: $SUGGESTED_KEY"
                    print_info "💡 Tip: Use Tab key for file/folder autocompletion"
                    read_file_path "Enter path to private key file (press Enter for $SUGGESTED_KEY): " SSH_KEY_FILE
                    if [ -z "$SSH_KEY_FILE" ]; then
                        SSH_KEY_FILE="$SUGGESTED_KEY"
                    fi
                else
                    print_info "💡 Tip: Use Tab key for file/folder autocompletion"
                    read_file_path "Enter path to private key file (suggested: $SUGGESTED_KEY): " SSH_KEY_FILE
                    if [ -z "$SSH_KEY_FILE" ]; then
                        SSH_KEY_FILE="$SUGGESTED_KEY"
                    fi
                fi
            else
                print_info "💡 Tip: Use Tab key for file/folder autocompletion"
                read_file_path "Enter path to private key file: " SSH_KEY_FILE
            fi
            
            if [ -z "$SSH_KEY_FILE" ]; then
                print_error "Private key file path is required!"
                exit 1
            fi
            
            # Expand ~ and resolve path
            SSH_KEY_FILE="${SSH_KEY_FILE/#\~/$HOME}"
            # Try to resolve absolute path (works on both Linux and macOS)
            if [ -f "$SSH_KEY_FILE" ]; then
                # Use readlink if available, otherwise use the path as-is
                if command_exists readlink; then
                    SSH_KEY_FILE=$(readlink -f "$SSH_KEY_FILE" 2>/dev/null || echo "$SSH_KEY_FILE")
                elif [ "$SSH_KEY_FILE" != "${SSH_KEY_FILE#/}" ]; then
                    # Already absolute path
                    :
                else
                    # Relative path, make it absolute
                    SSH_KEY_FILE="$(cd "$(dirname "$SSH_KEY_FILE")" && pwd)/$(basename "$SSH_KEY_FILE")"
                fi
            fi
            
            # Check if key file exists
            if [ ! -f "$SSH_KEY_FILE" ]; then
                print_error "Private key file not found: $SSH_KEY_FILE"
                exit 1
            fi
            
            # Check key file permissions (should be 600 or 400)
            KEY_PERMS=$(stat -f "%OLp" "$SSH_KEY_FILE" 2>/dev/null || stat -c "%a" "$SSH_KEY_FILE" 2>/dev/null || echo "000")
            if [ "$KEY_PERMS" != "600" ] && [ "$KEY_PERMS" != "400" ] && [ "$KEY_PERMS" != "0600" ] && [ "$KEY_PERMS" != "0400" ]; then
                print_warning "Private key file permissions are $KEY_PERMS (recommended: 600 or 400)"
                read_input "Fix permissions? (y/n, default: y): " FIX_PERMS
                if [ "$FIX_PERMS" != "n" ] && [ "$FIX_PERMS" != "N" ]; then
                    chmod 600 "$SSH_KEY_FILE"
                    print_success "Updated key file permissions to 600"
                fi
            fi
            ;;
    esac
    
    # Build final SSH command
    if [ "$SSH_AUTH_METHOD" == "1" ] && command_exists sshpass && [ ! -z "$SSH_PASSWORD" ]; then
        # Password authentication with sshpass
        SSH_FULL_CMD="sshpass -p '${SSH_PASSWORD}' ssh -p $SSH_PORT $SSH_USER@$SSH_IP"
    elif [ "$SSH_AUTH_METHOD" == "2" ]; then
        # Key-based authentication
        SSH_FULL_CMD="ssh -i '$SSH_KEY_FILE' -p $SSH_PORT $SSH_USER@$SSH_IP"
    else
        # Interactive password (no sshpass)
        SSH_FULL_CMD="ssh -p $SSH_PORT $SSH_USER@$SSH_IP"
    fi
    
    echo ""
    print_info "Connecting to $SSH_USER@$SSH_IP:$SSH_PORT"
    print_info "Press Ctrl+D or type 'exit' to disconnect"
    echo ""
    
    # Execute SSH connection
    eval "$SSH_FULL_CMD"
    
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        print_success "SSH session ended successfully"
    else
        print_error "SSH session ended with error code: $EXIT_CODE"
        echo ""
        print_info "Troubleshooting tips:"
        echo "  - Verify the IP address is correct and accessible"
        echo "  - Check that the SSH service is running on the instance"
        echo "  - Verify security group allows inbound SSH (port $SSH_PORT)"
        echo "  - For password auth: ensure PasswordAuthentication is enabled in sshd_config"
        echo "  - For key auth: verify the key file is correct and has proper permissions"
        exit $EXIT_CODE
    fi
}

# Function to configure SSM on EC2 instance
configure_ssm_for_instance() {
    local instance_id=$1
    
    print_info "Configuring SSM for instance: $instance_id"
    echo ""
    
    # Check credentials before proceeding
    if ! check_aws_credentials; then
        print_error "AWS credentials are invalid or expired!"
        echo ""
        print_info "If you're using aws-vault, the session may have expired."
        print_info "Please re-run the script and authenticate again."
        return 1
    fi
    
    # Get instance details
    INSTANCE_INFO=$(aws_cmd ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].[InstanceId,ImageId,Platform,SubnetId,VpcId,IamInstanceProfile.Arn]' \
        --output text 2>&1)
    
    # Check for credential errors in the output
    if echo "$INSTANCE_INFO" | grep -qi "InvalidClientTokenId\|ExpiredToken\|InvalidAccessKeyId"; then
        print_error "AWS credentials are invalid or expired!"
        echo ""
        print_info "If you're using aws-vault, the session may have expired."
        print_info "Please re-run the script and authenticate again."
        return 1
    fi
    
    if [ -z "$INSTANCE_INFO" ] || [ "$INSTANCE_INFO" == "None" ]; then
        print_error "Could not retrieve instance information"
        return 1
    fi
    
    IFS=$'\t' read -r INST_ID AMI_ID PLATFORM SUBNET_ID VPC_ID EXISTING_PROFILE_ARN <<< "$INSTANCE_INFO"
    
    # Check if instance already has an IAM instance profile
    if [ ! -z "$EXISTING_PROFILE_ARN" ] && [ "$EXISTING_PROFILE_ARN" != "None" ]; then
        print_info "Instance already has an IAM instance profile: $EXISTING_PROFILE_ARN"
        
        # Get the instance profile name from ARN
        EXISTING_PROFILE_NAME=$(echo "$EXISTING_PROFILE_ARN" | awk -F'/' '{print $NF}')
        
        # Get the role associated with this instance profile
        EXISTING_ROLE_NAME=$(aws_cmd iam get-instance-profile \
            --instance-profile-name "$EXISTING_PROFILE_NAME" \
            --query 'InstanceProfile.Roles[0].RoleName' \
            --output text 2>/dev/null || echo "")
        
        if [ ! -z "$EXISTING_ROLE_NAME" ] && [ "$EXISTING_ROLE_NAME" != "None" ]; then
            print_info "Found associated IAM role: $EXISTING_ROLE_NAME"
            
            # Check if the role has SSM permissions
            ATTACHED_POLICIES=$(aws_cmd iam list-attached-role-policies \
                --role-name "$EXISTING_ROLE_NAME" \
                --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore`]' \
                --output text 2>/dev/null || echo "")
            
            if [ ! -z "$ATTACHED_POLICIES" ] && [ "$ATTACHED_POLICIES" != "None" ]; then
                print_success "Instance already has SSM permissions configured!"
                return 0
            else
                print_info "Instance profile exists but doesn't have SSM permissions. Attaching SSM policy to existing role..."
                ATTACH_OUTPUT=$(aws_cmd iam attach-role-policy \
                    --role-name "$EXISTING_ROLE_NAME" \
                    --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" \
                    2>&1)
                ATTACH_EXIT=$?
                
                # Check for credential errors
                if echo "$ATTACH_OUTPUT" | grep -qi "InvalidClientTokenId\|ExpiredToken\|InvalidAccessKeyId"; then
                    print_error "AWS credentials are invalid or expired!"
                    echo ""
                    print_info "If you're using aws-vault, the session may have expired."
                    print_info "Please re-run the script and authenticate again."
                    return 1
                fi
                
                if [ $ATTACH_EXIT -eq 0 ]; then
                    print_success "SSM policy attached to existing role: $EXISTING_ROLE_NAME"
                    print_info "The instance should be ready for SSM connections in a few minutes."
                    return 0
                else
                    # Check if it's a NoSuchEntity error (role doesn't exist)
                    if echo "$ATTACH_OUTPUT" | grep -qi "NoSuchEntity"; then
                        print_warning "The role associated with the instance profile doesn't exist or is inaccessible."
                        print_info "We'll need to replace the instance profile with a new one."
                        echo ""
                        read_input "Replace the existing instance profile? (y/n, default: y): " REPLACE_PROFILE
                        if [ "$REPLACE_PROFILE" != "n" ] && [ "$REPLACE_PROFILE" != "N" ]; then
                            # Disassociate existing instance profile
                            print_info "Disassociating existing instance profile..."
                            ASSOCIATION_ID=$(aws_cmd ec2 describe-iam-instance-profile-associations \
                                --filters "Name=instance-id,Values=$instance_id" \
                                --query 'IamInstanceProfileAssociations[0].AssociationId' \
                                --output text 2>/dev/null || echo "")
                            
                            if [ ! -z "$ASSOCIATION_ID" ] && [ "$ASSOCIATION_ID" != "None" ]; then
                                DISASSOC_OUTPUT=$(aws_cmd ec2 disassociate-iam-instance-profile \
                                    --association-id "$ASSOCIATION_ID" \
                                    2>&1)
                                if [ $? -eq 0 ]; then
                                    print_success "Existing instance profile disassociated"
                                    # Wait a moment for disassociation to complete
                                    sleep 3
                                else
                                    print_error "Failed to disassociate existing instance profile"
                                    echo "$DISASSOC_OUTPUT" | grep -i "error\|exception\|denied" || echo "$DISASSOC_OUTPUT"
                                    return 1
                                fi
                            else
                                print_warning "Could not find association ID, proceeding anyway..."
                            fi
                        else
                            print_info "Keeping existing instance profile. SSM configuration cancelled."
                            return 1
                        fi
                    else
                        print_warning "Could not attach SSM policy to existing role. Creating new role..."
                        echo "$ATTACH_OUTPUT" | grep -i "error\|exception\|denied" || echo "$ATTACH_OUTPUT"
                    fi
                fi
            fi
        else
            print_warning "Could not determine the role associated with the instance profile."
            print_info "We'll create a new instance profile with SSM permissions."
            echo ""
            read_input "Replace the existing instance profile? (y/n, default: y): " REPLACE_PROFILE
            if [ "$REPLACE_PROFILE" != "n" ] && [ "$REPLACE_PROFILE" != "N" ]; then
                # Disassociate existing instance profile
                print_info "Disassociating existing instance profile..."
                ASSOCIATION_ID=$(aws_cmd ec2 describe-iam-instance-profile-associations \
                    --filters "Name=instance-id,Values=$instance_id" \
                    --query 'IamInstanceProfileAssociations[0].AssociationId' \
                    --output text 2>/dev/null || echo "")
                
                if [ ! -z "$ASSOCIATION_ID" ] && [ "$ASSOCIATION_ID" != "None" ]; then
                    DISASSOC_OUTPUT=$(aws_cmd ec2 disassociate-iam-instance-profile \
                        --association-id "$ASSOCIATION_ID" \
                        2>&1)
                    if [ $? -eq 0 ]; then
                        print_success "Existing instance profile disassociated"
                        # Wait a moment for disassociation to complete
                        sleep 3
                    else
                        print_error "Failed to disassociate existing instance profile"
                        echo "$DISASSOC_OUTPUT" | grep -i "error\|exception\|denied" || echo "$DISASSOC_OUTPUT"
                        return 1
                    fi
                else
                    print_warning "Could not find association ID, proceeding anyway..."
                fi
            else
                print_info "Keeping existing instance profile. SSM configuration cancelled."
                return 1
            fi
        fi
    fi
    
    # Create IAM role for SSM
    CLEAN_INSTANCE_ID=$(echo "$instance_id" | sed 's/[^a-zA-Z0-9-]/-/g' | cut -c1-30)
    TIMESTAMP=$(date +%s)
    SSM_ROLE_NAME="ec2-ssm-${CLEAN_INSTANCE_ID}-${TIMESTAMP}"
    
    print_info "Creating IAM role: $SSM_ROLE_NAME"
    IAM_ROLE_OUTPUT=$(aws_cmd iam create-role \
        --role-name "$SSM_ROLE_NAME" \
        --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
        --tags "Key=Name,Value=EC2-SSM-Role-${CLEAN_INSTANCE_ID}" \
               "Key=Purpose,Value=SSM-Connection" \
               "Key=InstanceId,Value=${instance_id}" \
               "Key=CreatedBy,Value=ec2-ssm-connection-script" \
               "Key=CreatedDate,Value=$(date +%Y-%m-%d)" \
        2>&1)
    IAM_ROLE_EXIT=$?
    
    # Check for credential errors
    if echo "$IAM_ROLE_OUTPUT" | grep -qi "InvalidClientTokenId\|ExpiredToken\|InvalidAccessKeyId"; then
        print_error "AWS credentials are invalid or expired!"
        echo ""
        print_info "If you're using aws-vault, the session may have expired."
        print_info "Please re-run the script and authenticate again."
        return 1
    fi
    
    if [ $IAM_ROLE_EXIT -ne 0 ]; then
        print_error "Failed to create IAM role"
        echo "$IAM_ROLE_OUTPUT" | grep -i "error\|exception\|denied" || echo "$IAM_ROLE_OUTPUT"
        return 1
    fi
    
    print_success "IAM role created"
    
    # Attach SSM policy
    print_info "Attaching SSM policy to IAM role..."
    ATTACH_POLICY_OUTPUT=$(aws_cmd iam attach-role-policy \
        --role-name "$SSM_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" \
        2>&1)
    ATTACH_POLICY_EXIT=$?
    
    # Check for credential errors
    if echo "$ATTACH_POLICY_OUTPUT" | grep -qi "InvalidClientTokenId\|ExpiredToken\|InvalidAccessKeyId"; then
        print_error "AWS credentials are invalid or expired!"
        echo ""
        print_info "If you're using aws-vault, the session may have expired."
        print_info "Please re-run the script and authenticate again."
        aws_cmd iam delete-role --role-name "$SSM_ROLE_NAME" > /dev/null 2>&1
        return 1
    fi
    
    if [ $ATTACH_POLICY_EXIT -ne 0 ]; then
        print_error "Failed to attach SSM policy"
        echo "$ATTACH_POLICY_OUTPUT" | grep -i "error\|exception\|denied" || echo "$ATTACH_POLICY_OUTPUT"
        aws_cmd iam delete-role --role-name "$SSM_ROLE_NAME" > /dev/null 2>&1
        return 1
    fi
    
    print_success "SSM policy attached"
    
    # Create instance profile
    SSM_PROFILE_NAME="ec2-ssm-profile-${CLEAN_INSTANCE_ID}-${TIMESTAMP}"
    print_info "Creating IAM instance profile: $SSM_PROFILE_NAME"
    
    PROFILE_OUTPUT=$(aws_cmd iam create-instance-profile \
        --instance-profile-name "$SSM_PROFILE_NAME" \
        2>&1)
    PROFILE_EXIT=$?
    
    # Check for credential errors
    if echo "$PROFILE_OUTPUT" | grep -qi "InvalidClientTokenId\|ExpiredToken\|InvalidAccessKeyId"; then
        print_error "AWS credentials are invalid or expired!"
        echo ""
        print_info "If you're using aws-vault, the session may have expired."
        print_info "Please re-run the script and authenticate again."
        aws_cmd iam delete-role --role-name "$SSM_ROLE_NAME" > /dev/null 2>&1
        return 1
    fi
    
    if [ $PROFILE_EXIT -ne 0 ]; then
        print_error "Failed to create instance profile"
        echo "$PROFILE_OUTPUT" | grep -i "error\|exception\|denied" || echo "$PROFILE_OUTPUT"
        aws_cmd iam delete-role --role-name "$SSM_ROLE_NAME" > /dev/null 2>&1
        return 1
    fi
    
    # Tag the instance profile
    aws_cmd iam tag-instance-profile \
        --instance-profile-name "$SSM_PROFILE_NAME" \
        --tags "Key=Name,Value=EC2-SSM-Instance-Profile-${CLEAN_INSTANCE_ID}" \
               "Key=Purpose,Value=SSM-Connection" \
               "Key=InstanceId,Value=${instance_id}" \
               "Key=CreatedBy,Value=ec2-ssm-connection-script" \
               "Key=CreatedDate,Value=$(date +%Y-%m-%d)" \
        > /dev/null 2>&1
    
    print_info "Adding role to instance profile..."
    if ! aws_cmd iam add-role-to-instance-profile \
        --instance-profile-name "$SSM_PROFILE_NAME" \
        --role-name "$SSM_ROLE_NAME" \
        2>&1; then
        print_error "Failed to add role to instance profile"
        aws_cmd iam delete-instance-profile --instance-profile-name "$SSM_PROFILE_NAME" > /dev/null 2>&1
        aws_cmd iam delete-role --role-name "$SSM_ROLE_NAME" > /dev/null 2>&1
        return 1
    fi
    
    print_success "Instance profile created"
    
    # Get instance profile ARN - wait for it to be available
    print_info "Waiting for instance profile to be ready..."
    PROFILE_ARN=""
    PROFILE_READY=false
    for i in {1..20}; do
        PROFILE_ARN=$(aws_cmd iam get-instance-profile \
            --instance-profile-name "$SSM_PROFILE_NAME" \
            --query 'InstanceProfile.Arn' \
            --output text 2>&1)
        
        # Check if we got a valid ARN (not an error)
        if [ ! -z "$PROFILE_ARN" ] && [ "$PROFILE_ARN" != "None" ] && ! echo "$PROFILE_ARN" | grep -qi "error\|exception\|not found"; then
            # Verify the role is attached
            PROFILE_CHECK=$(aws_cmd iam get-instance-profile \
                --instance-profile-name "$SSM_PROFILE_NAME" \
                --query 'InstanceProfile.Roles[0].RoleName' \
                --output text 2>&1)
            
            if [ ! -z "$PROFILE_CHECK" ] && [ "$PROFILE_CHECK" == "$SSM_ROLE_NAME" ]; then
                PROFILE_READY=true
                break
            fi
        fi
        echo -n "."
        sleep 2
    done
    echo ""
    
    if [ "$PROFILE_READY" == "false" ] || [ -z "$PROFILE_ARN" ] || [ "$PROFILE_ARN" == "None" ]; then
        print_error "Failed to retrieve instance profile ARN or profile not ready"
        print_warning "Instance profile may need more time to propagate."
        print_info "You can try again in a few minutes, or check the instance profile manually."
        aws_cmd iam remove-role-from-instance-profile --instance-profile-name "$SSM_PROFILE_NAME" --role-name "$SSM_ROLE_NAME" > /dev/null 2>&1
        aws_cmd iam delete-instance-profile --instance-profile-name "$SSM_PROFILE_NAME" > /dev/null 2>&1
        aws_cmd iam delete-role --role-name "$SSM_ROLE_NAME" > /dev/null 2>&1
        return 1
    fi
    
    print_success "Instance profile is ready: $PROFILE_ARN"
    
    # Check if instance already has an instance profile associated
    EXISTING_ASSOCIATION=$(aws_cmd ec2 describe-iam-instance-profile-associations \
        --filters "Name=instance-id,Values=$instance_id" \
        --query 'IamInstanceProfileAssociations[0].[AssociationId,IamInstanceProfile.Arn]' \
        --output text 2>&1 || echo "")
    
    if [ ! -z "$EXISTING_ASSOCIATION" ] && [ "$EXISTING_ASSOCIATION" != "None" ]; then
        IFS=$'\t' read -r EXISTING_ASSOC_ID EXISTING_ASSOC_ARN <<< "$EXISTING_ASSOCIATION"
        if [ ! -z "$EXISTING_ASSOC_ID" ] && [ "$EXISTING_ASSOC_ID" != "None" ]; then
            print_warning "Instance already has an instance profile associated: $EXISTING_ASSOC_ARN"
            print_info "Replacing with new instance profile..."
            
            # Disassociate existing
            DISASSOC_OUTPUT=$(aws_cmd ec2 disassociate-iam-instance-profile \
                --association-id "$EXISTING_ASSOC_ID" \
                2>&1)
            
            if [ $? -ne 0 ]; then
                print_error "Failed to disassociate existing instance profile"
                echo "$DISASSOC_OUTPUT" | grep -i "error\|exception\|denied" || echo "$DISASSOC_OUTPUT"
                aws_cmd iam remove-role-from-instance-profile --instance-profile-name "$SSM_PROFILE_NAME" --role-name "$SSM_ROLE_NAME" > /dev/null 2>&1
                aws_cmd iam delete-instance-profile --instance-profile-name "$SSM_PROFILE_NAME" > /dev/null 2>&1
                aws_cmd iam delete-role --role-name "$SSM_ROLE_NAME" > /dev/null 2>&1
                return 1
            fi
            
            print_success "Existing instance profile disassociated"
            # Wait for disassociation to complete
            print_info "Waiting for disassociation to complete..."
            sleep 5
        fi
    fi
    
    # Associate instance profile with EC2 instance
    print_info "Associating instance profile with EC2 instance..."
    ASSOCIATE_OUTPUT=$(aws_cmd ec2 associate-iam-instance-profile \
        --instance-id "$instance_id" \
        --iam-instance-profile Arn="$PROFILE_ARN" \
        2>&1)
    ASSOCIATE_EXIT=$?
    
    # Check for credential errors
    if echo "$ASSOCIATE_OUTPUT" | grep -qi "InvalidClientTokenId\|ExpiredToken\|InvalidAccessKeyId"; then
        print_error "AWS credentials are invalid or expired!"
        echo ""
        print_info "If you're using aws-vault, the session may have expired."
        print_info "Please re-run the script and authenticate again."
        aws_cmd iam remove-role-from-instance-profile --instance-profile-name "$SSM_PROFILE_NAME" --role-name "$SSM_ROLE_NAME" > /dev/null 2>&1
        aws_cmd iam delete-instance-profile --instance-profile-name "$SSM_PROFILE_NAME" > /dev/null 2>&1
        aws_cmd iam delete-role --role-name "$SSM_ROLE_NAME" > /dev/null 2>&1
        return 1
    fi
    
    # Check for InvalidParameterValue - might mean profile needs more time
    if echo "$ASSOCIATE_OUTPUT" | grep -qi "InvalidParameterValue.*Invalid IAM Instance Profile ARN"; then
        print_warning "Instance profile ARN may not be fully propagated yet."
        print_info "Waiting a bit longer and retrying..."
        sleep 10
        
        # Retry association
        ASSOCIATE_OUTPUT=$(aws_cmd ec2 associate-iam-instance-profile \
            --instance-id "$instance_id" \
            --iam-instance-profile Arn="$PROFILE_ARN" \
            2>&1)
        ASSOCIATE_EXIT=$?
    fi
    
    if [ $ASSOCIATE_EXIT -ne 0 ]; then
        print_error "Failed to associate instance profile with instance"
        echo "$ASSOCIATE_OUTPUT" | grep -i "error\|exception\|denied" || echo "$ASSOCIATE_OUTPUT"
        
        # If it's still an InvalidParameterValue, the profile might need even more time
        if echo "$ASSOCIATE_OUTPUT" | grep -qi "InvalidParameterValue.*Invalid IAM Instance Profile ARN"; then
            print_info "The instance profile was created but may need more time to propagate."
            print_info "You can try associating it manually later, or wait a few minutes and run the script again."
            print_info "Instance profile ARN: $PROFILE_ARN"
        fi
        
        aws_cmd iam remove-role-from-instance-profile --instance-profile-name "$SSM_PROFILE_NAME" --role-name "$SSM_ROLE_NAME" > /dev/null 2>&1
        aws_cmd iam delete-instance-profile --instance-profile-name "$SSM_PROFILE_NAME" > /dev/null 2>&1
        aws_cmd iam delete-role --role-name "$SSM_ROLE_NAME" > /dev/null 2>&1
        return 1
    fi
    
    print_success "Instance profile associated with EC2 instance"
    echo ""
    print_info "SSM configuration completed!"
    print_info "The instance may need to be restarted or the SSM agent may need a few minutes to register."
    print_info "Waiting for SSM to become available..."
    
    # Wait for SSM to become available (up to 5 minutes)
    SSM_READY=false
    for i in {1..30}; do
        SSM_CHECK=$(aws_cmd ssm describe-instance-information \
            --filters "Key=InstanceIds,Values=$instance_id" \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null || echo "")
        
        if [ "$SSM_CHECK" == "Online" ]; then
            SSM_READY=true
            break
        fi
        echo -n "."
        sleep 10
    done
    echo ""
    
    if [ "$SSM_READY" == "true" ]; then
        print_success "SSM is now available for the instance!"
        return 0
    else
        print_warning "SSM is not yet available. This may take a few more minutes."
        print_info "You can try connecting again in a few minutes, or restart the instance to speed up the process."
        return 0
    fi
}

# Step 3: Check SSM availability and connect
print_info "Step 3: Connect via SSM"
echo ""

# Check if Session Manager plugin is installed
if ! check_and_install_session_manager_plugin; then
    print_error "Cannot proceed without Session Manager plugin."
    print_info "Please install it and run the script again."
    exit 1
fi

# Check if instance is SSM-managed
print_info "Checking if instance is SSM-managed..."
SSM_INFO=$(aws_cmd ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$SELECTED_INSTANCE_ID" \
    --query 'InstanceInformationList[0].[InstanceId,PingStatus,PlatformType]' \
    --output text 2>/dev/null || echo "")

if [ -z "$SSM_INFO" ] || [ "$SSM_INFO" == "None" ]; then
    print_warning "Instance is not SSM-managed or SSM agent is not running."
    echo ""
    print_info "To use SSM, the instance needs:"
    echo "  1. SSM Agent installed and running"
    echo "  2. IAM instance profile with SSM permissions"
    echo "  3. Network connectivity to SSM service"
    echo ""
    print_info "Options:"
    echo "  1) Configure SSM automatically (requires IAM permissions)"
    echo "  2) Use another connection method (SSH, etc.)"
    echo "  3) Exit and configure manually"
    echo ""
    while true; do
        read_input "Select option (1, 2, or 3): " SSM_OPTION
        # Validate SSM_OPTION - must be numeric only
        if [ -z "$SSM_OPTION" ]; then
            print_error "Input cannot be empty. Please select 1, 2, or 3."
            continue
        fi
        if [[ ! "$SSM_OPTION" =~ ^[0-9]+$ ]]; then
            print_error "Invalid input: '$SSM_OPTION'. Please enter only numbers (1, 2, or 3)."
            continue
        fi
        if [ "$SSM_OPTION" -lt 1 ] || [ "$SSM_OPTION" -gt 3 ]; then
            print_error "Invalid option: '$SSM_OPTION'. Please select 1, 2, or 3."
            continue
        fi
        break
    done
    
    case $SSM_OPTION in
        1)
            # Check permissions first
            if ! check_ssm_config_permissions; then
                print_error "Missing required permissions for SSM configuration:"
                for perm in "${MISSING_PERMS[@]}"; do
                    echo "  - $perm"
                done
                echo ""
                print_error "Please contact your AWS administrator to grant these permissions."
                echo ""
                read_input "Continue anyway? (y/n, default: n): " CONTINUE_ANYWAY
                if [ "$CONTINUE_ANYWAY" != "y" ] && [ "$CONTINUE_ANYWAY" != "Y" ]; then
                    print_info "Exiting. Please configure SSM manually or request permissions."
                    exit 0
                fi
            else
                print_success "Permissions check passed"
                echo ""
                print_warning "This will create IAM resources and associate them with the instance."
                print_info "The following will be created:"
                echo "  - IAM role with SSM permissions"
                echo "  - IAM instance profile"
                echo "  - Association with EC2 instance"
                echo ""
                read_input "Do you want to proceed with SSM configuration? (y/n, default: n): " CONFIRM_CONFIG
                
                if [ "$CONFIRM_CONFIG" != "y" ] && [ "$CONFIRM_CONFIG" != "Y" ]; then
                    print_info "SSM configuration cancelled."
                    echo ""
                    print_info "Options:"
                    echo "  1) Use another connection method"
                    echo "  2) Exit and configure manually"
                    echo ""
                    while true; do
                        read_input "Select option (1 or 2): " ALTERNATIVE_OPTION
                        # Validate ALTERNATIVE_OPTION - must be numeric only
                        if [ -z "$ALTERNATIVE_OPTION" ]; then
                            print_error "Input cannot be empty. Please select 1 or 2."
                            continue
                        fi
                        if [[ ! "$ALTERNATIVE_OPTION" =~ ^[0-9]+$ ]]; then
                            print_error "Invalid input: '$ALTERNATIVE_OPTION'. Please enter only numbers (1 or 2)."
                            continue
                        fi
                        if [ "$ALTERNATIVE_OPTION" -lt 1 ] || [ "$ALTERNATIVE_OPTION" -gt 2 ]; then
                            print_error "Invalid option: '$ALTERNATIVE_OPTION'. Please select 1 or 2."
                            continue
                        fi
                        break
                    done
                    
                    if [ "$ALTERNATIVE_OPTION" == "1" ]; then
                        handle_alternative_connection "$SELECTED_INSTANCE_ID"
                    else
                        exit 0
                    fi
                fi
            fi
            
            # Configure SSM
            if configure_ssm_for_instance "$SELECTED_INSTANCE_ID"; then
                print_success "SSM configuration completed successfully!"
                echo ""
                # Re-check SSM status
                SSM_INFO=$(aws_cmd ssm describe-instance-information \
                    --filters "Key=InstanceIds,Values=$SELECTED_INSTANCE_ID" \
                    --query 'InstanceInformationList[0].[InstanceId,PingStatus,PlatformType]' \
                    --output text 2>/dev/null || echo "")
            else
                print_error "SSM configuration failed"
                echo ""
                print_info "Options:"
                echo "  1) Try connecting anyway (SSM may still work)"
                echo "  2) Use another connection method"
                echo "  3) Exit"
                echo ""
                while true; do
                    read_input "Select option (1, 2, or 3): " FAILED_OPTION
                    # Validate FAILED_OPTION - must be numeric only
                    if [ -z "$FAILED_OPTION" ]; then
                        print_error "Input cannot be empty. Please select 1, 2, or 3."
                        continue
                    fi
                    if [[ ! "$FAILED_OPTION" =~ ^[0-9]+$ ]]; then
                        print_error "Invalid input: '$FAILED_OPTION'. Please enter only numbers (1, 2, or 3)."
                        continue
                    fi
                    if [ "$FAILED_OPTION" -lt 1 ] || [ "$FAILED_OPTION" -gt 3 ]; then
                        print_error "Invalid option: '$FAILED_OPTION'. Please select 1, 2, or 3."
                        continue
                    fi
                    break
                done
                
                if [ "$FAILED_OPTION" == "2" ]; then
                    handle_alternative_connection "$SELECTED_INSTANCE_ID"
                elif [ "$FAILED_OPTION" == "3" ]; then
                    exit 1
                fi
                # Option 1: continue to connection attempt
            fi
            ;;
        2)
            handle_alternative_connection "$SELECTED_INSTANCE_ID"
            ;;
        3)
            print_info "Exiting. Please configure SSM manually and try again."
            exit 0
            ;;
    esac
else
    IFS=$'\t' read -r SSM_INSTANCE_ID PING_STATUS PLATFORM <<< "$SSM_INFO"
    if [ "$PING_STATUS" == "Online" ]; then
        print_success "Instance is SSM-managed and online"
        echo "  Platform: $PLATFORM"
    else
        print_warning "Instance is SSM-managed but status is: $PING_STATUS"
        echo ""
        read_input "Continue anyway? (y/n, default: y): " CONTINUE_ANYWAY
        # Allow y/n/Y/N or empty (defaults to y)
        if [ "$CONTINUE_ANYWAY" == "n" ] || [ "$CONTINUE_ANYWAY" == "N" ]; then
            print_info "Exiting. Please wait for the instance to come online and try again."
            exit 0
        fi
    fi
fi

echo ""
print_info "Connecting to instance: $SELECTED_INSTANCE_ID"
print_info "Press Ctrl+D or type 'exit' to disconnect"
echo ""

# Connect via SSM
if [ "$AWS_VAULT_ENABLED" == "true" ] && [ ! -z "$AWS_VAULT_PROFILE" ]; then
    aws-vault exec "$AWS_VAULT_PROFILE" -- aws ssm start-session --target "$SELECTED_INSTANCE_ID"
else
    aws_cmd ssm start-session --target "$SELECTED_INSTANCE_ID"
fi

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    print_success "Session ended successfully"
else
    print_error "Session ended with error code: $EXIT_CODE"
    exit $EXIT_CODE
fi

