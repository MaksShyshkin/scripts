#!/bin/bash
# Comprehensive RDS Connection Script
# Handles AWS authentication, database selection, secret retrieval, and connection setup

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

# Function to configure DataGrip / IntelliJ IDEA
configure_datagrip() {
    local name=$1
    local host=$2
    local port=$3
    local database=$4
    local username=$5
    local password=$6
    local engine=$7
    
    # DataGrip stores connections in ~/.DataGrip*/config/dataSources/
    # IntelliJ IDEA stores in ~/.IntelliJIdea*/config/dataSources/
    
    DATAGRIP_DIRS=(
        "$HOME/.DataGrip"*
        "$HOME/.IntelliJIdea"*
        "$HOME/Library/Application Support/JetBrains/DataGrip"*
        "$HOME/Library/Application Support/JetBrains/IntelliJIdea"*
    )
    
    CONFIG_DIR=""
    for dir in "${DATAGRIP_DIRS[@]}"; do
        if [ -d "$dir" ] && [ -d "$dir/config/dataSources" ]; then
            CONFIG_DIR="$dir/config/dataSources"
            break
        fi
    done
    
    if [ -z "$CONFIG_DIR" ]; then
        print_warning "DataGrip/IntelliJ IDEA config directory not found."
        print_info "Please create the connection manually in your IDE."
        return
    fi
    
    # Create data source XML
    UUID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "$(date +%s)")
    
    if [ "$engine" == "mysql" ] || [ "$engine" == "mariadb" ]; then
        DRIVER="mysql"
        DRIVER_CLASS="com.mysql.cj.jdbc.Driver"
        JDBC_URL="jdbc:mysql://$host:$port/$database"
    elif [ "$engine" == "postgres" ]; then
        DRIVER="postgresql"
        DRIVER_CLASS="org.postgresql.Driver"
        JDBC_URL="jdbc:postgresql://$host:$port/$database"
    else
        print_warning "Unsupported database engine for DataGrip: $engine"
        return
    fi
    
    XML_FILE="$CONFIG_DIR/${name}.xml"
    
    cat > "$XML_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<dataSource name="$name">
  <driver-class>$DRIVER_CLASS</driver-class>
  <jdbc-url>$JDBC_URL</jdbc-url>
  <user-name>$username</user-name>
  <password>$password</password>
  <driver>$DRIVER</driver>
</dataSource>
EOF
    
    print_success "DataGrip/IntelliJ IDEA connection configured!"
    echo "  Config file: $XML_FILE"
    echo "  Connection name: $name"
    echo ""
    print_info "Restart your IDE or refresh the database connections to see the new connection."
}

# Function to configure DBeaver
configure_dbeaver() {
    local name=$1
    local host=$2
    local port=$3
    local database=$4
    local username=$5
    local password=$6
    local engine=$7
    
    DBEAVER_DIR="$HOME/.dbeaver"
    if [ ! -d "$DBEAVER_DIR" ]; then
        print_warning "DBeaver config directory not found."
        print_info "Please create the connection manually in DBeaver."
        return
    fi
    
    # DBeaver stores connections in data-sources.json
    DATA_SOURCES_FILE="$DBEAVER_DIR/General/.dbeaver/data-sources.json"
    mkdir -p "$(dirname "$DATA_SOURCES_FILE")"
    
    if [ ! -f "$DATA_SOURCES_FILE" ]; then
        echo "{}" > "$DATA_SOURCES_FILE"
    fi
    
    # Generate connection ID
    CONNECTION_ID=$(echo -n "$name" | md5sum | cut -d' ' -f1 | head -c 16)
    
    if [ "$engine" == "mysql" ] || [ "$engine" == "mariadb" ]; then
        DRIVER_ID="mysql"
        JDBC_URL="jdbc:mysql://$host:$port/$database"
    elif [ "$engine" == "postgres" ]; then
        DRIVER_ID="postgresql"
        JDBC_URL="jdbc:postgresql://$host:$port/$database"
    else
        print_warning "Unsupported database engine for DBeaver: $engine"
        return
    fi
    
    # Use jq to add connection if available, otherwise create manual instructions
    if command_exists jq; then
        jq --arg id "$CONNECTION_ID" \
           --arg name "$name" \
           --arg url "$JDBC_URL" \
           --arg user "$username" \
           --arg pass "$password" \
           --arg driver "$DRIVER_ID" \
           '.connections += [{
             "id": $id,
             "name": $name,
             "configuration": {
               "url": $url,
               "user": $user,
               "password": $pass,
               "driver": $driver
             }
           }]' "$DATA_SOURCES_FILE" > "${DATA_SOURCES_FILE}.tmp" && mv "${DATA_SOURCES_FILE}.tmp" "$DATA_SOURCES_FILE"
        
        print_success "DBeaver connection configured!"
        echo "  Config file: $DATA_SOURCES_FILE"
        echo "  Connection name: $name"
        echo ""
        print_info "Restart DBeaver or refresh connections to see the new connection."
    else
        print_warning "jq is required for DBeaver auto-configuration."
        print_info "Please add this connection manually in DBeaver:"
        echo "  Name: $name"
        echo "  URL: $JDBC_URL"
        echo "  Username: $username"
        echo "  Password: $password"
    fi
}

# Function to export connection configuration to file
export_connection_config() {
    local name=$1
    local host=$2
    local port=$3
    local database=$4
    local username=$5
    local password=$6
    local engine=$7
    
    print_info "Exporting connection configuration..."
    echo ""
    
    # Create export directory
    EXPORT_DIR="$HOME/.rds-connection-exports"
    mkdir -p "$EXPORT_DIR"
    
    # Clean name for filename
    CLEAN_NAME=$(echo "$name" | sed 's/[^a-zA-Z0-9_-]/-/g' | tr '[:upper:]' '[:lower:]')
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    
    # Determine driver and connection strings
    if [ "$engine" == "mysql" ] || [ "$engine" == "mariadb" ]; then
        DRIVER="MySQL"
        DRIVER_ID="mysql"
        JDBC_URL="jdbc:mysql://$host:$port/$database"
        CONNECTION_STRING="mysql://$username:$password@$host:$port/$database"
    elif [ "$engine" == "postgres" ]; then
        DRIVER="PostgreSQL"
        DRIVER_ID="postgresql"
        JDBC_URL="jdbc:postgresql://$host:$port/$database"
        CONNECTION_STRING="postgresql://$username:$password@$host:$port/$database"
    else
        print_warning "Unsupported database engine: $engine"
        return 1
    fi
    
    # 1. Generic JSON format (universal)
    JSON_FILE="$EXPORT_DIR/${CLEAN_NAME}-${TIMESTAMP}.json"
    cat > "$JSON_FILE" <<EOF
{
  "name": "$name",
  "type": "database-connection",
  "engine": "$engine",
  "driver": "$DRIVER",
  "connection": {
    "host": "$host",
    "port": $port,
    "database": "$database",
    "username": "$username",
    "password": "$password"
  },
  "connectionStrings": {
    "jdbc": "$JDBC_URL",
    "uri": "$CONNECTION_STRING"
  },
  "exportedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "exportedBy": "rds-connection-script"
}
EOF
    
    # 2. SQLTools format
    SQLTOOLS_FILE="$EXPORT_DIR/${CLEAN_NAME}-sqltools-${TIMESTAMP}.json"
    cat > "$SQLTOOLS_FILE" <<EOF
{
  "connections": [
    {
      "name": "$name",
      "driver": "$DRIVER",
      "server": "$host",
      "port": $port,
      "database": "$database",
      "username": "$username",
      "password": "$password",
      "connectionTimeout": 30,
      "requestTimeout": 30
    }
  ]
}
EOF
    
    # 3. DBeaver format
    DBEAVER_FILE="$EXPORT_DIR/${CLEAN_NAME}-dbeaver-${TIMESTAMP}.json"
    CONNECTION_ID=$(echo -n "$name" | md5sum 2>/dev/null | cut -d' ' -f1 | head -c 16 || echo "$(date +%s)")
    cat > "$DBEAVER_FILE" <<EOF
{
  "folders": {},
  "connections": {
    "$CONNECTION_ID": {
      "provider": "$DRIVER_ID",
      "driver": "$DRIVER_ID",
      "name": "$name",
      "save-password": true,
      "read-only": false,
      "configuration": {
        "host": "$host",
        "port": "$port",
        "database": "$database",
        "url": "$JDBC_URL",
        "type": "dev",
        "auth-model": "native"
      },
      "user": "$username",
      "password": "$password"
    }
  }
}
EOF
    
    # 4. DataGrip/IntelliJ format (XML)
    DATAGRIP_FILE="$EXPORT_DIR/${CLEAN_NAME}-datagrip-${TIMESTAMP}.xml"
    UUID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "$(date +%s)")
    if [ "$engine" == "mysql" ] || [ "$engine" == "mariadb" ]; then
        DRIVER_CLASS="com.mysql.cj.jdbc.Driver"
    else
        DRIVER_CLASS="org.postgresql.Driver"
    fi
    cat > "$DATAGRIP_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<dataSource name="$name">
  <driver-class>$DRIVER_CLASS</driver-class>
  <jdbc-url>$JDBC_URL</jdbc-url>
  <user-name>$username</user-name>
  <password>$password</password>
  <driver>$DRIVER_ID</driver>
</dataSource>
EOF
    
    # 5. Connection strings file (plain text)
    CONNECTION_STRINGS_FILE="$EXPORT_DIR/${CLEAN_NAME}-connection-strings-${TIMESTAMP}.txt"
    cat > "$CONNECTION_STRINGS_FILE" <<EOF
Database Connection Configuration: $name
==========================================
Exported: $(date)
Engine: $engine
Driver: $DRIVER

Connection Details:
------------------
Host:     $host
Port:     $port
Database: $database
Username: $username
Password: $password

Connection Strings:
-------------------
JDBC URL:
  $JDBC_URL

URI Format:
  $CONNECTION_STRING

MySQL Command Line:
  mysql -h $host -P $port -u $username -p$password $database

PostgreSQL Command Line:
  psql -h $host -p $port -U $username -d $database
  (Set PGPASSWORD=$password)

Import Instructions:
-------------------
- SQLTools (VS Code): Copy contents of ${CLEAN_NAME}-sqltools-${TIMESTAMP}.json to ~/.vscode/.sqltools.json or ~/Library/Application Support/Code/User/.sqltools.json
- DBeaver: Import ${CLEAN_NAME}-dbeaver-${TIMESTAMP}.json via Database → Import Connection
- DataGrip/IntelliJ: Copy ${CLEAN_NAME}-datagrip-${TIMESTAMP}.xml to ~/.DataGrip*/config/dataSources/ or ~/.IntelliJIdea*/config/dataSources/
- Generic JSON: Use ${CLEAN_NAME}-${TIMESTAMP}.json for custom tools or manual configuration
EOF
    
    # 6. TablePlus format (JSON)
    TABLEPLUS_FILE="$EXPORT_DIR/${CLEAN_NAME}-tableplus-${TIMESTAMP}.json"
    cat > "$TABLEPLUS_FILE" <<EOF
{
  "connections": [
    {
      "id": "$(uuidgen 2>/dev/null || echo "$(date +%s)")",
      "name": "$name",
      "type": "$engine",
      "host": "$host",
      "port": $port,
      "database": "$database",
      "user": "$username",
      "password": "$password"
    }
  ]
}
EOF
    
    print_success "Connection configuration exported successfully!"
    echo ""
    echo "Export directory: $EXPORT_DIR"
    echo ""
    echo "Exported files:"
    echo "  1. Generic JSON:        $JSON_FILE"
    echo "  2. SQLTools format:      $SQLTOOLS_FILE"
    echo "  3. DBeaver format:       $DBEAVER_FILE"
    echo "  4. DataGrip/IntelliJ:    $DATAGRIP_FILE"
    echo "  5. Connection strings:   $CONNECTION_STRINGS_FILE"
    echo "  6. TablePlus format:     $TABLEPLUS_FILE"
    echo ""
    print_info "How to use these files:"
    echo ""
    echo "SQLTools (VS Code):"
    echo "  • Copy the SQLTools JSON file to:"
    echo "    ~/Library/Application Support/Code/User/.sqltools.json"
    echo "  • Or merge it with your existing .sqltools.json file"
    echo ""
    echo "DBeaver:"
    echo "  • Open DBeaver → Database → Import Connection"
    echo "  • Select the DBeaver JSON file"
    echo ""
    echo "DataGrip/IntelliJ IDEA:"
    echo "  • Copy the XML file to:"
    echo "    ~/.DataGrip*/config/dataSources/ (or ~/.IntelliJIdea*/config/dataSources/)"
    echo "  • Restart your IDE"
    echo ""
    echo "TablePlus:"
    echo "  • Import the TablePlus JSON file via File → Import"
    echo ""
    echo "Generic/Other Tools:"
    echo "  • Use the generic JSON file or connection strings file"
    echo "  • Check the connection strings file for command-line examples"
    echo ""
    echo "All files are saved in: $EXPORT_DIR"
    echo "You can share these files or import them into any compatible database tool."
}

# Function to configure VS Code SQLTools
configure_vscode_sqltools() {
    local name=$1
    local host=$2
    local port=$3
    local database=$4
    local username=$5
    local password=$6
    local engine=$7
    
    print_info "Configuring VS Code SQLTools connection..."
    
    # Check if VS Code is installed
    if ! command_exists code; then
        print_warning "VS Code 'code' command not found in PATH."
        print_info "Please ensure VS Code is installed and the 'code' command is available."
        print_info "You can install it from: https://code.visualstudio.com/"
        print_info ""
        print_info "To enable the 'code' command:"
        echo "  1. Open VS Code"
        echo "  2. Press Cmd+Shift+P (macOS) or Ctrl+Shift+P (Linux/Windows)"
        echo "  3. Type 'Shell Command: Install code command in PATH'"
        echo "  4. Select it and restart your terminal"
        echo ""
        print_info "Connection details for manual configuration:"
        echo "  Name: $name"
        echo "  Driver: $([ "$engine" == "mysql" ] || [ "$engine" == "mariadb" ] && echo "MySQL" || echo "PostgreSQL")"
        echo "  Server: $host"
        echo "  Port: $port"
        echo "  Database: $database"
        echo "  Username: $username"
        echo "  Password: $password"
        return 1
    fi
    
    # Check if SQLTools extension is installed
    print_info "Checking for SQLTools extension..."
    SQLTOOLS_EXTENSION_ID="mtxr.sqltools"
    SQLTOOLS_DRIVER_EXTENSION=""
    
    if [ "$engine" == "mysql" ] || [ "$engine" == "mariadb" ]; then
        SQLTOOLS_DRIVER_EXTENSION="mtxr.sqltools-driver-mysql"
        DRIVER="MySQL"
    elif [ "$engine" == "postgres" ]; then
        SQLTOOLS_DRIVER_EXTENSION="mtxr.sqltools-driver-pg"
        DRIVER="PostgreSQL"
    else
        print_warning "Unsupported database engine for SQLTools: $engine"
        return 1
    fi
    
    # Check if SQLTools main extension is installed
    if ! code --list-extensions 2>/dev/null | grep -q "^${SQLTOOLS_EXTENSION_ID}$"; then
        print_warning "SQLTools extension is not installed."
        print_info "Installing SQLTools extension..."
        
        if code --install-extension "$SQLTOOLS_EXTENSION_ID" 2>/dev/null; then
            print_success "SQLTools extension installed!"
        else
            print_error "Failed to install SQLTools extension automatically."
            print_info "Please install it manually:"
            echo "  1. Open VS Code"
            echo "  2. Go to Extensions (Cmd+Shift+X or Ctrl+Shift+X)"
            echo "  3. Search for 'SQLTools' by Matheus Teixeira"
            echo "  4. Click Install"
            echo ""
            print_info "Or run: code --install-extension $SQLTOOLS_EXTENSION_ID"
            return 1
        fi
    else
        debug_log "SQLTools extension is already installed"
    fi
    
    # Check if driver extension is installed
    if [ ! -z "$SQLTOOLS_DRIVER_EXTENSION" ]; then
        if ! code --list-extensions 2>/dev/null | grep -q "^${SQLTOOLS_DRIVER_EXTENSION}$"; then
            print_warning "$DRIVER driver extension is not installed."
            print_info "Installing $DRIVER driver extension..."
            
            if code --install-extension "$SQLTOOLS_DRIVER_EXTENSION" 2>/dev/null; then
                print_success "$DRIVER driver extension installed!"
            else
                print_error "Failed to install $DRIVER driver extension automatically."
                print_info "Please install it manually:"
                echo "  1. Open VS Code"
                echo "  2. Go to Extensions (Cmd+Shift+X or Ctrl+Shift+X)"
                echo "  3. Search for 'SQLTools $DRIVER' by Matheus Teixeira"
                echo "  4. Click Install"
                echo ""
                print_info "Or run: code --install-extension $SQLTOOLS_DRIVER_EXTENSION"
                return 1
            fi
        else
            debug_log "$DRIVER driver extension is already installed"
        fi
    fi
    
    # Find VS Code user settings directory (SQLTools uses user-level settings, not workspace)
    # Try multiple possible locations
    VSCODE_USER_DIR=""
    
    # macOS
    if [ -d "$HOME/Library/Application Support/Code/User" ]; then
        VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"
    # Linux
    elif [ -d "$HOME/.config/Code/User" ]; then
        VSCODE_USER_DIR="$HOME/.config/Code/User"
    # Windows (if running in WSL or Git Bash)
    elif [ -d "$HOME/AppData/Roaming/Code/User" ]; then
        VSCODE_USER_DIR="$HOME/AppData/Roaming/Code/User"
    # Fallback: try workspace .vscode (less reliable)
    elif [ -d "$HOME/.vscode" ]; then
        VSCODE_USER_DIR="$HOME/.vscode"
        print_warning "Using workspace .vscode directory. SQLTools may prefer user settings directory."
    else
        # Create user settings directory
        if [[ "$OSTYPE" == "darwin"* ]]; then
            VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            VSCODE_USER_DIR="$HOME/.config/Code/User"
        else
            VSCODE_USER_DIR="$HOME/.vscode"
        fi
    fi
    
    # Create directory if it doesn't exist
    if [ ! -d "$VSCODE_USER_DIR" ]; then
        mkdir -p "$VSCODE_USER_DIR"
        debug_log "Created VS Code user directory: $VSCODE_USER_DIR"
    fi
    
    SQLTOOLS_FILE="$VSCODE_USER_DIR/.sqltools.json"
    debug_log "Using SQLTools config file: $SQLTOOLS_FILE"
    
    # Create or update SQLTools config
    if [ ! -f "$SQLTOOLS_FILE" ]; then
        echo '{"connections": []}' > "$SQLTOOLS_FILE"
        debug_log "Created SQLTools config file: $SQLTOOLS_FILE"
    fi
    
    if command_exists jq; then
        # Check if connection with this name already exists
        if jq -e --arg name "$name" '.connections[] | select(.name == $name)' "$SQLTOOLS_FILE" > /dev/null 2>&1; then
            print_warning "Connection '$name' already exists. Updating it..."
            # Remove existing connection
            jq --arg name "$name" 'del(.connections[] | select(.name == $name))' "$SQLTOOLS_FILE" > "${SQLTOOLS_FILE}.tmp" && mv "${SQLTOOLS_FILE}.tmp" "$SQLTOOLS_FILE"
        fi
        
        # Add new connection with proper SQLTools format
        # SQLTools expects specific field names and structure for MySQL
        if [ "$DRIVER" == "MySQL" ]; then
            # MySQL connection format
            jq --arg name "$name" \
               --arg host "$host" \
               --arg port "$port" \
               --arg database "$database" \
               --arg username "$username" \
               --arg password "$password" \
               '.connections += [{
                 "name": $name,
                 "driver": "MySQL",
                 "server": $host,
                 "port": ($port | tonumber),
                 "database": $database,
                 "username": $username,
                 "password": $password,
                 "connectionTimeout": 30,
                 "requestTimeout": 30,
                 "connectionMethod": "default"
               }]' "$SQLTOOLS_FILE" > "${SQLTOOLS_FILE}.tmp" && mv "${SQLTOOLS_FILE}.tmp" "$SQLTOOLS_FILE"
        elif [ "$DRIVER" == "PostgreSQL" ]; then
            # PostgreSQL connection format
            jq --arg name "$name" \
               --arg host "$host" \
               --arg port "$port" \
               --arg database "$database" \
               --arg username "$username" \
               --arg password "$password" \
               '.connections += [{
                 "name": $name,
                 "driver": "PostgreSQL",
                 "server": $host,
                 "port": ($port | tonumber),
                 "database": $database,
                 "username": $username,
                 "password": $password,
                 "connectionTimeout": 30,
                 "requestTimeout": 30
               }]' "$SQLTOOLS_FILE" > "${SQLTOOLS_FILE}.tmp" && mv "${SQLTOOLS_FILE}.tmp" "$SQLTOOLS_FILE"
        fi
        
        # Verify the file was updated correctly
        if [ $? -eq 0 ] && [ -f "$SQLTOOLS_FILE" ]; then
            debug_log "SQLTools config file updated successfully"
            debug_log "File location: $SQLTOOLS_FILE"
            debug_log "File contents preview:"
            cat "$SQLTOOLS_FILE" | jq '.connections[0]' 2>/dev/null | head -15 | while read line; do
                debug_log "  $line"
            done || debug_log "  (Could not parse JSON preview)"
            
            # Verify JSON is valid
            if ! jq empty "$SQLTOOLS_FILE" 2>/dev/null; then
                print_error "Generated JSON is invalid!"
                print_info "File contents:"
                cat "$SQLTOOLS_FILE"
                return 1
            fi
        else
            print_error "Failed to update SQLTools config file"
            return 1
        fi
        
        if [ $? -eq 0 ]; then
            print_success "VS Code SQLTools connection configured!"
            echo "  Config file: $SQLTOOLS_FILE"
            echo "  Connection name: $name"
            echo "  Driver: $DRIVER"
            echo ""
            
            # Also copy to workspace .vscode if it exists (for workspace-level configs)
            WORKSPACE_CONFIG="$HOME/.vscode/.sqltools.json"
            if [ -d "$HOME/.vscode" ] && [ "$SQLTOOLS_FILE" != "$WORKSPACE_CONFIG" ]; then
                debug_log "Also copying config to workspace: $WORKSPACE_CONFIG"
                cp "$SQLTOOLS_FILE" "$WORKSPACE_CONFIG" 2>/dev/null && debug_log "Copied to workspace config" || debug_log "Failed to copy to workspace"
            fi
            
            # Verify the connection was added
            CONNECTION_COUNT=$(jq '.connections | length' "$SQLTOOLS_FILE" 2>/dev/null || echo "0")
            if [ "$CONNECTION_COUNT" -gt 0 ]; then
                print_success "✅ Verified: $CONNECTION_COUNT connection(s) in config file"
                CONNECTION_NAMES=$(jq -r '.connections[].name' "$SQLTOOLS_FILE" 2>/dev/null | tr '\n' ', ' | sed 's/, $//')
                echo "  Connection(s): $CONNECTION_NAMES"
                echo "  Config file: $SQLTOOLS_FILE"
                echo "  File exists: $([ -f "$SQLTOOLS_FILE" ] && echo 'Yes ✅' || echo 'No ❌')"
            else
                print_warning "Warning: No connections found in config file after update"
                print_info "Config file location: $SQLTOOLS_FILE"
            fi
            
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            print_warning "⚠️  IMPORTANT: You MUST reload VS Code for the connection to appear in SQLTools!"
            echo ""
            print_info "📋 Step-by-step instructions to see your connection:"
            echo ""
            echo "Step 1: Reload VS Code Window"
            echo "  • Press Cmd+Shift+P (macOS) or Ctrl+Shift+P (Linux/Windows)"
            echo "  • Type: Developer: Reload Window"
            echo "  • Press Enter"
            echo "  • Wait for VS Code to reload completely"
            echo ""
            echo "Step 2: Open SQLTools Sidebar"
            echo "  • Look for the SQLTools icon in the left sidebar (database cylinder icon)"
            echo "  • Click it, OR"
            echo "  • Press Cmd+Shift+P → Type 'SQLTools: Show SQLTools' → Press Enter"
            echo ""
            echo "Step 3: Find Your Connection"
            echo "  • In the SQLTools sidebar, expand 'CONNECTIONS' section"
            echo "  • Look for: '$name'"
            echo "  • It should appear in the list"
            echo ""
            echo "Step 4: Connect to Database"
            echo "  • Click the 'Connect' button (play icon ▶️) next to the connection name"
            echo "  • If prompted for password, enter: $password"
            echo ""
            echo "Step 5: If Connection Still Doesn't Appear After Reload"
            echo "  • Press Cmd+Shift+P → Type 'SQLTools: Refresh Connections' → Press Enter"
            echo "  • Check SQLTools Output panel: View → Output → Select 'SQLTools' from dropdown"
            echo "  • Verify config file exists:"
            echo "    ls -la \"$SQLTOOLS_FILE\""
            echo "  • View config file:"
            echo "    cat \"$SQLTOOLS_FILE\""
            echo ""
            echo "Connection Details:"
            echo "  Host: $host"
            echo "  Port: $port"
            echo "  Database: $database"
            echo "  Username: $username"
            echo ""
            echo "Note: If you're using a bastion host, make sure the port forwarding is active."
            echo "      The connection will use: $host:$port"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        else
            print_error "Failed to update SQLTools configuration file."
            print_info "Please add this connection manually in VS Code SQLTools:"
            echo "  Name: $name"
            echo "  Driver: $DRIVER"
            echo "  Server: $host"
            echo "  Port: $port"
            echo "  Database: $database"
            echo "  Username: $username"
            echo "  Password: $password"
        fi
    else
        print_warning "jq is required for SQLTools auto-configuration."
        print_info "Please install jq:"
        echo "  macOS: brew install jq"
        echo "  Linux: sudo apt-get install jq (or use your package manager)"
        echo ""
        print_info "Or add this connection manually in VS Code SQLTools:"
        echo "  Name: $name"
        echo "  Driver: $DRIVER"
        echo "  Server: $host"
        echo "  Port: $port"
        echo "  Database: $database"
        echo "  Username: $username"
        echo "  Password: $password"
    fi
}

# Function to configure MySQL Workbench
configure_mysql_workbench() {
    local name=$1
    local host=$2
    local port=$3
    local database=$4
    local username=$5
    local password=$6
    
    WORKBENCH_DIR="$HOME/.mysql/workbench"
    if [ ! -d "$WORKBENCH_DIR" ]; then
        print_warning "MySQL Workbench config directory not found."
        print_info "Please create the connection manually in MySQL Workbench:"
        echo "  Connection Name: $name"
        echo "  Hostname: $host"
        echo "  Port: $port"
        echo "  Username: $username"
        echo "  Password: $password"
        echo "  Default Schema: $database"
        return
    fi
    
    # MySQL Workbench uses XML files in connections.xml
    CONNECTIONS_FILE="$WORKBENCH_DIR/connections.xml"
    
    if [ ! -f "$CONNECTIONS_FILE" ]; then
        cat > "$CONNECTIONS_FILE" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<data>
</data>
EOF
    fi
    
    # Create a simple connection entry (MySQL Workbench format is complex, so we'll create instructions)
    print_info "MySQL Workbench connection details:"
    echo "  Connection Name: $name"
    echo "  Hostname: $host"
    echo "  Port: $port"
    echo "  Username: $username"
    echo "  Password: $password"
    echo "  Default Schema: $database"
    echo ""
    print_info "Please add this connection manually in MySQL Workbench."
    print_info "MySQL Workbench connection file: $CONNECTIONS_FILE"
}

# Function to create bastion host
create_bastion_host() {
    local db_identifier=$1
    local region=$2
    local bastion_id_file=$3  # File to write BASTION_ID to
    
    print_info "Gathering information to create bastion host..."
    
    # Get RDS VPC and subnet information
    RDS_INFO=$(aws_cmd rds describe-db-instances \
        --db-instance-identifier "$db_identifier" \
        --query 'DBInstances[0].[DBSubnetGroup.VpcId,DBSubnetGroup.Subnets[0].SubnetIdentifier,DBSubnetGroup.Subnets[0].AvailabilityZone]' \
        --output text 2>/dev/null)
    
    if [ -z "$RDS_INFO" ] || [ "$RDS_INFO" == "None" ]; then
        print_error "Could not retrieve RDS VPC information. Missing permission: rds:DescribeDBInstances"
        return 1
    fi
    
    VPC_ID=$(echo "$RDS_INFO" | awk '{print $1}')
    SUBNET_ID=$(echo "$RDS_INFO" | awk '{print $2}')
    AZ=$(echo "$RDS_INFO" | awk '{print $3}')
    
    if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
        print_error "Could not determine VPC ID for RDS instance"
        return 1
    fi
    
    print_info "RDS VPC: $VPC_ID"
    print_info "RDS Subnet: $SUBNET_ID"
    
    # Get a public subnet in the same VPC (for bastion)
    PUBLIC_SUBNETS=$(aws_cmd ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
        --query 'Subnets[*].[SubnetId,AvailabilityZone]' \
        --output text 2>/dev/null)
    
    if [ -z "$PUBLIC_SUBNETS" ]; then
        print_warning "No public subnet found. Using private subnet (bastion will need SSM only)."
        BASTION_SUBNET_ID="$SUBNET_ID"
    else
        BASTION_SUBNET_ID=$(echo "$PUBLIC_SUBNETS" | head -1 | awk '{print $1}')
        print_info "Using public subnet for bastion: $BASTION_SUBNET_ID"
    fi
    
    # Get latest Amazon Linux 2 AMI
    print_info "Finding latest Amazon Linux 2 AMI..."
    AMI_ID=$(aws_cmd ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text 2>/dev/null)
    
    if [ -z "$AMI_ID" ] || [ "$AMI_ID" == "None" ]; then
        print_error "Could not find Amazon Linux 2 AMI. Missing permission: ec2:DescribeImages"
        return 1
    fi
    
    print_info "Using AMI: $AMI_ID"
    
    # Create IAM role for bastion (with SSM access)
    # Clean database identifier for use in resource names (remove special chars, limit length)
    CLEAN_DB_ID=$(echo "$db_identifier" | sed 's/[^a-zA-Z0-9-]/-/g' | cut -c1-30)
    TIMESTAMP=$(date +%s)
    BASTION_ROLE_NAME="rds-bastion-${CLEAN_DB_ID}-${TIMESTAMP}"
    print_info "Creating IAM role: $BASTION_ROLE_NAME"
    
    # Check if we can create IAM role
    IAM_ROLE_OUTPUT=$(aws_cmd iam create-role \
        --role-name "$BASTION_ROLE_NAME" \
        --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
        --tags "Key=Name,Value=RDS-Bastion-IAM-Role-${CLEAN_DB_ID}" \
               "Key=Purpose,Value=RDS-Bastion-Host" \
               "Key=Database,Value=${db_identifier}" \
               "Key=CreatedBy,Value=rds-connection-script" \
               "Key=CreatedDate,Value=$(date +%Y-%m-%d)" \
        2>&1)
    
    if [ $? -ne 0 ]; then
        print_error "Failed to create IAM role"
        echo "$IAM_ROLE_OUTPUT" | grep -i "error\|exception\|denied" || echo "$IAM_ROLE_OUTPUT"
        print_error "Missing permission: iam:CreateRole or iam:TagRole"
        print_error "Please contact your AWS administrator to grant IAM permissions or use an existing bastion host."
        return 1
    fi
    
    print_success "IAM role created"
    
    # Attach SSM policy
    print_info "Attaching SSM policy to IAM role..."
    if ! aws_cmd iam attach-role-policy \
        --role-name "$BASTION_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" \
        2>&1; then
        print_error "Failed to attach SSM policy"
        aws_cmd iam delete-role --role-name "$BASTION_ROLE_NAME" > /dev/null 2>&1
        return 1
    fi
    
    print_success "SSM policy attached"
    
    # Create instance profile
    BASTION_PROFILE_NAME="rds-bastion-profile-${CLEAN_DB_ID}-${TIMESTAMP}"
    print_info "Creating IAM instance profile: $BASTION_PROFILE_NAME"
    
    PROFILE_OUTPUT=$(aws_cmd iam create-instance-profile \
        --instance-profile-name "$BASTION_PROFILE_NAME" \
        2>&1)
    
    if [ $? -ne 0 ]; then
        print_error "Failed to create instance profile"
        echo "$PROFILE_OUTPUT" | grep -i "error\|exception\|denied" || echo "$PROFILE_OUTPUT"
        aws_cmd iam delete-role --role-name "$BASTION_ROLE_NAME" > /dev/null 2>&1
        return 1
    fi
    
    # Tag the instance profile
    aws_cmd iam tag-instance-profile \
        --instance-profile-name "$BASTION_PROFILE_NAME" \
        --tags "Key=Name,Value=RDS-Bastion-Instance-Profile-${CLEAN_DB_ID}" \
               "Key=Purpose,Value=RDS-Bastion-Host" \
               "Key=Database,Value=${db_identifier}" \
               "Key=CreatedBy,Value=rds-connection-script" \
               "Key=CreatedDate,Value=$(date +%Y-%m-%d)" \
        > /dev/null 2>&1
    
    print_info "Adding role to instance profile..."
    ADD_ROLE_OUTPUT=$(aws_cmd iam add-role-to-instance-profile \
        --instance-profile-name "$BASTION_PROFILE_NAME" \
        --role-name "$BASTION_ROLE_NAME" \
        2>&1)
    
    if [ $? -ne 0 ]; then
        print_error "Failed to add role to instance profile"
        echo "$ADD_ROLE_OUTPUT" | grep -i "error\|exception\|denied" || echo "$ADD_ROLE_OUTPUT"
        aws_cmd iam delete-instance-profile --instance-profile-name "$BASTION_PROFILE_NAME" > /dev/null 2>&1
        aws_cmd iam delete-role --role-name "$BASTION_ROLE_NAME" > /dev/null 2>&1
        return 1
    fi
    
    print_success "Instance profile created"
    
    # Get the instance profile ARN (needed for EC2 launch)
    print_info "Retrieving instance profile ARN..."
    PROFILE_ARN=$(aws_cmd iam get-instance-profile \
        --instance-profile-name "$BASTION_PROFILE_NAME" \
        --query 'InstanceProfile.Arn' \
        --output text 2>&1)
    
    if [ -z "$PROFILE_ARN" ] || [ "$PROFILE_ARN" == "None" ] || echo "$PROFILE_ARN" | grep -qi "error\|exception"; then
        print_error "Failed to retrieve instance profile ARN"
        echo "$PROFILE_ARN"
        aws_cmd iam remove-role-from-instance-profile --instance-profile-name "$BASTION_PROFILE_NAME" --role-name "$BASTION_ROLE_NAME" > /dev/null 2>&1
        aws_cmd iam delete-instance-profile --instance-profile-name "$BASTION_PROFILE_NAME" > /dev/null 2>&1
        aws_cmd iam delete-role --role-name "$BASTION_ROLE_NAME" > /dev/null 2>&1
        return 1
    fi
    
    debug_log "Instance profile ARN: $PROFILE_ARN"
    
    # Wait for instance profile to be ready (IAM propagation delay)
    # AWS requires instance profiles to propagate before they can be used
    print_info "Waiting for instance profile to propagate (this may take 15-30 seconds)..."
    PROFILE_READY=false
    for i in {1..15}; do
        # Check if the profile is actually available for use
        PROFILE_CHECK=$(aws_cmd iam get-instance-profile \
            --instance-profile-name "$BASTION_PROFILE_NAME" \
            --query 'InstanceProfile.Roles[0].RoleName' \
            --output text 2>&1)
        
        if [ ! -z "$PROFILE_CHECK" ] && [ "$PROFILE_CHECK" == "$BASTION_ROLE_NAME" ] && ! echo "$PROFILE_CHECK" | grep -qi "error\|exception"; then
            # Additional check: verify the profile can be described
            if aws_cmd iam get-instance-profile --instance-profile-name "$BASTION_PROFILE_NAME" > /dev/null 2>&1; then
                PROFILE_READY=true
                break
            fi
        fi
        echo -n "."
        sleep 2
    done
    echo ""
    
    if [ "$PROFILE_READY" == "false" ]; then
        print_warning "Instance profile may not be fully propagated, but proceeding..."
        print_info "If EC2 launch fails, wait 30 seconds and try again"
    else
        print_success "Instance profile is ready"
    fi
    
    # Create security group for bastion
    BASTION_SG_NAME="rds-bastion-sg-${CLEAN_DB_ID}-${TIMESTAMP}"
    print_info "Creating security group: $BASTION_SG_NAME"
    
    SG_OUTPUT=$(aws_cmd ec2 create-security-group \
        --group-name "$BASTION_SG_NAME" \
        --description "Security group for RDS bastion host - allows outbound traffic for database connections via SSM" \
        --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=RDS-Bastion-SecurityGroup-$CLEAN_DB_ID},{Key=Purpose,Value=RDS-Bastion-Host},{Key=Database,Value=$db_identifier},{Key=CreatedBy,Value=rds-connection-script},{Key=CreatedDate,Value=$(date +%Y-%m-%d)}]" \
        --query 'GroupId' \
        --output text 2>&1)
    
    SG_ID="$SG_OUTPUT"
    
    if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ] || echo "$SG_OUTPUT" | grep -qi "error\|exception\|denied"; then
        print_error "Failed to create security group"
        echo "$SG_OUTPUT" | grep -i "error\|exception\|denied" || echo "$SG_OUTPUT"
        print_error "Missing permission: ec2:CreateSecurityGroup or ec2:CreateTags"
        # Cleanup IAM resources
        aws_cmd iam remove-role-from-instance-profile --instance-profile-name "$BASTION_PROFILE_NAME" --role-name "$BASTION_ROLE_NAME" > /dev/null 2>&1
        aws_cmd iam delete-instance-profile --instance-profile-name "$BASTION_PROFILE_NAME" > /dev/null 2>&1
        aws_cmd iam delete-role --role-name "$BASTION_ROLE_NAME" > /dev/null 2>&1
        return 1
    fi
    
    print_success "Security group created: $SG_ID"
    
    # Note: Security groups allow all outbound traffic by default, so we don't need to configure egress rules
    # This avoids potential issues with duplicate rules and makes the script faster
    print_info "Security group egress: Using default (allows all outbound traffic)"
    print_success "Security group configured"
    echo ""
    
    # Create EC2 instance with unique name
    # Base name format: rds-bastion-for-{database-id}
    # This makes it clear what the bastion is for
    BASE_BASTION_NAME="rds-bastion-for-${CLEAN_DB_ID}"
    BASTION_NAME="$BASE_BASTION_NAME"
    
    # Check if an instance with this name already exists
    print_info "Checking for existing bastion hosts with the same name..."
    EXISTING_INSTANCE=$(aws_cmd ec2 describe-instances \
        --filters "Name=tag:Name,Values=$BASE_BASTION_NAME" \
                  "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
        --output text 2>/dev/null | head -1)
    
    if [ ! -z "$EXISTING_INSTANCE" ]; then
        # Instance with this name exists, add timestamp to make it unique
        # Format: rds-bastion-for-{database-id}-{YYYYMMDD-HHMMSS}
        DATE_SUFFIX=$(date +%Y%m%d-%H%M%S)
        BASTION_NAME="${BASE_BASTION_NAME}-${DATE_SUFFIX}"
        EXISTING_ID=$(echo "$EXISTING_INSTANCE" | awk '{print $1}')
        print_warning "Instance with name '$BASE_BASTION_NAME' already exists (ID: $EXISTING_ID)"
        print_info "Using unique name with timestamp: $BASTION_NAME"
    else
        print_info "No existing instance found with name '$BASE_BASTION_NAME' - using base name"
    fi
    echo ""
    
    print_info "Creating EC2 instance: $BASTION_NAME"
    print_info "  AMI: $AMI_ID"
    print_info "  Subnet: $BASTION_SUBNET_ID"
    print_info "  Security Group: $SG_ID"
    print_info "  Instance Profile: $BASTION_PROFILE_NAME"
    
    print_info "Launching EC2 instance (this may take a moment)..."
    debug_log "Creating EC2 instance with:"
    debug_log "  AMI: $AMI_ID"
    debug_log "  Subnet: $BASTION_SUBNET_ID"
    debug_log "  Security Group: $SG_ID"
    debug_log "  Instance Profile: $BASTION_PROFILE_NAME"
    debug_log "  Name: $BASTION_NAME"
    
    # Use ARN format for instance profile (more reliable than name)
    INSTANCE_PROFILE_PARAM=""
    if [ ! -z "$PROFILE_ARN" ]; then
        INSTANCE_PROFILE_PARAM="--iam-instance-profile Arn=$PROFILE_ARN"
        debug_log "Using instance profile ARN: $PROFILE_ARN"
    else
        # Fallback to name if ARN not available
        INSTANCE_PROFILE_PARAM="--iam-instance-profile Name=$BASTION_PROFILE_NAME"
        debug_log "Using instance profile name: $BASTION_PROFILE_NAME"
    fi
    
    INSTANCE_OUTPUT=$(aws_cmd ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type t3.micro \
        --subnet-id "$BASTION_SUBNET_ID" \
        --security-group-ids "$SG_ID" \
        $INSTANCE_PROFILE_PARAM \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$BASTION_NAME},{Key=Purpose,Value=RDS-Bastion-Host},{Key=Database,Value=$db_identifier},{Key=Description,Value=Bastion host for secure RDS database access via SSM},{Key=CreatedBy,Value=rds-connection-script},{Key=CreatedDate,Value=$(date +%Y-%m-%d)},{Key=ManagedBy,Value=Script}]" \
        --query 'Instances[0].InstanceId' \
        --output text \
        2>&1)
    INSTANCE_EXIT_CODE=$?
    debug_log "EC2 run-instances exit code: $INSTANCE_EXIT_CODE"
    debug_log "EC2 run-instances output: $INSTANCE_OUTPUT"
    
    # Extract instance ID from output
    if [ $INSTANCE_EXIT_CODE -eq 0 ]; then
        INSTANCE_ID=$(echo "$INSTANCE_OUTPUT" | head -1 | tr -d '[:space:]')
        debug_log "Extracted Instance ID (method 1): '$INSTANCE_ID'"
        # Check if output contains an error message instead of instance ID
        if [ -z "$INSTANCE_ID" ] || echo "$INSTANCE_OUTPUT" | grep -qi "error\|exception\|denied"; then
            debug_log "Instance ID extraction failed or contains error, trying full JSON output..."
            # Get full output for error reporting
            debug_log "Getting full JSON output for error analysis..."
            INSTANCE_OUTPUT_FULL=$(aws_cmd ec2 run-instances \
                --image-id "$AMI_ID" \
                --instance-type t3.micro \
                --subnet-id "$BASTION_SUBNET_ID" \
                --security-group-ids "$SG_ID" \
                --iam-instance-profile Name="$BASTION_PROFILE_NAME" \
                --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$BASTION_NAME},{Key=Purpose,Value=RDS-Bastion-Host},{Key=Database,Value=$db_identifier},{Key=Description,Value=Bastion host for secure RDS database access via SSM},{Key=CreatedBy,Value=rds-connection-script},{Key=CreatedDate,Value=$(date +%Y-%m-%d)},{Key=ManagedBy,Value=Script}]" \
                2>&1)
            INSTANCE_OUTPUT="$INSTANCE_OUTPUT_FULL"
            debug_log "Full output length: ${#INSTANCE_OUTPUT} characters"
            # Try to extract instance ID from full JSON output
            INSTANCE_ID=$(echo "$INSTANCE_OUTPUT" | grep -o '"InstanceId": "[^"]*"' | cut -d'"' -f4 | head -1)
            debug_log "Extracted Instance ID (method 2 - grep): '$INSTANCE_ID'"
            if [ -z "$INSTANCE_ID" ]; then
                INSTANCE_ID=$(echo "$INSTANCE_OUTPUT" | jq -r '.Instances[0].InstanceId' 2>/dev/null || echo "")
                debug_log "Extracted Instance ID (method 3 - jq): '$INSTANCE_ID'"
            fi
            if [ -z "$INSTANCE_ID" ]; then
                INSTANCE_ID=$(echo "$INSTANCE_OUTPUT" | grep -o 'i-[a-z0-9]*' | head -1)
                debug_log "Extracted Instance ID (method 4 - pattern match): '$INSTANCE_ID'"
            fi
        else
            debug_log "Instance ID successfully extracted: '$INSTANCE_ID'"
        fi
    else
        INSTANCE_ID=""
        debug_log "EC2 run-instances failed with exit code: $INSTANCE_EXIT_CODE"
    fi
    
    debug_log "Final check - Exit code: $INSTANCE_EXIT_CODE, Instance ID: '$INSTANCE_ID'"
    
    if [ $INSTANCE_EXIT_CODE -ne 0 ] || [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ] || [ "$INSTANCE_ID" == "null" ]; then
        print_error "Failed to create EC2 instance"
        echo ""
        debug_log "Full AWS CLI output:"
        echo "$INSTANCE_OUTPUT" | head -50
        echo ""
        echo "AWS CLI Output (first 20 lines):"
        echo "$INSTANCE_OUTPUT" | head -20
        echo ""
        if echo "$INSTANCE_OUTPUT" | grep -qi "error\|exception\|denied"; then
            echo "Error details:"
            echo "$INSTANCE_OUTPUT" | grep -i "error\|exception\|denied" | head -5
        fi
        print_error "Possible causes:"
        echo "  - Missing permission: ec2:RunInstances"
        echo "  - Missing permission: ec2:CreateTags"
        echo "  - Insufficient instance quota"
        echo "  - Invalid subnet or security group"
        echo ""
        print_error "Please contact your AWS administrator to grant EC2 permissions or use an existing bastion host."
        # Cleanup
        aws_cmd ec2 delete-security-group --group-id "$SG_ID" > /dev/null 2>&1
        aws_cmd iam remove-role-from-instance-profile --instance-profile-name "$BASTION_PROFILE_NAME" --role-name "$BASTION_ROLE_NAME" > /dev/null 2>&1
        aws_cmd iam delete-instance-profile --instance-profile-name "$BASTION_PROFILE_NAME" > /dev/null 2>&1
        aws_cmd iam delete-role --role-name "$BASTION_ROLE_NAME" > /dev/null 2>&1
        return 1
    fi
    
    BASTION_ID="$INSTANCE_ID"
    debug_log "Bastion ID set to: $BASTION_ID"
    print_success "Bastion host created successfully!"
    echo "  Instance ID: $INSTANCE_ID"
    echo "  Name: $BASTION_NAME"
    echo "  Security Group: $SG_ID"
    echo "  IAM Role: $BASTION_ROLE_NAME"
    echo "  Instance Profile: $BASTION_PROFILE_NAME"
    echo ""
    print_info "Instance is launching. It will be ready for SSM connections in a few minutes."
    print_info "The script will wait for the instance to be ready before proceeding."
    
    # Write BASTION_ID to file so it's available to the calling function
    if [ ! -z "$bastion_id_file" ]; then
        debug_log "Writing BASTION_ID to file: $bastion_id_file"
        echo "$BASTION_ID" > "$bastion_id_file"
        debug_log "File contents: $(cat "$bastion_id_file" 2>/dev/null || echo 'ERROR: Could not read file')"
    else
        debug_log "No bastion_id_file provided, skipping file write"
    fi
    
    debug_log "create_bastion_host function returning successfully"
    return 0
}

# Function to check and install Session Manager plugin
check_and_install_session_manager_plugin() {
    if command_exists session-manager-plugin; then
        debug_log "Session Manager plugin is already installed"
        return 0
    fi
    
    print_warning "AWS Session Manager plugin is not installed!"
    echo ""
    print_info "The Session Manager plugin is required for SSM port forwarding."
    echo ""
    
    # Detect OS
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
                    echo ""
                    
                    # Try to find the plugin in common locations and add to PATH if needed
                    PLUGIN_PATHS=(
                        "/usr/local/bin/session-manager-plugin"
                        "/opt/homebrew/bin/session-manager-plugin"
                        "$HOME/.local/bin/session-manager-plugin"
                    )
                    
                    PLUGIN_FOUND=false
                    for PLUGIN_PATH in "${PLUGIN_PATHS[@]}"; do
                        if [ -f "$PLUGIN_PATH" ] && [ -x "$PLUGIN_PATH" ]; then
                            # Add to PATH for current session
                            export PATH="$(dirname "$PLUGIN_PATH"):$PATH"
                            PLUGIN_FOUND=true
                            debug_log "Found plugin at: $PLUGIN_PATH"
                            break
                        fi
                    done
                    
                    # Verify it's now available
                    if command_exists session-manager-plugin; then
                        print_success "Plugin is now available in PATH!"
                        return 0
                    elif [ "$PLUGIN_FOUND" == "true" ]; then
                        print_warning "Plugin installed but may not be in PATH for this session."
                        print_info "Trying to use it directly..."
                        # Try to use the full path
                        for PLUGIN_PATH in "${PLUGIN_PATHS[@]}"; do
                            if [ -f "$PLUGIN_PATH" ] && [ -x "$PLUGIN_PATH" ]; then
                                # Create a temporary symlink or alias
                                export PATH="$(dirname "$PLUGIN_PATH"):$PATH"
                                if command_exists session-manager-plugin; then
                                    return 0
                                fi
                            fi
                        done
                    fi
                    
                    print_warning "Plugin installed but may require terminal restart."
                    print_info "You may need to restart your terminal or run:"
                    echo "  source ~/.zshrc  # or ~/.bashrc"
                    echo ""
                    read_input "Press Enter to continue (script will try to proceed)... " DUMMY_INPUT
                    # Try one more time after a moment
                    sleep 2
                    if command_exists session-manager-plugin; then
                        return 0
                    else
                        print_warning "Plugin still not found in PATH. You may need to restart terminal."
                        return 1
                    fi
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
        print_info "Detected Linux. Installing Session Manager plugin..."
        echo ""
        read_input "Install Session Manager plugin now? (y/n, default: y): " INSTALL_PLUGIN
        if [ "$INSTALL_PLUGIN" != "n" ] && [ "$INSTALL_PLUGIN" != "N" ]; then
            PLUGIN_DIR="$HOME/.local/session-manager-plugin"
            PLUGIN_BIN_DIR="$HOME/.local/bin"
            mkdir -p "$PLUGIN_DIR"
            mkdir -p "$PLUGIN_BIN_DIR"
            
            print_info "Downloading Session Manager plugin..."
            PLUGIN_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm"
            
            # Try to detect package manager
            if command_exists yum; then
                # RHEL/CentOS/Amazon Linux
                if curl -fsSL "$PLUGIN_URL" -o /tmp/session-manager-plugin.rpm; then
                    print_info "Installing Session Manager plugin..."
                    if sudo yum install -y /tmp/session-manager-plugin.rpm; then
                        print_success "Session Manager plugin installed successfully!"
                        rm -f /tmp/session-manager-plugin.rpm
                        return 0
                    fi
                fi
            elif command_exists apt-get; then
                # Debian/Ubuntu - need to convert RPM or use .deb
                PLUGIN_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb"
                if curl -fsSL "$PLUGIN_URL" -o /tmp/session-manager-plugin.deb; then
                    print_info "Installing Session Manager plugin..."
                    if sudo apt-get install -y /tmp/session-manager-plugin.deb; then
                        print_success "Session Manager plugin installed successfully!"
                        rm -f /tmp/session-manager-plugin.deb
                        return 0
                    fi
                fi
            fi
            
            # Fallback: manual download
            print_warning "Automatic installation failed. Please install manually:"
            echo "  Download from: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
            return 1
        else
            print_info "Skipping installation. Please install manually:"
            echo "  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
            return 1
        fi
    else
        # Other OS
        print_info "Unsupported OS: $OS_TYPE"
        print_info "Please install Session Manager plugin manually:"
        echo "  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
        return 1
    fi
}

# Function to wait for bastion to be ready
wait_for_bastion_ready() {
    local instance_id=$1
    local max_attempts=36  # 6 minutes total (36 * 10 seconds)
    local attempt=0
    
    # First, wait for instance to be in running state
    print_info "Waiting for instance to be in 'running' state..."
    INSTANCE_STATE=""
    while [ $attempt -lt 12 ]; do  # Wait up to 2 minutes for running state
        INSTANCE_STATE=$(aws_cmd ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null)
        
        if [ "$INSTANCE_STATE" == "running" ]; then
            print_success "Instance is running"
            break
        elif [ "$INSTANCE_STATE" == "pending" ]; then
            echo -n "."
            sleep 10
            attempt=$((attempt + 1))
        else
            print_error "Instance is in unexpected state: $INSTANCE_STATE"
            return 1
        fi
    done
    
    if [ "$INSTANCE_STATE" != "running" ]; then
        print_warning "Instance is not yet running (current state: $INSTANCE_STATE)"
        print_info "This may take a few more minutes. Continuing anyway..."
        return 1
    fi
    
    # Now wait for SSM to be ready
    print_info "Waiting for SSM agent to be ready..."
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        PING_STATUS=$(aws_cmd ssm describe-instance-information \
            --instance-information-filter-list "key=InstanceIds,values=$instance_id" \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null)
        
        if [ "$PING_STATUS" == "Online" ]; then
            echo ""
            print_success "Bastion is ready for SSM connections!"
            return 0
        fi
        
        attempt=$((attempt + 1))
        if [ $((attempt % 3)) -eq 0 ]; then
            echo -n " [${attempt}/${max_attempts}]"
        else
            echo -n "."
        fi
        sleep 10
    done
    
    echo ""
    print_warning "Bastion is still starting. SSM agent may not be ready yet."
    print_info "This usually takes 2-3 minutes after the instance starts running."
    return 1
}

# Function to configure TablePlus
configure_tableplus() {
    local name=$1
    local host=$2
    local port=$3
    local database=$4
    local username=$5
    local password=$6
    local engine=$7
    
    TABLEPLUS_DIR="$HOME/Library/Application Support/com.tinyapp.TablePlus"
    if [ ! -d "$TABLEPLUS_DIR" ]; then
        print_warning "TablePlus config directory not found."
        print_info "Please create the connection manually in TablePlus:"
        echo "  Name: $name"
        echo "  Host: $host"
        echo "  Port: $port"
        echo "  User: $username"
        echo "  Password: $password"
        echo "  Database: $database"
        return
    fi
    
    # TablePlus uses JSON files
    CONNECTIONS_FILE="$TABLEPLUS_DIR/Connections.json"
    
    if [ "$engine" == "mysql" ] || [ "$engine" == "mariadb" ]; then
        DRIVER="MySQL"
    elif [ "$engine" == "postgres" ]; then
        DRIVER="PostgreSQL"
    else
        print_warning "Unsupported database engine for TablePlus: $engine"
        return
    fi
    
    if [ ! -f "$CONNECTIONS_FILE" ]; then
        echo '[]' > "$CONNECTIONS_FILE"
    fi
    
    if command_exists jq; then
        CONNECTION_ID=$(uuidgen 2>/dev/null || echo "$(date +%s)")
        
        jq --arg id "$CONNECTION_ID" \
           --arg name "$name" \
           --arg driver "$DRIVER" \
           --arg host "$host" \
           --arg port "$port" \
           --arg database "$database" \
           --arg username "$username" \
           --arg password "$password" \
           '. += [{
             "id": $id,
             "name": $name,
             "driver": $driver,
             "isSocket": false,
             "host": $host,
             "socketPath": "",
             "port": ($port | tonumber),
             "user": $username,
             "password": $password,
             "database": $database,
             "isOverSSH": false
           }]' "$CONNECTIONS_FILE" > "${CONNECTIONS_FILE}.tmp" && mv "${CONNECTIONS_FILE}.tmp" "$CONNECTIONS_FILE"
        
        print_success "TablePlus connection configured!"
        echo "  Config file: $CONNECTIONS_FILE"
        echo "  Connection name: $name"
        echo ""
        print_info "Restart TablePlus to see the new connection."
    else
        print_warning "jq is required for TablePlus auto-configuration."
        print_info "Please add this connection manually in TablePlus:"
        echo "  Name: $name"
        echo "  Driver: $DRIVER"
        echo "  Host: $host"
        echo "  Port: $port"
        echo "  User: $username"
        echo "  Password: $password"
        echo "  Database: $database"
    fi
}

# Check required tools
if ! command_exists aws; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

if ! command_exists jq; then
    print_error "jq is not installed. Please install it first (brew install jq)."
    exit 1
fi

# Step 1: Get AWS Credentials
echo "=========================================="
echo "  AWS RDS Database Connection Tool"
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

# Unified authentication menu - show all options at once
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
                    # Extract value after = sign (handles both "region = value" and "region=value" formats)
                    # Remove "region" keyword and equals sign, then trim whitespace
                    PROFILE_REGION=$(echo "$REGION_LINE" | sed -E 's/^[[:space:]]*region[[:space:]]*=[[:space:]]*//i' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '"' | tr -d "'")
                fi
            # Check for [profile-name] format (alternative format)
            elif grep -q "^\[$SELECTED_PROFILE\]" "$AWS_CONFIG_FILE"; then
                REGION_LINE=$(sed -n "/^\[$SELECTED_PROFILE\]/,/^\[/p" "$AWS_CONFIG_FILE" | grep -i "^region" | head -1)
                if [ ! -z "$REGION_LINE" ]; then
                    PROFILE_REGION=$(echo "$REGION_LINE" | sed -E 's/^[[:space:]]*region[[:space:]]*=[[:space:]]*//i' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '"' | tr -d "'")
                fi
            fi
            
            # If still not found and it's not "default", check default profile
            if [ -z "$PROFILE_REGION" ] && [ "$SELECTED_PROFILE" != "default" ]; then
                if grep -q "^\[default\]" "$AWS_CONFIG_FILE"; then
                    REGION_LINE=$(sed -n "/^\[default\]/,/^\[/p" "$AWS_CONFIG_FILE" | grep -i "^region" | head -1)
                    if [ ! -z "$REGION_LINE" ]; then
                        PROFILE_REGION=$(echo "$REGION_LINE" | sed -E 's/^[[:space:]]*region[[:space:]]*=[[:space:]]*//i' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '"' | tr -d "'")
                    fi
                fi
            fi
        fi
        
        # Clean up any remaining whitespace
        if [ ! -z "$PROFILE_REGION" ]; then
            PROFILE_REGION=$(echo "$PROFILE_REGION" | xargs)
        fi
        
        if [ ! -z "$PROFILE_REGION" ] && [ "$PROFILE_REGION" != "None" ] && [ "$PROFILE_REGION" != "" ]; then
            AWS_REGION="$PROFILE_REGION"
            print_success "Using region from ~/.aws/config: $AWS_REGION"
            REGION_FROM_PROFILE=true
        else
            print_info "No region configured in ~/.aws/config for profile '$SELECTED_PROFILE'. Using default: $AWS_REGION"
            REGION_FROM_PROFILE=false
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
    print_info "Testing AWS credentials and permissions..."
    
    if ! aws_cmd sts get-caller-identity > /dev/null 2>&1; then
        print_error "Failed to authenticate with AWS"
        print_info "If using aws-vault, make sure the profile exists and credentials are valid"
        exit 1
    fi
fi

# Get account info
ACCOUNT_INFO=$(aws_cmd sts get-caller-identity 2>/dev/null)
ACCOUNT_ID=$(echo "$ACCOUNT_INFO" | jq -r '.Account' 2>/dev/null || echo "unknown")
USER_ARN=$(echo "$ACCOUNT_INFO" | jq -r '.Arn' 2>/dev/null || echo "unknown")

if [ "$SKIP_TO_PERMISSIONS" != "true" ]; then
    print_success "Connected to AWS Account: $ACCOUNT_ID in region: $AWS_REGION"
    echo ""
    
    print_info "Checking required AWS permissions..."
    
    # Check permissions
    MISSING_PERMS=()
    
    if ! aws_cmd sts get-caller-identity > /dev/null 2>&1; then
        MISSING_PERMS+=("sts:GetCallerIdentity")
    fi
    
    if ! aws_cmd rds describe-db-instances --max-items 1 > /dev/null 2>&1; then
        MISSING_PERMS+=("rds:DescribeDBInstances")
    fi
    
    if ! aws_cmd ec2 describe-instances --max-items 1 > /dev/null 2>&1; then
        MISSING_PERMS+=("ec2:DescribeInstances")
    fi
    
    if ! aws_cmd secretsmanager list-secrets --max-results 1 > /dev/null 2>&1; then
        MISSING_PERMS+=("secretsmanager:ListSecrets")
    fi
    
    if ! aws_cmd secretsmanager get-secret-value --secret-id "dummy" > /dev/null 2>&1; then
        # This will fail but we check the error type
        ERROR_OUTPUT=$(aws_cmd secretsmanager get-secret-value --secret-id "dummy" 2>&1)
        if echo "$ERROR_OUTPUT" | grep -qi "AccessDenied\|UnauthorizedOperation"; then
            MISSING_PERMS+=("secretsmanager:GetSecretValue")
        fi
    fi
    
    # Check SSM permission - only report missing if it's an access denied error
    # Note: This might return empty results if no instances are managed by SSM, which is OK
    # We'll check this permission more accurately when actually needed (when using bastion)
    # For now, we'll only check if it's explicitly denied
    SSM_OUTPUT=$(aws_cmd ssm describe-instance-information --max-results 1 2>&1)
    SSM_EXIT_CODE=$?
    if [ $SSM_EXIT_CODE -ne 0 ]; then
        # Only report as missing permission if it's an access denied error
        if echo "$SSM_OUTPUT" | grep -qi "AccessDenied\|UnauthorizedOperation\|AccessDeniedException"; then
            MISSING_PERMS+=("ssm:DescribeInstanceInformation")
        fi
        # If it's a different error (like no instances, service unavailable, etc.), we'll check later when needed
        # This is OK because SSM permission is only needed when using a bastion host
    fi
    
    if [ ${#MISSING_PERMS[@]} -gt 0 ]; then
        print_error "Missing required AWS permissions:"
        for perm in "${MISSING_PERMS[@]}"; do
            echo "  - $perm"
        done
        echo ""
        print_error "Please contact your AWS administrator to grant these permissions."
        exit 1
    fi
    
    print_success "All required permissions verified"
fi

# Continue with rest of script...
if [ "$SKIP_TO_PERMISSIONS" == "true" ]; then
    # Already checked permissions above for aws-vault
    print_success "All required permissions verified"
fi

echo ""

# Step 2: Discover RDS Databases
print_info "Step 2: Discovering RDS Databases..."
echo ""

# Get all RDS instances
RDS_INSTANCES=$(aws_cmd rds describe-db-instances \
    --query 'DBInstances[*].[DBInstanceIdentifier,Engine,Endpoint.Address,Endpoint.Port,DBName,DBInstanceStatus,PubliclyAccessible]' \
    --output text 2>/dev/null)

if [ -z "$RDS_INSTANCES" ] || [ "$RDS_INSTANCES" == "None" ]; then
    print_error "No RDS instances found or missing permission: rds:DescribeDBInstances"
    exit 1
fi

# Parse RDS instances and display
echo "Available RDS Databases:"
echo "======================="
echo ""
printf "%-3s %-40s %-12s %-50s %-6s %-12s %-8s\n" "#" "Database Name" "Engine" "Endpoint" "Port" "Status" "Public"
echo "--------------------------------------------------------------------------------------------------------------------------------------------------------"

COUNT=1
declare -a DB_ARRAY
while IFS=$'\t' read -r IDENTIFIER ENGINE ENDPOINT PORT DBNAME STATUS PUBLIC_ACCESS; do
    PUBLIC_TEXT="No"
    if [ "$PUBLIC_ACCESS" == "True" ]; then
        PUBLIC_TEXT="Yes"
    fi
    # Truncate endpoint if too long for display (keep first 48 chars)
    DISPLAY_ENDPOINT="$ENDPOINT"
    if [ ${#ENDPOINT} -gt 48 ]; then
        DISPLAY_ENDPOINT="${ENDPOINT:0:45}..."
    fi
    printf "%-3s %-40s %-12s %-50s %-6s %-12s %-8s\n" "$COUNT" "$IDENTIFIER" "$ENGINE" "$DISPLAY_ENDPOINT" "$PORT" "$STATUS" "$PUBLIC_TEXT"
    
    # Get secret ARN separately
    SECRET_ARN=$(aws_cmd rds describe-db-instances \
        --db-instance-identifier "$IDENTIFIER" \
        --query 'DBInstances[0].MasterUserSecret.SecretArn' \
        --output text 2>/dev/null || echo "")
    
    DB_ARRAY[$COUNT]="$IDENTIFIER|$ENGINE|$ENDPOINT|$PORT|$DBNAME|$STATUS|$SECRET_ARN|$PUBLIC_ACCESS"
    ((COUNT++))
done <<< "$RDS_INSTANCES"

echo ""
while true; do
    read_input "Select database number: " DB_NUM
    # Validate DB_NUM - must be numeric only
    if [ -z "$DB_NUM" ]; then
        print_error "Input cannot be empty. Please enter a number."
        continue
    fi
    if [[ ! "$DB_NUM" =~ ^[0-9]+$ ]]; then
        print_error "Invalid input: '$DB_NUM'. Please enter only numbers."
        continue
    fi
    if [ "$DB_NUM" -lt 1 ] || [ "$DB_NUM" -ge "$COUNT" ]; then
        print_error "Invalid database number: $DB_NUM. Please select a number between 1 and $((COUNT-1))."
        continue
    fi
    break
done

if [ -z "$DB_NUM" ] || [ "$DB_NUM" -lt 1 ] || [ "$DB_NUM" -ge "$COUNT" ]; then
    print_error "Invalid selection!"
    exit 1
fi

SELECTED_DB="${DB_ARRAY[$DB_NUM]}"
DB_IDENTIFIER=$(echo "$SELECTED_DB" | cut -d'|' -f1)
DB_ENGINE=$(echo "$SELECTED_DB" | cut -d'|' -f2)
DB_ENDPOINT=$(echo "$SELECTED_DB" | cut -d'|' -f3)
DB_PORT=$(echo "$SELECTED_DB" | cut -d'|' -f4)
DB_NAME=$(echo "$SELECTED_DB" | cut -d'|' -f5)
DB_STATUS=$(echo "$SELECTED_DB" | cut -d'|' -f6)
DB_SECRET_ARN=$(echo "$SELECTED_DB" | cut -d'|' -f7)
DB_PUBLIC_ACCESS=$(echo "$SELECTED_DB" | cut -d'|' -f8)

print_success "Selected: $DB_IDENTIFIER ($DB_ENGINE)"
echo "  Endpoint: $DB_ENDPOINT"
echo "  Port: $DB_PORT"
echo "  Database: $DB_NAME"
echo "  Status: $DB_STATUS"
echo "  Publicly Accessible: $DB_PUBLIC_ACCESS"
echo ""

# Step 3: Find Bastion Hosts in the same VPC as the selected database
print_info "Step 3: Finding Bastion Hosts for Database..."
echo ""

# Get RDS VPC information
print_info "Getting database VPC information..."
RDS_VPC_INFO=$(aws_cmd rds describe-db-instances \
    --db-instance-identifier "$DB_IDENTIFIER" \
    --query 'DBInstances[0].[DBSubnetGroup.VpcId,DBSubnetGroup.Subnets[0].SubnetIdentifier]' \
    --output text 2>/dev/null)

if [ -z "$RDS_VPC_INFO" ] || [ "$RDS_VPC_INFO" == "None" ]; then
    print_error "Could not retrieve VPC information for database $DB_IDENTIFIER"
    exit 1
fi

RDS_VPC_ID=$(echo "$RDS_VPC_INFO" | awk '{print $1}')
RDS_SUBNET_ID=$(echo "$RDS_VPC_INFO" | awk '{print $2}')

print_info "Database VPC: $RDS_VPC_ID"
print_info "Database Subnet: $RDS_SUBNET_ID"
echo ""

# Find bastion instances in the same VPC
print_info "Searching for bastion hosts in VPC: $RDS_VPC_ID..."
BASTION_INSTANCES=$(aws_cmd ec2 describe-instances \
    --filters "Name=vpc-id,Values=$RDS_VPC_ID" \
              "Name=instance-state-name,Values=running" \
              "Name=tag:Name,Values=*bastion*,*Bastion*" \
    --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0],SubnetId,SecurityGroups[0].GroupId]' \
    --output text 2>/dev/null || echo "")

BASTION_ID=""
BASTION_NAME=""
USE_BASTION=false

if [ -z "$BASTION_INSTANCES" ]; then
    print_warning "No bastion hosts found in the same VPC as the database."
    echo ""
else
    BASTION_COUNT=$(echo "$BASTION_INSTANCES" | wc -l | tr -d ' ')
    print_success "Found $BASTION_COUNT bastion host(s) in the same VPC:"
    echo ""
    printf "%-3s %-20s %-30s %-20s %-15s\n" "#" "Instance ID" "Name" "Subnet" "Security Group"
    echo "--------------------------------------------------------------------------------------------------------"
    
    COUNT=1
    declare -a BASTION_ARRAY
    while IFS=$'\t' read -r INST_ID INST_NAME SUBNET_ID SG_ID; do
        printf "%-3s %-20s %-30s %-20s %-15s\n" "$COUNT" "$INST_ID" "$INST_NAME" "$SUBNET_ID" "$SG_ID"
        BASTION_ARRAY[$COUNT]="$INST_ID|$INST_NAME|$SUBNET_ID|$SG_ID"
        ((COUNT++))
    done <<< "$BASTION_INSTANCES"
    echo ""
    
    if [ "$DB_PUBLIC_ACCESS" == "False" ]; then
        print_warning "Database is not publicly accessible. A bastion host is required!"
        echo ""
        echo "Options:"
        echo "1) Select from bastion hosts above"
        echo "2) Create a new bastion host automatically"
        echo "3) Enter bastion instance ID manually"
        echo "4) Exit script"
        echo ""
        while true; do
            read_input "Select option (1-4): " BASTION_OPTION
            # Validate BASTION_OPTION - must be numeric only
            if [ -z "$BASTION_OPTION" ]; then
                print_error "Input cannot be empty. Please select 1, 2, 3, or 4."
                continue
            fi
            if [[ ! "$BASTION_OPTION" =~ ^[0-9]+$ ]]; then
                print_error "Invalid input: '$BASTION_OPTION'. Please enter only numbers (1, 2, 3, or 4)."
                continue
            fi
            if [ "$BASTION_OPTION" -lt 1 ] || [ "$BASTION_OPTION" -gt 4 ]; then
                print_error "Invalid option: '$BASTION_OPTION'. Please select 1, 2, 3, or 4."
                continue
            fi
            break
        done
        
        case $BASTION_OPTION in
            1)
                while true; do
                    read_input "Select bastion number (1-$((COUNT-1))): " BASTION_NUM
                    # Validate BASTION_NUM - must be numeric only
                    if [ -z "$BASTION_NUM" ]; then
                        print_error "Input cannot be empty. Please enter a number."
                        continue
                    fi
                    if [[ ! "$BASTION_NUM" =~ ^[0-9]+$ ]]; then
                        print_error "Invalid input: '$BASTION_NUM'. Please enter only numbers."
                        continue
                    fi
                    if [ "$BASTION_NUM" -lt 1 ] || [ "$BASTION_NUM" -ge "$COUNT" ]; then
                        print_error "Invalid bastion number: $BASTION_NUM. Please select a number between 1 and $((COUNT-1))."
                        continue
                    fi
                    break
                done
                if [ -z "$BASTION_NUM" ] || [ "$BASTION_NUM" -lt 1 ] || [ "$BASTION_NUM" -ge "$COUNT" ]; then
                    print_error "Invalid selection!"
                    exit 1
                fi
                SELECTED_BASTION="${BASTION_ARRAY[$BASTION_NUM]}"
                BASTION_ID=$(echo "$SELECTED_BASTION" | cut -d'|' -f1)
                BASTION_NAME=$(echo "$SELECTED_BASTION" | cut -d'|' -f2)
                print_success "Selected bastion: $BASTION_NAME ($BASTION_ID)"
                USE_BASTION=true
                ;;
            2)
                # Create bastion host automatically
                print_info "Creating bastion host automatically..."
                echo ""
                
                # Call function and capture return code
                TEMP_BASTION_FILE=$(mktemp)
                BASTION_ID=""
                
                debug_log "Calling create_bastion_host with:"
                debug_log "  DB_IDENTIFIER: $DB_IDENTIFIER"
                debug_log "  AWS_REGION: $AWS_REGION"
                debug_log "  TEMP_BASTION_FILE: $TEMP_BASTION_FILE"
                
                create_bastion_host "$DB_IDENTIFIER" "$AWS_REGION" "$TEMP_BASTION_FILE"
                CREATE_RESULT=$?
                debug_log "create_bastion_host returned exit code: $CREATE_RESULT"
                
                # Read BASTION_ID from temp file if function succeeded
                if [ $CREATE_RESULT -eq 0 ] && [ -f "$TEMP_BASTION_FILE" ]; then
                    debug_log "Reading BASTION_ID from temp file: $TEMP_BASTION_FILE"
                    BASTION_ID=$(cat "$TEMP_BASTION_FILE" 2>/dev/null || echo "")
                    debug_log "BASTION_ID read from file: '$BASTION_ID'"
                    rm -f "$TEMP_BASTION_FILE"
                else
                    debug_log "Temp file does not exist or function failed. File exists: $([ -f "$TEMP_BASTION_FILE" ] && echo 'yes' || echo 'no')"
                fi
                
                if [ $CREATE_RESULT -eq 0 ] && [ ! -z "$BASTION_ID" ]; then
                    echo ""
                    print_success "Bastion host created: $BASTION_ID"
                    print_info "Waiting for bastion to be ready for SSM connections (this may take 2-3 minutes)..."
                    echo ""
                    
                    # Wait for instance to be ready
                    if wait_for_bastion_ready "$BASTION_ID"; then
                        print_success "Bastion host is ready!"
                        USE_BASTION=true
                    else
                        print_warning "Bastion host was created but is not yet ready for SSM connections."
                        print_info "You can continue, but SSM port forwarding may not work until the instance is ready."
                        print_info "This usually takes 2-3 minutes after instance creation."
                        read_input "Continue anyway? (y/n, default: y): " CONTINUE_ANYWAY
                        if [ "$CONTINUE_ANYWAY" != "n" ] && [ "$CONTINUE_ANYWAY" != "N" ]; then
                            USE_BASTION=true
                        else
                            print_error "Exiting. Please wait a few minutes and try again, or use an existing bastion host."
                            exit 1
                        fi
                    fi
                else
                    echo ""
                    print_error "Failed to create bastion host. Please try option 1 or 3."
                    rm -f "$TEMP_BASTION_FILE"
                    exit 1
                fi
                ;;
            3)
                read_input "Enter Bastion Instance ID: " BASTION_ID
                if [ -z "$BASTION_ID" ]; then
                    print_error "Cannot proceed without bastion host for private RDS instance."
                    exit 1
                fi
                USE_BASTION=true
                ;;
            4)
                print_info "Exiting script."
                exit 0
                ;;
            *)
                print_error "Invalid option!"
                exit 1
                ;;
        esac
    else
        print_info "Database is publicly accessible. You can connect directly or use a bastion for additional security."
        echo ""
        read_input "Do you want to use a bastion host? (y/n, default: n): " USE_BASTION_INPUT
        if [ "$USE_BASTION_INPUT" == "y" ] || [ "$USE_BASTION_INPUT" == "Y" ]; then
            read_input "Select bastion number (1-$((COUNT-1))), or press Enter to skip: " BASTION_NUM
            # Validate BASTION_NUM is a number if provided
            if [ ! -z "$BASTION_NUM" ]; then
                if [[ ! "$BASTION_NUM" =~ ^[0-9]+$ ]]; then
                    print_error "Invalid input: '$BASTION_NUM'. Please enter a number or press Enter to skip."
                    exit 1
                fi
            fi
            if [ ! -z "$BASTION_NUM" ] && [ "$BASTION_NUM" -ge 1 ] && [ "$BASTION_NUM" -lt "$COUNT" ]; then
                SELECTED_BASTION="${BASTION_ARRAY[$BASTION_NUM]}"
                BASTION_ID=$(echo "$SELECTED_BASTION" | cut -d'|' -f1)
                BASTION_NAME=$(echo "$SELECTED_BASTION" | cut -d'|' -f2)
                print_success "Selected bastion: $BASTION_NAME ($BASTION_ID)"
                USE_BASTION=true
            else
                print_info "Proceeding without bastion host (direct connection)."
                USE_BASTION=false
            fi
        else
            print_info "Proceeding without bastion host (direct connection)."
            USE_BASTION=false
        fi
    fi
fi
echo ""

# Step 4: Get Secrets from Secrets Manager
print_info "Step 4: Retrieving Database Credentials..."
echo ""

# Use Master User Secret ARN from RDS instance (preferred method)
SECRET_ARN=""
SECRET_NAME=""

if [ ! -z "$DB_SECRET_ARN" ] && [ "$DB_SECRET_ARN" != "None" ] && [ "$DB_SECRET_ARN" != "null" ]; then
    SECRET_ARN="$DB_SECRET_ARN"
    print_success "Using Master User Secret ARN from RDS instance"
    SECRET_NAME=$(echo "$SECRET_ARN" | awk -F':' '{print $6}' | awk -F'/' '{print $2}')
else
    print_warning "Master User Secret ARN not found in RDS instance."
    print_info "Trying to find secret using alternative methods..."
    
    # Try different secret naming patterns
    SECRET_PATTERNS=(
        "rds!db-*"
        "$DB_IDENTIFIER"
        "${DB_IDENTIFIER}-secret"
        "rds-${DB_IDENTIFIER}"
    )
    
    for PATTERN in "${SECRET_PATTERNS[@]}"; do
        SECRET_LIST=$(aws_cmd secretsmanager list-secrets \
            --filters "Key=name,Values=$PATTERN" \
            --query 'SecretList[*].[Name,ARN]' \
            --output text 2>/dev/null || echo "")
        
        if [ ! -z "$SECRET_LIST" ]; then
            SECRET_NAME=$(echo "$SECRET_LIST" | head -1 | awk '{print $1}')
            SECRET_ARN=$(echo "$SECRET_LIST" | head -1 | awk '{print $2}')
            break
        fi
    done
    
    if [ -z "$SECRET_ARN" ]; then
        # List all secrets and let user choose
        print_warning "Could not auto-detect secret. Listing available secrets..."
        ALL_SECRETS=$(aws_cmd secretsmanager list-secrets \
            --query 'SecretList[*].[Name,ARN]' \
            --output text 2>/dev/null | head -20)
        
        if [ ! -z "$ALL_SECRETS" ]; then
            echo "Available Secrets:"
            echo "$ALL_SECRETS" | nl -w2 -s'. '
            read_input "Select secret number (or press Enter to enter credentials manually): " SECRET_NUM
            # Validate SECRET_NUM is a number if provided
            if [ ! -z "$SECRET_NUM" ]; then
                if [[ ! "$SECRET_NUM" =~ ^[0-9]+$ ]]; then
                    print_error "Invalid input: '$SECRET_NUM'. Please enter a number or press Enter to skip."
                    exit 1
                fi
            fi
            if [ ! -z "$SECRET_NUM" ]; then
                SECRET_NAME=$(echo "$ALL_SECRETS" | sed -n "${SECRET_NUM}p" | awk '{print $1}')
                SECRET_ARN=$(echo "$ALL_SECRETS" | sed -n "${SECRET_NUM}p" | awk '{print $2}')
            fi
        fi
    fi
fi

if [ -z "$SECRET_ARN" ]; then
    print_warning "Could not find secrets in Secrets Manager."
    print_info "You can enter credentials manually or contact your administrator."
    read_input "Enter database username: " DB_USERNAME
    read -sp "Enter database password: " DB_PASSWORD
    DB_PASSWORD=$(echo "$DB_PASSWORD" | tr -d '\r\n')
    echo ""
    
    # Validate credentials are not empty
    if [ -z "$DB_USERNAME" ]; then
        print_error "Database username cannot be empty!"
        exit 1
    fi
    if [ -z "$DB_PASSWORD" ]; then
        print_error "Database password cannot be empty!"
        exit 1
    fi
else
    print_success "Found secret: $SECRET_NAME"
    
    # Check permission to get secret value
    if ! aws_cmd secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query SecretString --output text > /dev/null 2>&1; then
        print_error "Missing permission: secretsmanager:GetSecretValue"
        echo ""
        print_error "Please contact your AWS administrator to grant the following IAM permission:"
        echo "  - secretsmanager:GetSecretValue"
        echo "  - Resource: $SECRET_ARN"
        exit 1
    fi
    
    # Get secret value
    SECRET_VALUE=$(aws_cmd secretsmanager get-secret-value \
        --secret-id "$SECRET_ARN" \
        --query SecretString \
        --output text 2>/dev/null)
    
    if [ -z "$SECRET_VALUE" ]; then
        print_error "Could not retrieve secret value"
        print_error "Please check your permissions for: $SECRET_ARN"
        exit 1
    fi
    
    # Parse secret (handle both JSON and key-value formats)
    if echo "$SECRET_VALUE" | jq empty 2>/dev/null; then
        # JSON format
        DB_USERNAME=$(echo "$SECRET_VALUE" | jq -r '.username // .user // .masterUsername // empty')
        DB_PASSWORD=$(echo "$SECRET_VALUE" | jq -r '.password // .masterPassword // empty')
        
        # If auto-rotation is enabled, the secret might have a different structure
        if [ -z "$DB_USERNAME" ] || [ "$DB_USERNAME" == "null" ]; then
            # Try alternative keys
            DB_USERNAME=$(echo "$SECRET_VALUE" | jq -r 'keys[]' | grep -i user | head -1)
            if [ ! -z "$DB_USERNAME" ]; then
                DB_USERNAME=$(echo "$SECRET_VALUE" | jq -r ".[\"$DB_USERNAME\"]")
            fi
        fi
        
        if [ -z "$DB_PASSWORD" ] || [ "$DB_PASSWORD" == "null" ]; then
            DB_PASSWORD=$(echo "$SECRET_VALUE" | jq -r 'keys[]' | grep -i pass | head -1)
            if [ ! -z "$DB_PASSWORD" ]; then
                DB_PASSWORD=$(echo "$SECRET_VALUE" | jq -r ".[\"$DB_PASSWORD\"]")
            fi
        fi
    else
        # Try to parse as key-value pairs
        DB_USERNAME=$(echo "$SECRET_VALUE" | grep -i "username\|user" | head -1 | cut -d'=' -f2 | tr -d ' ')
        DB_PASSWORD=$(echo "$SECRET_VALUE" | grep -i "password\|pass" | head -1 | cut -d'=' -f2 | tr -d ' ')
    fi
    
    if [ -z "$DB_USERNAME" ] || [ -z "$DB_PASSWORD" ]; then
        print_warning "Could not parse username/password from secret. Showing raw secret:"
        echo "$SECRET_VALUE" | jq '.' 2>/dev/null || echo "$SECRET_VALUE"
        read_input "Enter database username: " DB_USERNAME
        read -sp "Enter database password: " DB_PASSWORD
        DB_PASSWORD=$(echo "$DB_PASSWORD" | tr -d '\r\n')
        echo ""
        
        # Validate credentials are not empty
        if [ -z "$DB_USERNAME" ]; then
            print_error "Database username cannot be empty!"
            exit 1
        fi
        if [ -z "$DB_PASSWORD" ]; then
            print_error "Database password cannot be empty!"
            exit 1
        fi
    else
        print_success "Retrieved credentials from Secrets Manager"
    fi
    
    # Final validation: ensure credentials are not empty before proceeding
    if [ -z "$DB_USERNAME" ] || [ -z "$DB_PASSWORD" ]; then
        print_error "Database credentials are missing! Username or password is empty."
        print_error "Please check your Secrets Manager configuration or enter credentials manually."
        exit 1
    fi
fi

echo ""

# Step 5: Choose Connection Method
print_info "Step 5: Choose Connection Method"
echo ""
echo "How would you like to connect?"
echo "1) Terminal connection (interactive shell)"
echo "2) Show connection settings (copy/paste for manual IDE configuration)"
echo ""
while true; do
    read_input "Select option (1 or 2): " CONNECTION_METHOD
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
echo ""

case $CONNECTION_METHOD in
    1)
        # Terminal connection
        print_info "Setting up terminal connection..."
        echo ""
        
        # Determine local port based on database port
        if [ "$DB_PORT" == "3306" ]; then
            LOCAL_PORT=13306
            CLIENT_CMD="mysql"
        elif [ "$DB_PORT" == "5432" ]; then
            LOCAL_PORT=15432
            CLIENT_CMD="psql"
        else
            LOCAL_PORT=$((10000 + DB_PORT))
            CLIENT_CMD=""
        fi
        
        print_info "Starting port forwarding (local port: $LOCAL_PORT)..."
        echo "Press Ctrl+C to stop port forwarding"
        echo ""
        
        # Start port forwarding in background (if bastion is required)
        if [ "$USE_BASTION" == "true" ]; then
            if [ -z "$BASTION_ID" ]; then
                print_error "Bastion host is required but not specified!"
                exit 1
            fi
            
            # Check and install Session Manager plugin if needed
            if ! check_and_install_session_manager_plugin; then
                print_error "Cannot proceed without Session Manager plugin."
                print_info "Please install it and run the script again."
                exit 1
            fi
            
            # Check SSM permission
            if ! aws_cmd ssm describe-instance-information --instance-information-filter-list "key=InstanceIds,valueSet=$BASTION_ID" > /dev/null 2>&1; then
                print_error "Missing permission: ssm:DescribeInstanceInformation"
                echo ""
                print_error "Please contact your AWS administrator to grant the following IAM permission:"
                echo "  - ssm:StartSession (to establish port forwarding)"
                echo "  - ssm:DescribeInstanceInformation (to verify bastion access)"
                exit 1
            fi
            
            PID_DIR="$HOME/.rds-port-forwarding"
            mkdir -p "$PID_DIR"
            PID_FILE="$PID_DIR/${DB_IDENTIFIER}.pid"
            LOG_FILE="$PID_DIR/${DB_IDENTIFIER}.log"
            
            # Check if already running
            if [ -f "$PID_FILE" ]; then
                OLD_PID=$(cat "$PID_FILE")
                if ps -p $OLD_PID > /dev/null 2>&1; then
                    print_warning "Port forwarding already running (PID: $OLD_PID)"
                    read_input "Kill existing session and start new one? (y/n): " KILL_EXISTING
                    if [ "$KILL_EXISTING" == "y" ]; then
                        kill $OLD_PID 2>/dev/null || true
                        rm -f "$PID_FILE"
                    else
                        print_info "Using existing port forwarding session"
                        sleep 2
                    fi
                fi
            fi
            
            # Start new session if needed
            if [ ! -f "$PID_FILE" ] || ! ps -p $(cat "$PID_FILE") > /dev/null 2>&1; then
                print_info "Starting port forwarding in background..."
                debug_log "Starting SSM port forwarding:"
                debug_log "  Target: $BASTION_ID"
                debug_log "  Remote Host: $DB_ENDPOINT"
                debug_log "  Remote Port: $DB_PORT"
                debug_log "  Local Port: $LOCAL_PORT"
                debug_log "  Log File: $LOG_FILE"
                
                # Verify Session Manager plugin is available before starting
                if ! command_exists session-manager-plugin; then
                    print_error "Session Manager plugin is not available!"
                    print_info "Please install it first:"
                    echo "  macOS: brew install --cask session-manager-plugin"
                    echo "  Or download from: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
                    exit 1
                fi
                
                # Start SSM port forwarding in background
                print_info "Starting SSM port forwarding session..."
                # Build the actual command to run (aws_cmd is a function, so we need to expand it for nohup)
                if [ "$AWS_VAULT_ENABLED" == "true" ] && [ ! -z "$AWS_VAULT_PROFILE" ]; then
                    # Use aws-vault
                    SSM_CMD="aws-vault exec $AWS_VAULT_PROFILE -- aws ssm start-session --target $BASTION_ID --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{\"host\":[\"$DB_ENDPOINT\"],\"portNumber\":[\"$DB_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}'"
                else
                    # Use regular aws command, export environment variables for the subshell
                    export AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION AWS_DEFAULT_REGION
                    SSM_CMD="aws ssm start-session --target $BASTION_ID --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{\"host\":[\"$DB_ENDPOINT\"],\"portNumber\":[\"$DB_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}'"
                fi
                
                nohup bash -c "$SSM_CMD" > "$LOG_FILE" 2>&1 &
                
                SSM_PID=$!
                debug_log "SSM session started with PID: $SSM_PID"
                echo $SSM_PID > "$PID_FILE"
                
                # Wait a moment for the session to establish
                print_info "Waiting for port forwarding to establish..."
                sleep 3
                
                # Check if process is still running
                if ! ps -p $SSM_PID > /dev/null 2>&1; then
                    # Process exited, check the log file for errors
                    print_error "Failed to start port forwarding. Checking log file..."
                    echo ""
                    
                    if [ -f "$LOG_FILE" ]; then
                        LOG_CONTENT=$(cat "$LOG_FILE" 2>/dev/null)
                        if [ ! -z "$LOG_CONTENT" ]; then
                            echo "Error details from log file:"
                            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                            echo "$LOG_CONTENT"
                            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                            echo ""
                            
                            # Check for common error patterns
                            if echo "$LOG_CONTENT" | grep -qi "session-manager-plugin.*not found\|command not found"; then
                                print_error "Session Manager plugin is not installed or not in PATH!"
                                print_info "Please install it:"
                                echo "  macOS: brew install --cask session-manager-plugin"
                                echo "  Or download from: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
                            elif echo "$LOG_CONTENT" | grep -qi "AccessDenied\|UnauthorizedOperation"; then
                                print_error "Missing permission: ssm:StartSession"
                                print_info "Please contact your AWS administrator to grant this permission."
                            elif echo "$LOG_CONTENT" | grep -qi "TargetNotConnected\|InvalidInstanceId"; then
                                print_error "Bastion host is not accessible via SSM."
                                print_info "Make sure the bastion host has the SSM agent running and the IAM role attached."
                            else
                                print_error "Unknown error. Please check the log file: $LOG_FILE"
                            fi
                        else
                            print_error "Log file is empty. The process may have exited immediately."
                            print_info "This usually means:"
                            echo "  1. Session Manager plugin is not installed or not in PATH"
                            echo "  2. Missing permission: ssm:StartSession"
                            echo "  3. Bastion host is not accessible via SSM"
                        fi
                    else
                        print_error "Log file not found. The process may have exited immediately."
                    fi
                    
                    echo ""
                    print_error "Please check the log file for details: $LOG_FILE"
                    rm -f "$PID_FILE"
                    exit 1
                fi
                
                # Check if port is actually listening
                if ! lsof -Pi :$LOCAL_PORT -sTCP:LISTEN > /dev/null 2>&1; then
                    print_warning "Port forwarding process is running but port $LOCAL_PORT is not listening yet."
                    print_info "This may take a few more seconds. Waiting..."
                    sleep 5
                    
                    if ! lsof -Pi :$LOCAL_PORT -sTCP:LISTEN > /dev/null 2>&1; then
                        print_error "Port $LOCAL_PORT is still not listening. Check log: $LOG_FILE"
                        debug_log "Last 20 lines of log file:"
                        tail -20 "$LOG_FILE" 2>/dev/null | while read line; do
                            debug_log "  $line"
                        done
                        kill $SSM_PID 2>/dev/null || true
                        rm -f "$PID_FILE"
                        exit 1
                    fi
                fi
                
                print_success "Port forwarding established on localhost:$LOCAL_PORT"
            else
                EXISTING_PID=$(cat "$PID_FILE")
                print_info "Port forwarding already running (PID: $EXISTING_PID)"
            fi
        else
            # Direct connection (public RDS)
            print_info "Using direct connection (RDS is publicly accessible)"
            LOCAL_PORT=$DB_PORT
        fi
        
        print_success "Port forwarding active on localhost:$LOCAL_PORT"
        echo ""
        
        # Connect to database
        if [ "$USE_BASTION" == "true" ]; then
            CONNECT_HOST="127.0.0.1"
        else
            CONNECT_HOST="$DB_ENDPOINT"
        fi
        
        if [ "$DB_ENGINE" == "mysql" ] || [ "$DB_ENGINE" == "mariadb" ]; then
            if command_exists mysql; then
                print_info "Connecting to MySQL database..."
                echo ""
                # Use MYSQL_PWD environment variable for secure password passing
                # This avoids issues with special characters in passwords
                export MYSQL_PWD="$DB_PASSWORD"
                mysql -h "$CONNECT_HOST" -P $LOCAL_PORT -u "$DB_USERNAME" "$DB_NAME"
                MYSQL_EXIT_CODE=$?
                unset MYSQL_PWD
                
                if [ $MYSQL_EXIT_CODE -ne 0 ]; then
                    echo ""
                    print_error "Failed to connect to MySQL database."
                    print_info "Possible issues:"
                    echo "  1. Incorrect credentials (check Secrets Manager)"
                    echo "  2. User doesn't have permission to connect from this IP"
                    echo "  3. Database name is incorrect"
                    echo ""
                    print_info "You can try connecting manually with:"
                    echo "  export MYSQL_PWD='$DB_PASSWORD'"
                    echo "  mysql -h $CONNECT_HOST -P $LOCAL_PORT -u $DB_USERNAME $DB_NAME"
                    echo "  unset MYSQL_PWD"
                    exit 1
                fi
            else
                print_error "mysql client not found. Install it with: brew install mysql-client"
                print_info "You can connect manually with:"
                echo "  export MYSQL_PWD='$DB_PASSWORD'"
                echo "  mysql -h $CONNECT_HOST -P $LOCAL_PORT -u $DB_USERNAME $DB_NAME"
                echo "  unset MYSQL_PWD"
            fi
        elif [ "$DB_ENGINE" == "postgres" ]; then
            if command_exists psql; then
                print_info "Connecting to PostgreSQL database..."
                echo ""
                export PGPASSWORD="$DB_PASSWORD"
                psql -h "$CONNECT_HOST" -p $LOCAL_PORT -U "$DB_USERNAME" -d "$DB_NAME"
                PSQL_EXIT_CODE=$?
                unset PGPASSWORD
                
                if [ $PSQL_EXIT_CODE -ne 0 ]; then
                    echo ""
                    print_error "Failed to connect to PostgreSQL database."
                    print_info "Possible issues:"
                    echo "  1. Incorrect credentials (check Secrets Manager)"
                    echo "  2. User doesn't have permission to connect"
                    echo "  3. Database name is incorrect"
                    echo ""
                    print_info "You can try connecting manually with:"
                    echo "  export PGPASSWORD='$DB_PASSWORD'"
                    echo "  psql -h $CONNECT_HOST -p $LOCAL_PORT -U $DB_USERNAME -d $DB_NAME"
                    echo "  unset PGPASSWORD"
                    exit 1
                fi
            else
                print_error "psql client not found. Install it with: brew install postgresql"
                print_info "You can connect manually with:"
                echo "  export PGPASSWORD='$DB_PASSWORD'"
                echo "  psql -h $CONNECT_HOST -p $LOCAL_PORT -U $DB_USERNAME -d $DB_NAME"
                echo "  unset PGPASSWORD"
            fi
        else
            print_warning "Unknown database engine: $DB_ENGINE"
            print_info "Connection details:"
            echo "  Host: $CONNECT_HOST"
            echo "  Port: $LOCAL_PORT"
            echo "  Username: $DB_USERNAME"
            echo "  Password: $DB_PASSWORD"
            echo "  Database: $DB_NAME"
        fi
        ;;
        
    2)
        # Show connection settings for manual IDE configuration
        print_info "Setting up connection for IDE configuration..."
        echo ""
        
        # Determine local port
        if [ "$DB_PORT" == "3306" ]; then
            LOCAL_PORT=13306
        elif [ "$DB_PORT" == "5432" ]; then
            LOCAL_PORT=15432
        else
            LOCAL_PORT=$((10000 + DB_PORT))
        fi
        
        if [ "$USE_BASTION" == "true" ]; then
            if [ -z "$BASTION_ID" ]; then
                print_error "Bastion host is required but not specified!"
                exit 1
            fi
            
            # Check and install Session Manager plugin if needed
            if ! check_and_install_session_manager_plugin; then
                print_error "Cannot proceed without Session Manager plugin."
                print_info "Please install it and run the script again."
                exit 1
            fi
            
            # Check SSM permission
            if ! aws_cmd ssm describe-instance-information --instance-information-filter-list "key=InstanceIds,valueSet=$BASTION_ID" > /dev/null 2>&1; then
                print_error "Missing permission: ssm:DescribeInstanceInformation"
                echo ""
                print_error "Please contact your AWS administrator to grant the following IAM permission:"
                echo "  - ssm:StartSession (to establish port forwarding)"
                echo "  - ssm:DescribeInstanceInformation (to verify bastion access)"
                exit 1
            fi
            
            PID_DIR="$HOME/.rds-port-forwarding"
            mkdir -p "$PID_DIR"
            PID_FILE="$PID_DIR/${DB_IDENTIFIER}.pid"
            LOG_FILE="$PID_DIR/${DB_IDENTIFIER}.log"
            
            # Check if already running
            if [ -f "$PID_FILE" ]; then
                OLD_PID=$(cat "$PID_FILE")
                if ps -p $OLD_PID > /dev/null 2>&1; then
                    print_info "Port forwarding already running (PID: $OLD_PID)"
                else
                    rm -f "$PID_FILE"
                fi
            fi
            
            # Start port forwarding if not running
            if [ ! -f "$PID_FILE" ] || ! ps -p $(cat "$PID_FILE") > /dev/null 2>&1; then
                print_info "Starting port forwarding in background..."
                debug_log "Starting SSM port forwarding:"
                debug_log "  Target: $BASTION_ID"
                debug_log "  Remote Host: $DB_ENDPOINT"
                debug_log "  Remote Port: $DB_PORT"
                debug_log "  Local Port: $LOCAL_PORT"
                debug_log "  Log File: $LOG_FILE"
                
                # Verify Session Manager plugin is available before starting
                if ! command_exists session-manager-plugin; then
                    print_error "Session Manager plugin is not available!"
                    print_info "Please install it first:"
                    echo "  macOS: brew install --cask session-manager-plugin"
                    echo "  Or download from: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
                    exit 1
                fi
                
                # Start SSM port forwarding in background
                print_info "Starting SSM port forwarding session..."
                # Build the actual command to run (aws_cmd is a function, so we need to expand it for nohup)
                if [ "$AWS_VAULT_ENABLED" == "true" ] && [ ! -z "$AWS_VAULT_PROFILE" ]; then
                    # Use aws-vault
                    SSM_CMD="aws-vault exec $AWS_VAULT_PROFILE -- aws ssm start-session --target $BASTION_ID --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{\"host\":[\"$DB_ENDPOINT\"],\"portNumber\":[\"$DB_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}'"
                else
                    # Use regular aws command, export environment variables for the subshell
                    export AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION AWS_DEFAULT_REGION
                    SSM_CMD="aws ssm start-session --target $BASTION_ID --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{\"host\":[\"$DB_ENDPOINT\"],\"portNumber\":[\"$DB_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}'"
                fi
                
                nohup bash -c "$SSM_CMD" > "$LOG_FILE" 2>&1 &
                
                SSM_PID=$!
                debug_log "SSM session started with PID: $SSM_PID"
                echo $SSM_PID > "$PID_FILE"
                
                # Wait a moment for the session to establish
                print_info "Waiting for port forwarding to establish..."
                sleep 3
                
                # Check if process is still running
                if ! ps -p $SSM_PID > /dev/null 2>&1; then
                    # Process exited, check the log file for errors
                    print_error "Failed to start port forwarding. Checking log file..."
                    echo ""
                    
                    if [ -f "$LOG_FILE" ]; then
                        LOG_CONTENT=$(cat "$LOG_FILE" 2>/dev/null)
                        if [ ! -z "$LOG_CONTENT" ]; then
                            echo "Error details from log file:"
                            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                            echo "$LOG_CONTENT"
                            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                            echo ""
                            
                            # Check for common error patterns
                            if echo "$LOG_CONTENT" | grep -qi "session-manager-plugin.*not found\|command not found"; then
                                print_error "Session Manager plugin is not installed or not in PATH!"
                                print_info "Please install it:"
                                echo "  macOS: brew install --cask session-manager-plugin"
                                echo "  Or download from: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
                            elif echo "$LOG_CONTENT" | grep -qi "AccessDenied\|UnauthorizedOperation"; then
                                print_error "Missing permission: ssm:StartSession"
                                print_info "Please contact your AWS administrator to grant this permission."
                            elif echo "$LOG_CONTENT" | grep -qi "TargetNotConnected\|InvalidInstanceId"; then
                                print_error "Bastion host is not accessible via SSM."
                                print_info "Make sure the bastion host has the SSM agent running and the IAM role attached."
                            else
                                print_error "Unknown error. Please check the log file: $LOG_FILE"
                            fi
                        else
                            print_error "Log file is empty. The process may have exited immediately."
                            print_info "This usually means:"
                            echo "  1. Session Manager plugin is not installed or not in PATH"
                            echo "  2. Missing permission: ssm:StartSession"
                            echo "  3. Bastion host is not accessible via SSM"
                        fi
                    else
                        print_error "Log file not found. The process may have exited immediately."
                    fi
                    
                    echo ""
                    print_error "Please check the log file for details: $LOG_FILE"
                    rm -f "$PID_FILE"
                    exit 1
                fi
                
                # Check if port is actually listening
                if ! lsof -Pi :$LOCAL_PORT -sTCP:LISTEN > /dev/null 2>&1; then
                    print_warning "Port forwarding process is running but port $LOCAL_PORT is not listening yet."
                    print_info "This may take a few more seconds. Waiting..."
                    sleep 5
                    
                    if ! lsof -Pi :$LOCAL_PORT -sTCP:LISTEN > /dev/null 2>&1; then
                        print_error "Port $LOCAL_PORT is still not listening. Check log: $LOG_FILE"
                        debug_log "Last 20 lines of log file:"
                        tail -20 "$LOG_FILE" 2>/dev/null | while read line; do
                            debug_log "  $line"
                        done
                        kill $SSM_PID 2>/dev/null || true
                        rm -f "$PID_FILE"
                        exit 1
                    fi
                fi
                
                print_success "Port forwarding established on localhost:$LOCAL_PORT"
            fi
            
            CONNECT_HOST_STR="127.0.0.1"
        else
            print_info "RDS is publicly accessible. No port forwarding needed."
            CONNECT_HOST_STR="$DB_ENDPOINT"
            LOCAL_PORT=$DB_PORT
        fi
        
        echo ""
        echo "=========================================="
        echo "  Connection Settings"
        echo "=========================================="
        echo ""
        echo "Copy and paste these settings into your IDE or database tool:"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Host:     $CONNECT_HOST_STR"
        echo "Port:     $LOCAL_PORT"
        echo "Database: $DB_NAME"
        echo "Username: $DB_USERNAME"
        echo "Password: $DB_PASSWORD"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        # Connection strings
        if [ "$DB_ENGINE" == "mysql" ] || [ "$DB_ENGINE" == "mariadb" ]; then
            echo "Connection String (URI):"
            echo "  mysql://$DB_USERNAME:$DB_PASSWORD@$CONNECT_HOST_STR:$LOCAL_PORT/$DB_NAME"
            echo ""
            echo "JDBC URL:"
            echo "  jdbc:mysql://$CONNECT_HOST_STR:$LOCAL_PORT/$DB_NAME"
            echo ""
            echo "MySQL Command Line:"
            echo "  mysql -h $CONNECT_HOST_STR -P $LOCAL_PORT -u $DB_USERNAME -p$DB_PASSWORD $DB_NAME"
        elif [ "$DB_ENGINE" == "postgres" ]; then
            echo "Connection String (URI):"
            echo "  postgresql://$DB_USERNAME:$DB_PASSWORD@$CONNECT_HOST_STR:$LOCAL_PORT/$DB_NAME"
            echo ""
            echo "JDBC URL:"
            echo "  jdbc:postgresql://$CONNECT_HOST_STR:$LOCAL_PORT/$DB_NAME"
            echo ""
            echo "PostgreSQL Command Line:"
            echo "  export PGPASSWORD='$DB_PASSWORD'"
            echo "  psql -h $CONNECT_HOST_STR -p $LOCAL_PORT -U $DB_USERNAME -d $DB_NAME"
        fi
        
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        if [ "$USE_BASTION" == "true" ]; then
            echo "Port Forwarding Status:"
            echo "  Running (PID: $(cat $PID_FILE))"
            echo "  Local Port: $LOCAL_PORT → Remote: $DB_ENDPOINT:$DB_PORT"
            echo ""
            echo "To stop port forwarding:"
            echo "  kill \$(cat $PID_FILE)"
            echo "  rm $PID_FILE"
            echo ""
        fi
        
        print_info "Connection settings displayed above. Copy and paste into your IDE or database tool."
        echo ""
        ;;
        
    *)
        print_error "Invalid option!"
        exit 1
        ;;
esac

