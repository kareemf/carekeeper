#!/bin/bash
# Helper script to capture screenshots from iOS Simulator for documentation

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}CareKeeper Screenshot Capture Helper${NC}\n"

# Configuration
SCREENSHOTS_DIR="docs/images/screenshots"
DATE=$(date +"%Y%m%d_%H%M%S")
DEFAULT_DEVICE="17 pro w/ watch"

# Create screenshots directory if it doesn't exist
mkdir -p "$SCREENSHOTS_DIR"

echo -e "${BLUE}This script helps you capture screenshots from the iOS Simulator.${NC}\n"

# Function to check if simulator is running
check_simulator() {
    local booted_simulators=$(xcrun simctl list devices | grep -c "Booted" || true)
    if [ "$booted_simulators" -eq 0 ]; then
        echo -e "${RED}Error: No simulator is running.${NC}"
        echo -e "Please:"
        echo -e "  1. Open Xcode"
        echo -e "  2. Run CareKeeper (Cmd+R)"
        echo -e "  3. Wait for simulator to boot"
        echo -e "  4. Re-run this script"
        exit 1
    fi
}

# Function to get booted simulator ID
get_booted_simulator() {
    xcrun simctl list devices | grep "Booted" | head -n 1 | sed -E 's/.*\(([^)]+)\).*/\1/'
}

# Function to capture screenshot
capture_screenshot() {
    local name="$1"
    local description="$2"
    local simulator_id=$(get_booted_simulator)

    if [ -z "$simulator_id" ]; then
        echo -e "${RED}Error: Could not find booted simulator${NC}"
        return 1
    fi

    local filename="${name// /-}_${DATE}.png"
    local filepath="$SCREENSHOTS_DIR/$filename"

    echo -e "${YELLOW}Capturing: ${NC}$description"
    echo -e "${BLUE}Filename:  ${NC}$filename"

    # Capture screenshot
    xcrun simctl io "$simulator_id" screenshot "$filepath"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Saved to: $filepath${NC}\n"
        return 0
    else
        echo -e "${RED}✗ Failed to capture screenshot${NC}\n"
        return 1
    fi
}

# Check simulator is running
check_simulator

# Get simulator info
SIMULATOR_ID=$(get_booted_simulator)
SIMULATOR_NAME=$(xcrun simctl list devices | grep "$SIMULATOR_ID" | sed -E 's/([^(]+).*/\1/' | xargs)

echo -e "${GREEN}Found booted simulator:${NC} $SIMULATOR_NAME"
echo -e "${GREEN}Simulator ID:${NC} $SIMULATOR_ID"
echo -e "${GREEN}Screenshots will be saved to:${NC} $SCREENSHOTS_DIR\n"

# Interactive mode
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}           Screenshot Capture Mode${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}\n"

echo "Instructions:"
echo "1. Navigate to the screen you want to capture in the simulator"
echo "2. Press Enter in this terminal to capture"
echo "3. Enter a description when prompted"
echo "4. Type 'done' when finished"
echo ""

screenshot_count=0

while true; do
    echo -ne "${YELLOW}Press Enter to capture (or type 'done' to finish): ${NC}"
    read -r input

    if [ "$input" = "done" ] || [ "$input" = "exit" ] || [ "$input" = "quit" ]; then
        break
    fi

    echo -ne "${YELLOW}Screenshot description: ${NC}"
    read -r description

    if [ -z "$description" ]; then
        description="screenshot_$screenshot_count"
    fi

    # Sanitize filename from description
    safe_name=$(echo "$description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')

    if capture_screenshot "$safe_name" "$description"; then
        ((screenshot_count++))
    fi
done

# Summary
echo -e "\n${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}           Capture Complete${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}\n"

echo -e "Captured: ${GREEN}$screenshot_count${NC} screenshot(s)"
echo -e "Location: ${GREEN}$SCREENSHOTS_DIR${NC}\n"

if [ $screenshot_count -gt 0 ]; then
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Review screenshots in $SCREENSHOTS_DIR"
    echo "2. Rename files for clarity (optional)"
    echo "3. Optimize images (use ImageOptim or similar)"
    echo "4. Replace [SCREENSHOT: ...] placeholders in docs/:"
    echo ""
    echo "   ${YELLOW}[SCREENSHOT: App Store listing]${NC}"
    echo "   ↓"
    echo "   ${GREEN}![App Store listing](../images/screenshots/app-store-listing.png)${NC}"
    echo ""
    echo "5. Commit and push:"
    echo "   ${BLUE}git add docs/images/screenshots/${NC}"
    echo "   ${BLUE}git commit -m \"docs: Add screenshots\"${NC}"
    echo "   ${BLUE}git push${NC}"
fi

echo ""
echo -e "${GREEN}Happy documenting! 📸${NC}"
