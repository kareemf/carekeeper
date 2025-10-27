#!/bin/bash
# Serve MkDocs documentation locally for preview

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting CareKeeper documentation server...${NC}\n"

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is required but not installed.${NC}"
    echo "Install Python: https://www.python.org/downloads/"
    exit 1
fi

# Check if mkdocs is installed
if ! command -v mkdocs &> /dev/null; then
    echo -e "${YELLOW}MkDocs not found. Installing dependencies...${NC}"
    pip3 install -r requirements.txt
    echo -e "${GREEN}Dependencies installed.${NC}\n"
fi

# Start the development server
echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                    ║${NC}"
echo -e "${BLUE}║  ${GREEN}Documentation server starting...${BLUE}                ║${NC}"
echo -e "${BLUE}║                                                    ║${NC}"
echo -e "${BLUE}║  ${YELLOW}Local:${NC}   http://127.0.0.1:8000                    ${BLUE}║${NC}"
echo -e "${BLUE}║  ${YELLOW}Network:${NC} http://<your-ip>:8000                    ${BLUE}║${NC}"
echo -e "${BLUE}║                                                    ║${NC}"
echo -e "${BLUE}║  Press ${RED}Ctrl+C${BLUE} to stop                             ║${NC}"
echo -e "${BLUE}║                                                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Run MkDocs dev server with live reload
mkdocs serve
