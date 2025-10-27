#!/bin/bash
# Build MkDocs documentation site

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building CareKeeper documentation...${NC}\n"

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is required but not installed.${NC}"
    echo "Install Python: https://www.python.org/downloads/"
    exit 1
fi

# Check if pip is installed
if ! command -v pip3 &> /dev/null; then
    echo -e "${RED}Error: pip3 is required but not installed.${NC}"
    echo "Install pip: python3 -m ensurepip --upgrade"
    exit 1
fi

# Check if mkdocs is installed
if ! command -v mkdocs &> /dev/null; then
    echo -e "${YELLOW}MkDocs not found. Installing dependencies...${NC}"
    pip3 install -r requirements.txt
    echo -e "${GREEN}Dependencies installed.${NC}\n"
fi

# Clean previous build
if [ -d "site" ]; then
    echo -e "${YELLOW}Cleaning previous build...${NC}"
    rm -rf site
fi

# Build the documentation
echo -e "${GREEN}Building site...${NC}"
mkdocs build

# Check if build was successful
if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}✓ Documentation built successfully!${NC}"
    echo -e "Output: ${GREEN}site/${NC}"
    echo -e "\nTo preview locally, run:"
    echo -e "  ${YELLOW}./scripts/serve-docs.sh${NC}"
    echo -e "\nTo deploy, upload the ${GREEN}site/${NC} directory to your hosting provider."
else
    echo -e "\n${RED}✗ Build failed.${NC}"
    exit 1
fi
