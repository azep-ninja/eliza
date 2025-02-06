#!/bin/bash

# Store current branch name
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# List of packages we want to keep/update
PACKAGES=(
    "adapter-sqlite"
    "client-auto"
    "client-direct"
    "client-discord"
    "client-farcaster"
    "client-telegram"
    "client-telegram-account"
    "client-twitter"
    "client-twitter-qi"
    "core"
    "plugin-bootstrap"
    "plugin-di"
    "plugin-gitbook"
    "plugin-goat"
    "plugin-image-generation"
    "plugin-lit"
    "plugin-news"
    "plugin-node"
    "plugin-quick-intel"
    "plugin-tee"
    "plugin-tee-log"
    "plugin-tee-marlin"
    "plugin-twitter"
    "plugin-video-generation"
    "plugin-web-search"
    "plugin-tee-verifiable-log"
    "plugin-open-weather"
    "plugin-imgflip"
    "plugin-sgx"
)

# Ensure we're on the right branch
if [ "$CURRENT_BRANCH" != "base-qi-aaas" ]; then
    echo "Switching to base-qi-aaas branch..."
    git checkout base-qi-aaas
fi

# Save current special files
echo "Backing up special files..."
cp agent/src/index.ts agent/src/index.ts.backup
cp agent/package.json agent/package.json.backup
cp Dockerfile Dockerfile.backup

# Save current dependencies
echo "Backing up current dependencies..."
CURRENT_DEPS=$(jq '.dependencies' agent/package.json)

# Fetch the latest changes from develop
echo "Fetching latest changes from develop branch..."
git fetch origin develop

# Remove existing temp branch if it exists
git branch -D temp-merge-branch 2>/dev/null || true

# Create a new temporary branch from our current clean branch
echo "Creating temporary merge branch from base-qi-aaas..."
git checkout -b temp-merge-branch

# First, get all root-level files from develop
echo "Checking out root-level files from develop..."
git checkout origin/develop -- .

# Restore our version of index.ts
echo "Restoring our version of index.ts..."
cp agent/src/index.ts.backup agent/src/index.ts

# Handle package.json specially
echo "Handling package.json merge..."
jq --argjson deps "$CURRENT_DEPS" '. * {"dependencies": $deps}' agent/package.json > agent/package.json.tmp && mv agent/package.json.tmp agent/package.json

# Restore our version of Dockerfile
echo "Restoring our version of Dockerfile..."
cp Dockerfile.backup Dockerfile

# Build the checkout command for all wanted packages
CHECKOUT_PATHS=""
for package in "${PACKAGES[@]}"; do
    CHECKOUT_PATHS="$CHECKOUT_PATHS packages/$package"
done

# Selectively checkout only the packages we want from develop
echo "Selectively checking out wanted packages from develop..."
git checkout origin/develop -- $CHECKOUT_PATHS

# Remove any unwanted package directories that might have come in
echo "Cleaning up unwanted packages..."
find packages/* -maxdepth 0 -type d | grep -vE "/($(echo "${PACKAGES[@]}" | tr ' ' '|'))$" | xargs rm -rf

# Stage all changes
git add .

# Check if there are any changes to commit
if git diff --staged --quiet; then
    echo "No changes to commit"
else
    # Commit the changes
    git commit -m "Updated from develop while preserving special files and selected packages"
fi

# Switch back to base branch
git checkout base-qi-aaas

# Merge the temporary branch
echo "Merging changes..."
git merge temp-merge-branch

# Clean up
git branch -D temp-merge-branch
rm agent/src/index.ts.backup
rm agent/package.json.backup
rm Dockerfile.backup

echo "Process complete. Please resolve any remaining conflicts."
echo "Current branch: $(git rev-parse --abbrev-ref HEAD)"