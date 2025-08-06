#\!/bin/bash

echo "🚀 Pushing ISABELLE to GitHub..."

# Remove old remote if exists
git remote remove origin 2>/dev/null

# Add your GitHub repository as remote
git remote add origin https://github.com/ushamkamaljitsingh/isabelle-gemma3n.git

# Set main branch
git branch -M main

# Push all commits and set upstream
git push -u origin main

echo "✅ Successfully pushed to GitHub\!"
echo "🌐 View your repository at: https://github.com/ushamkamaljitsingh/isabelle-gemma3n"
