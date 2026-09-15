#!/bin/bash
# Create a new 2GP package version for AgentGuard SF.
# Reads package name + version from sfdx-project.json so this script and the
# project manifest can't drift apart.

set -euo pipefail

for bin in sf jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "❌ Error: '$bin' is required but not on PATH."; exit 1; }
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_FILE="$ROOT_DIR/sfdx-project.json"

PACKAGE_NAME=$(jq -r '.packageDirectories[0].package' "$PROJECT_FILE")
VERSION_NAME=$(jq -r '.packageDirectories[0].versionName' "$PROJECT_FILE")

echo "🔒 AgentGuard SF - Package Creation"
echo "===================================="
echo "Package: $PACKAGE_NAME ($VERSION_NAME)"
echo ""

# Check if Dev Hub is authenticated
if ! sf org list --json | jq -e '.result.devHubs | length > 0' >/dev/null 2>&1; then
    echo "❌ Error: No Dev Hub org found. Please authenticate:"
    echo "   sf org login web --set-default-dev-hub --alias devhub"
    exit 1
fi

# Get package ID (create if doesn't exist)
PACKAGE_ID=$(sf package list --json | jq -r --arg name "$PACKAGE_NAME" '.result[] | select(.Name==$name) | .Id' 2>/dev/null || echo "")

if [ -z "$PACKAGE_ID" ]; then
    echo "📦 Creating new package..."
    PACKAGE_ID=$(sf package create \
        --name "$PACKAGE_NAME" \
        --description "Apex security firewall between AI agents and Salesforce data" \
        --package-type Unlocked \
        --path force-app \
        --json | jq -r '.result.Id')

    echo "✅ Package created: $PACKAGE_ID"

    # Keep sfdx-project.json in sync instead of asking for a manual paste.
    jq --arg name "$PACKAGE_NAME" --arg id "$PACKAGE_ID" \
        '.packageAliases[$name] = $id' "$PROJECT_FILE" > "$PROJECT_FILE.tmp"
    mv "$PROJECT_FILE.tmp" "$PROJECT_FILE"
    echo "✅ sfdx-project.json packageAliases updated"
    echo ""
else
    echo "✅ Package exists: $PACKAGE_ID"
fi

# Create package version
echo ""
echo "📦 Creating package version ($VERSION_NAME)..."
echo ""

VERSION_JSON=$(sf package version create \
    --package "$PACKAGE_NAME" \
    --installation-key-bypass \
    --code-coverage \
    --wait 30 \
    --json)

echo "$VERSION_JSON"

VERSION_ID=$(echo "$VERSION_JSON" | jq -r '.result.SubscriberPackageVersionId // empty')

echo ""
echo "✅ Package version created successfully!"
echo ""
echo "Next steps:"
if [ -n "$VERSION_ID" ]; then
    echo "1. Test installation: sf package install --package $VERSION_ID --target-org testorg"
    echo "2. Promote when ready: sf package version promote --package $VERSION_ID"
else
    echo "1. Get the package version ID from the JSON output above"
    echo "2. Test installation: sf package install --package 04t... --target-org testorg"
    echo "3. Promote when ready: sf package version promote --package 04t..."
fi
