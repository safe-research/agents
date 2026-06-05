# Agents

This repository contains a collection of shared skills and `AGENTS.md` snippets for use in the Safe Research projects.

## Usage

Add skills to your collection:

```sh
ln -s skills/$SKILL ~/.claude/skills/$SKILL
```

Snippets can be added into an `AGENTS.md` file.

```sh
(echo; cat snippets/$SNIPPET.md) >> $REPO/AGENTS.md
```
