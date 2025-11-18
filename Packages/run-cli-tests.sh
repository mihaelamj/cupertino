#!/bin/bash
# Cupertino CLI Command Tests Runner
#
# This script runs all CLI command tests for the Cupertino project.
# Tests are organized by command: crawl, index, fetch, and MCP server.

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🧪 Cupertino CLI Command Tests${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if we're in the Packages directory
if [ ! -f "Package.swift" ]; then
    echo -e "${RED}❌ Error: Package.swift not found${NC}"
    echo "   Please run this script from the Packages directory"
    exit 1
fi

# Function to run a specific test
run_test() {
    local test_name="$1"
    echo -e "${YELLOW}▶ Running: $test_name${NC}"
    echo ""

    if swift test --filter "$test_name" 2>&1; then
        echo ""
        echo -e "${GREEN}✅ $test_name PASSED${NC}"
        return 0
    else
        echo ""
        echo -e "${RED}❌ $test_name FAILED${NC}"
        return 1
    fi
}

# Function to run test category
run_category() {
    local category="$1"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}📦 $category${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Track test results
PASSED=0
FAILED=0
TESTS=()

# Parse command line arguments
RUN_ALL=false
RUN_UNIT=false
RUN_INTEGRATION=false
RUN_SLOW=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            RUN_ALL=true
            shift
            ;;
        --unit)
            RUN_UNIT=true
            shift
            ;;
        --integration)
            RUN_INTEGRATION=true
            shift
            ;;
        --slow)
            RUN_SLOW=true
            shift
            ;;
        --help|-h)
            echo "Usage: ./run-cli-tests.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --all          Run all tests (unit + integration + slow)"
            echo "  --unit         Run unit tests only (fast, no network)"
            echo "  --integration  Run integration tests (requires network)"
            echo "  --slow         Run slow tests (full MCP workflow)"
            echo "  --help, -h     Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./run-cli-tests.sh --unit                # Fast unit tests"
            echo "  ./run-cli-tests.sh --integration         # Integration tests"
            echo "  ./run-cli-tests.sh --all                 # Everything"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Default to unit tests if nothing specified
if [ "$RUN_ALL" = false ] && [ "$RUN_UNIT" = false ] && [ "$RUN_INTEGRATION" = false ] && [ "$RUN_SLOW" = false ]; then
    RUN_UNIT=true
fi

# Unit Tests (Fast, no network)
if [ "$RUN_UNIT" = true ] || [ "$RUN_ALL" = true ]; then
    run_category "Unit Tests (Fast)"

    TESTS+=(
        "indexEmptyDirectory"
    )

    for test in "${TESTS[@]}"; do
        if run_test "$test"; then
            ((PASSED++))
        else
            ((FAILED++))
        fi
    done
fi

# Integration Tests (Requires network, uses WKWebView)
if [ "$RUN_INTEGRATION" = true ] || [ "$RUN_ALL" = true ]; then
    run_category "Integration Tests (Network Required)"

    echo -e "${YELLOW}⚠️  Integration tests require:${NC}"
    echo "   • Internet connection"
    echo "   • Access to developer.apple.com"
    echo "   • WKWebView (macOS GUI)"
    echo ""

    INTEGRATION_TESTS=(
        "crawlSinglePage"
        "crawlWithResume"
        "crawlSwiftEvolution"
        "buildSearchIndex"
        "searchWithFrameworkFilter"
        "registerSearchProvider"
        "executeSearchTool"
    )

    for test in "${INTEGRATION_TESTS[@]}"; do
        if run_test "$test"; then
            ((PASSED++))
        else
            ((FAILED++))
        fi
    done
fi

# Slow Tests (Full MCP workflow)
if [ "$RUN_SLOW" = true ] || [ "$RUN_ALL" = true ]; then
    run_category "Slow Tests (Complete Workflows)"

    echo -e "${YELLOW}⚠️  Slow tests may take several minutes${NC}"
    echo ""

    SLOW_TESTS=(
        "completeMCPWorkflow"
    )

    for test in "${SLOW_TESTS[@]}"; do
        if run_test "$test"; then
            ((PASSED++))
        else
            ((FAILED++))
        fi
    done
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}📊 Test Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

TOTAL=$((PASSED + FAILED))

echo -e "   Total Tests: $TOTAL"
echo -e "   ${GREEN}✅ Passed: $PASSED${NC}"

if [ $FAILED -gt 0 ]; then
    echo -e "   ${RED}❌ Failed: $FAILED${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
else
    echo ""
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
fi
