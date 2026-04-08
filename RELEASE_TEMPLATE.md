# Release Template / Checklist

Use this template when publishing a new version of UsageTool to GitHub Releases.

## GitHub Release Title
`vX.Y.Z - [Short descriptive summary of the release]`
*(e.g., `v1.0.2 - Fix Claude Code CLI parser update`)*

## Release Notes Body

```markdown
### What's New
- [Briefly list new features, e.g., Added support for Provider X]
- [Keep it user-focused and concise]

### Fixes & Improvements
- [List bug fixes, e.g., Fixed an issue where Codex quotas displayed incorrectly]
- [Mention upstream CLI adaptations, e.g., Updated Claude parser to support new CLI v2 format]

### Notes / Known Issues
- [Mention any ongoing limitations or prerequisites if they changed]
- *Reminder: UsageTool relies on local CLI state. If a provider's CLI updates and breaks tracking, please open an issue!*

---

### Installation
1. Download `UsageTool.zip` below.
2. Unzip and drag `UsageTool.app` to your Applications folder.
3. Open the app (it lives in your menu bar).

*(Requires macOS 14.0+)*

### Support ☕️
If this utility makes your workflow easier, consider supporting its maintenance.
[Sponsor on GitHub](https://github.com/sponsors/pavelalbawork) | [Tip via Ko-fi](https://ko-fi.com/pavelalba)
```

## Publishing Checklist

- [ ] Ensure no hardcoded secrets or PII logging exist in the shipped source.
- [ ] Verify `UsageTool.app` has the correct version and build numbers set.
- [ ] Verify the build is signed and notarized for macOS.
- [ ] Zip the `UsageTool.app` into `UsageTool.zip`.
- [ ] Attach `UsageTool.zip` to the GitHub Release.
- [ ] Publish Release.
