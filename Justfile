set shell := ["bash", "-euo", "pipefail", "-c"]

# List available recipes.
default:
    @just --list

# Adds a specific skill in the global Claude skill directory
# Note: will overwrite any existing skill with the same name
install skill:
    @just uninstall {{skill}}
    cp -r skills/{{skill}}/ ~/.claude/skills/{{skill}}/

# Removes a specific skill from the global Claude skill directory
uninstall skill:
    rm -rf ~/.claude/skills/{{skill}}
