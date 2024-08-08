# Git Workflow: Managing Private and Public Octant Repositories

This document outlines the workflow for managing development between a private repository (for active development) and a public repository (for open-source releases) using Git.

## Configuring Git User Information on a New System

When setting up Git on a new system, it's important to configure your user name and email address. This information is used to identify you as the author of your commits.

### Setting User Name and Email

1. Open a terminal or command prompt.

2. Set your Git username:
   ```
   git config --global user.name "Your Name"
   ```
   Replace "Your Name" with your actual name.

3. Set your Git email address:
   ```
   git config --global user.email "youremail@example.com"
   ```
   Replace "youremail@example.com" with your actual email address.

## Initial Setup

1. Create a new public repository on GitHub, https://github.com/shamsway/octant.
2. In your local private repository, add the public repo as a remote:
   ```
   git remote add release https://github.com/shamsway/octant.git
   ```
3. Create a new branch for the public release version:
   ```
   git checkout -b release
   ```
4. Remove any sensitive or private information from this branch.
5. Commit these changes and push to the public repository:
   ```
   git push release release:main
   ```

"release" `git push release` refers to the remote `release` added in step 2. `release:main` specifies that the local branch named `release` will be pushed to the remote brain named `main`.

## Ongoing Development Workflow

### Working on Private Features

1. Work on your private `main` branch as usual.
2. Commit changes regularly:
   ```
   git commit -m "Description of changes"
   ```

### Updating the Public Repository

When ready to update the public version:

1. Checkout the public branch:
   ```
   git checkout public
   ```
2. Merge changes from your private main branch:
   ```
   git merge main
   ```
3. Review changes to ensure no private information is included.
4. Push to the public repository:
   ```
   git push public public:main
   ```

### Cherry-Picking Specific Changes

To apply specific commits to the public branch:

1. Identify the commit hash you want to apply.
2. Checkout the public branch:
   ```
   git checkout public
   ```
3. Cherry-pick the desired commit:
   ```
   git cherry-pick <commit-hash>
   ```
4. Push to the public repository:
   ```
   git push public public:main
   ```

### Handling Public Contributions

1. Pull changes from the public repository to your public branch:
   ```
   git checkout public
   git pull public main
   ```
2. Review the changes.
3. If approved, merge the public branch into your private main branch:
   ```
   git checkout main
   git merge public
   ```

## Best Practices for Open-Source Management

1. **Documentation**: Maintain a comprehensive README.md, CONTRIBUTING.md, and up-to-date API documentation.
2. **Changelog**: Use a standardized format like Keep a Changelog. Update it with each public release.
3. **Versioning**: Follow Semantic Versioning (SemVer) for your releases.
4. **Issue Management**: Use GitHub issue templates and labels. Respond promptly to issues.
5. **Code Quality**: Implement linting, formatting tools, and maintain high test coverage.
6. **Security**: Set up security scanning tools and maintain a SECURITY.md file.
7. **Community Management**: Create a CODE_OF_CONDUCT.md and be welcoming to contributors.
8. **Licensing**: Include the full MIT license text in a LICENSE file and ensure all source files have appropriate headers.

## Useful Git Commands

- View current branch: `git branch`
- Create and switch to a new branch: `git checkout -b branch-name`
- Switch to an existing branch: `git checkout branch-name`
- View commit history: `git log`
- View changes in a specific commit: `git show <commit-hash>`
- Undo last commit (keeping changes): `git reset HEAD~1`
- Discard all local changes: `git reset --hard`
- View remote repositories: `git remote -v`

Remember to always review changes before pushing to the public repository to ensure you're not accidentally sharing private information.