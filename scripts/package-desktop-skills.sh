#!/bin/bash
#
# Package Claude Code skills for Claude Desktop compatibility
#
# This script:
# 1. Finds all SKILL.md files in plugins/*/skills/
# 2. Strips Claude Code-specific frontmatter fields
# 3. Bundles reference files
# 4. Creates ZIP packages following Desktop's required structure
#
# Usage: ./scripts/package-desktop-skills.sh [--output-dir DIR] [--plugin NAME]
#
# Options:
#   --output-dir DIR   Output directory (default: dist/desktop)
#   --plugin NAME      Process only this plugin (default: all plugins)
#   --dry-run          Show what would be done without creating files
#   --verbose          Show detailed progress

set -euo pipefail

# Default configuration
OUTPUT_DIR="dist/desktop"
PLUGIN_FILTER=""
DRY_RUN=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --plugin)
            PLUGIN_FILTER="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--output-dir DIR] [--plugin NAME] [--dry-run] [--verbose]"
            echo ""
            echo "Package Claude Code skills for Claude Desktop compatibility."
            echo ""
            echo "Options:"
            echo "  --output-dir DIR   Output directory (default: dist/desktop)"
            echo "  --plugin NAME      Process only this plugin (default: all plugins)"
            echo "  --dry-run          Show what would be done without creating files"
            echo "  --verbose          Show detailed progress"
            echo "  -h, --help         Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Claude Code-specific frontmatter fields to strip
# These are not supported in Claude Desktop
CODE_SPECIFIC_FIELDS=(
    "context"
    "agent"
    "hooks"
    "allowed-tools"
    "user-invocable"
    "model"
)

# Function to strip Code-specific frontmatter from SKILL.md
strip_code_specific_frontmatter() {
    local input_file="$1"
    local output_file="$2"

    # Read the file content
    local content
    content=$(cat "$input_file")

    # Check if file starts with frontmatter
    if [[ ! "$content" =~ ^--- ]]; then
        log_warning "No frontmatter found in $input_file, copying as-is"
        echo "$content" > "$output_file"
        return
    fi

    # Extract frontmatter and body
    local frontmatter
    local body

    # Use awk to extract frontmatter (between first and second ---)
    frontmatter=$(awk '/^---$/{p++} p==1{print} p==2{exit}' "$input_file" | tail -n +2)

    # Extract body (everything after second ---)
    body=$(awk '/^---$/{p++} p>=2{if(p==2 && /^---$/){p++;next}; print}' "$input_file")

    # Filter frontmatter to keep only Desktop-compatible fields
    local filtered_frontmatter=""
    while IFS= read -r line; do
        local should_skip=false

        # Check each Code-specific field
        for field in "${CODE_SPECIFIC_FIELDS[@]}"; do
            if [[ "$line" =~ ^${field}: ]] || [[ "$line" =~ ^${field}:$ ]]; then
                should_skip=true
                log_verbose "  Stripping field: $field"
                break
            fi
        done

        if [ "$should_skip" = false ] && [ -n "$line" ]; then
            filtered_frontmatter+="$line"$'\n'
        fi
    done <<< "$frontmatter"

    # Write the Desktop-compatible SKILL.md
    {
        echo "---"
        echo -n "$filtered_frontmatter"
        echo "---"
        echo "$body"
    } > "$output_file"
}

# Function to create a Desktop skill package
create_skill_package() {
    local skill_dir="$1"
    local plugin_name="$2"
    local skill_name
    skill_name=$(basename "$skill_dir")

    log_info "Processing skill: $plugin_name/$skill_name"

    local skill_md="$skill_dir/SKILL.md"

    if [ ! -f "$skill_md" ]; then
        log_warning "No SKILL.md found in $skill_dir, skipping"
        return 1
    fi

    # Create temporary directory for packaging
    local temp_dir
    temp_dir=$(mktemp -d)
    local package_dir="$temp_dir/$skill_name"
    mkdir -p "$package_dir"

    # Strip Code-specific frontmatter and copy SKILL.md
    log_verbose "  Stripping Code-specific frontmatter..."
    if [ "$DRY_RUN" = true ]; then
        log_info "  [DRY RUN] Would create Desktop-compatible SKILL.md"
    else
        strip_code_specific_frontmatter "$skill_md" "$package_dir/SKILL.md"
    fi

    # Copy references directory if it exists
    local references_dir="$skill_dir/references"
    if [ -d "$references_dir" ]; then
        log_verbose "  Bundling references directory..."
        if [ "$DRY_RUN" = true ]; then
            log_info "  [DRY RUN] Would copy references: $(ls "$references_dir" | wc -l | tr -d ' ') files"
        else
            cp -r "$references_dir" "$package_dir/"
        fi
    fi

    # Create output directory
    local output_plugin_dir="$OUTPUT_DIR/$plugin_name"
    if [ "$DRY_RUN" = true ]; then
        log_info "  [DRY RUN] Would create directory: $output_plugin_dir"
    else
        mkdir -p "$output_plugin_dir"
    fi

    # Create ZIP package
    local zip_file="$output_plugin_dir/$skill_name.zip"
    log_verbose "  Creating ZIP package..."

    if [ "$DRY_RUN" = true ]; then
        log_info "  [DRY RUN] Would create: $zip_file"
    else
        # Create ZIP with skill folder at root (Claude Desktop requirement)
        (cd "$temp_dir" && zip -r "$skill_name.zip" "$skill_name" -x "*.DS_Store" > /dev/null)
        mv "$temp_dir/$skill_name.zip" "$zip_file"
        log_success "Created: $zip_file"
    fi

    # Cleanup
    rm -rf "$temp_dir"

    return 0
}

# Main execution
main() {
    log_info "Claude Desktop Skill Packager"
    log_info "=============================="

    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE - No files will be created"
    fi

    # Find plugins directory
    if [ ! -d "plugins" ]; then
        log_error "plugins/ directory not found. Run from repository root."
        exit 1
    fi

    # Track statistics
    local skills_processed=0
    local skills_failed=0
    local packages_created=0

    # Process each plugin
    for plugin_dir in plugins/*/; do
        local plugin_name
        plugin_name=$(basename "$plugin_dir")

        # Skip if filtering by plugin and this isn't the target
        if [ -n "$PLUGIN_FILTER" ] && [ "$plugin_name" != "$PLUGIN_FILTER" ]; then
            continue
        fi

        local skills_dir="$plugin_dir/skills"

        if [ ! -d "$skills_dir" ]; then
            log_verbose "No skills directory in $plugin_name, skipping"
            continue
        fi

        log_info "Processing plugin: $plugin_name"

        # Process each skill in the plugin
        for skill_dir in "$skills_dir"/*/; do
            if [ -d "$skill_dir" ]; then
                skills_processed=$((skills_processed + 1))

                if create_skill_package "$skill_dir" "$plugin_name"; then
                    packages_created=$((packages_created + 1))
                else
                    skills_failed=$((skills_failed + 1))
                fi
            fi
        done
    done

    # Summary
    echo ""
    log_info "=============================="
    log_info "Summary:"
    log_info "  Skills processed: $skills_processed"
    log_info "  Packages created: $packages_created"

    if [ "$skills_failed" -gt 0 ]; then
        log_warning "  Skills failed: $skills_failed"
    fi

    if [ "$DRY_RUN" = false ] && [ "$packages_created" -gt 0 ]; then
        log_success "Desktop skill packages created in: $OUTPUT_DIR/"
        echo ""
        log_info "Package structure (Claude Desktop compatible):"
        log_info "  skill-name.zip"
        log_info "  └── skill-name/"
        log_info "      ├── SKILL.md"
        log_info "      └── references/"
    fi
}

main
