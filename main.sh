#!/bin/sh

# Colors setup
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# Determine repo name
REPO="hyuuwu/bunch-of-sh"
if command -v git >/dev/null 2>&1; then
    GIT_URL=$(git config --get remote.origin.url 2>/dev/null)
    if [ -n "$GIT_URL" ]; then
        # Handle git@github.com:owner/repo.git or https://github.com/owner/repo.git
        TEMP_URL=${GIT_URL#*github.com[:/]}
        TEMP_URL=${TEMP_URL%.git}
        if [ -n "$TEMP_URL" ]; then
            REPO="$TEMP_URL"
        fi
    fi
fi

# Temp file for downloading scripts
TEMP_FILE=$(mktemp 2>/dev/null || echo ".temp-script.sh")
cleanup() {
    rm -f "$TEMP_FILE"
}
trap cleanup EXIT INT TERM

read_input() {
    if (exec < /dev/tty) 2>/dev/null; then
        read -r "$1" </dev/tty
    else
        read -r "$1"
    fi
}

# Print beautiful header
print_header() {
    printf "${CYAN}${BOLD}%s${NC}\n" " ____                   _        ___   __   ____  _"
    printf "${CYAN}${BOLD}%s${NC}\n" "| __ ) _   _ _ __   ___| |__    / _ \ / _| / ___|| |_"
    printf "${CYAN}${BOLD}%s${NC}\n" "|  _ \| | | | '_ \ / __| '_ \  | | | | |_  \___ \| '_ \ "
    printf "${CYAN}${BOLD}%s${NC}\n" "| |_) | |_| | | | | (__| | | | | |_| |  _|  ___) | | | |"
    printf "${CYAN}${BOLD}%s${NC}\n" "|____/ \__,_|_| |_|\___|_| |_|  \___/|_|   |____/|_| |_|"
    printf "\n"
    printf "  ${BOLD}Repository:${NC} https://github.com/%s\n" "$REPO"
    printf "  ==================================================\n"
}

# Fetch scripts list
fetch_scripts() {
    printf "  Fetching script list... "
    API_URL="https://api.github.com/repos/${REPO}/contents/"
    RESPONSE=$(curl -sSf "$API_URL" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$RESPONSE" ]; then
        printf "${RED}failed to fetch from GitHub API.${NC}\n"
        printf "  Falling back to local directory scan...\n"
        
        SCRIPTS_LIST=""
        for f in *.sh; do
            if [ -f "$f" ] && [ "$f" != "main.sh" ]; then
                if [ -z "$SCRIPTS_LIST" ]; then
                    SCRIPTS_LIST="$f"
                else
                    SCRIPTS_LIST="$SCRIPTS_LIST"$'\n'"$f"
                fi
            fi
        done
    else
        printf "${GREEN}done.${NC}\n"
        # Parse using jq if available, fallback to grep
        if command -v jq >/dev/null 2>&1; then
            SCRIPTS_LIST=$(echo "$RESPONSE" | jq -r '.[] | select(.type == "file" and (.name | endswith(".sh")) and .name != "main.sh") | .name' 2>/dev/null)
        else
            SCRIPTS_LIST=$(echo "$RESPONSE" | grep -o '"name": "[^"]*\.sh"' | cut -d'"' -f4 | grep -v '^main\.sh$' 2>/dev/null)
        fi
    fi
}

main_menu() {
    while true; do
        clear 2>/dev/null || printf "\033[H\033[2J"
        print_header
        
        if [ -z "$SCRIPTS_LIST" ]; then
            printf "  ${RED}No .sh scripts found in the repository/directory.${NC}\n"
            printf "  Press Enter to exit..."
            read_input _
            exit 1
        fi
        
        printf "  ${BOLD}Select a script to view/execute:${NC}\n\n"
        
        # Count lines
        NUM_SCRIPTS=$(echo "$SCRIPTS_LIST" | wc -l | tr -d ' ')
        
        i=1
        echo "$SCRIPTS_LIST" | while read -r name; do
            if [ -n "$name" ]; then
                printf "   %2d) ${GREEN}%s${NC}\n" "$i" "$name"
                i=$((i+1))
            fi
        done
        
        printf "   %2d) ${RED}Exit${NC}\n\n" "$((NUM_SCRIPTS + 1))"
        printf "  Enter selection [1-%d]: " "$((NUM_SCRIPTS + 1))"
        
        read_input choice
        
        # Validate number
        if ! echo "$choice" | grep -q '^[0-9]\+$'; then
            printf "  ${RED}Invalid input. Press Enter to continue...${NC}\n"
            read_input _
            continue
        fi
        
        if [ "$choice" -eq "$((NUM_SCRIPTS + 1))" ]; then
            printf "  Goodbye!\n"
            exit 0
        fi
        
        if [ "$choice" -lt 1 ] || [ "$choice" -gt "$NUM_SCRIPTS" ]; then
            printf "  ${RED}Selection out of range. Press Enter to continue...${NC}\n"
            read_input _
            continue
        fi
        
        # Get selected script name
        SCRIPT_NAME=$(echo "$SCRIPTS_LIST" | sed -n "${choice}p")
        
        # Download selected script to temp file
        printf "\n  Downloading %s... " "$SCRIPT_NAME"
        
        # Determine source (github vs local fallback)
        if echo "$RESPONSE" | grep -q "\"name\": \"$SCRIPT_NAME\""; then
            # From Github
            # We can use raw.githubusercontent.com
            # First attempt to find the raw download_url from JSON using jq if available
            RAW_URL=""
            if command -v jq >/dev/null 2>&1; then
                RAW_URL=$(echo "$RESPONSE" | jq -r ".[] | select(.name == \"$SCRIPT_NAME\") | .download_url" 2>/dev/null)
            fi
            # If not found or jq wasn't used, construct default raw url
            if [ -z "$RAW_URL" ] || [ "$RAW_URL" = "null" ]; then
                RAW_URL="https://raw.githubusercontent.com/${REPO}/main/${SCRIPT_NAME}"
            fi
            
            curl -sSf "$RAW_URL" > "$TEMP_FILE" 2>/dev/null
        else
            # Local fallback
            if [ -f "$SCRIPT_NAME" ]; then
                cp "$SCRIPT_NAME" "$TEMP_FILE"
            else
                false
            fi
        fi
        
        if [ $? -ne 0 ]; then
            printf "${RED}failed.${NC}\n"
            printf "  Press Enter to continue..."
            read_input _
            continue
        fi
        
        printf "${GREEN}done.${NC}\n"
        
        # Submenu
        while true; do
            clear 2>/dev/null || printf "\033[H\033[2J"
            print_header
            
            printf "  ${BOLD}Selected Script:${NC} ${GREEN}%s${NC}\n" "$SCRIPT_NAME"
            printf "  ${BOLD}Description:${NC}\n"
            # Read first few lines of comments
            DESC=$(grep -E '^#[[:space:]]*' "$TEMP_FILE" | grep -v '^#![[:space:]]*/' | sed 's/^#[[:space:]]*//' | head -n 10)
            if [ -n "$DESC" ]; then
                echo "$DESC" | sed 's/^/    /'
            else
                printf "    No description available.\n"
            fi
            printf "  ==================================================\n\n"
            
            printf "  1) ${GREEN}Run script${NC}\n"
            printf "  2) ${YELLOW}View source code${NC}\n"
            printf "  3) ${BLUE}Download & save locally${NC}\n"
            printf "  4) ${RED}Go back${NC}\n\n"
            printf "  Select action [1-4]: "
            
            read_input action
            
            case "$action" in
                1)
                    clear 2>/dev/null || printf "\033[H\033[2J"
                    printf "${GREEN}--- Running %s ---${NC}\n\n" "$SCRIPT_NAME"
                    # Run script using sh or bash depending on contents/shebang
                    if grep -q '^#!/bin/bash' "$TEMP_FILE"; then
                        if command -v bash >/dev/null 2>&1; then
                            bash "$TEMP_FILE"
                        else
                            sh "$TEMP_FILE"
                        fi
                    else
                        sh "$TEMP_FILE"
                    fi
                    printf "\n${GREEN}--- Finished execution (Exit code: $?) ---${NC}\n"
                    printf "Press Enter to return..."
                    read_input _
                    ;;
                2)
                    clear 2>/dev/null || printf "\033[H\033[2J"
                    printf "${YELLOW}--- Source: %s ---${NC}\n\n" "$SCRIPT_NAME"
                    if [ -t 0 ] && [ -t 1 ] && command -v less >/dev/null 2>&1; then
                        less "$TEMP_FILE"
                    else
                        cat "$TEMP_FILE"
                    fi
                    printf "\n${YELLOW}--- End of Source ---${NC}\n"
                    printf "Press Enter to return..."
                    read_input _
                    ;;
                3)
                    default_dest="./$SCRIPT_NAME"
                    printf "  Enter destination path [default: %s]: " "$default_dest"
                    read_input dest
                    if [ -z "$dest" ]; then
                        dest="$default_dest"
                    fi
                    cp "$TEMP_FILE" "$dest"
                    chmod +x "$dest"
                    printf "  ${GREEN}Script saved to %s and made executable.${NC}\n" "$dest"
                    printf "  Press Enter to return..."
                    read_input _
                    ;;
                4)
                    break
                    ;;
                *)
                    printf "  ${RED}Invalid action. Press Enter to continue...${NC}\n"
                    read_input _
                    ;;
            esac
        done
    done
}

fetch_scripts
main_menu
