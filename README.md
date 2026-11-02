# ReduxKit

The redux implementation

## Installation

Add this package to your Package.swift as dependency and to your target.

```swift
dependencies: [
    .package(
        url: "https://github.com/amine2233/swift-redux-kit.git",
        from: "1.0.0"
    )
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "ReduxKit", package: "redux-kit"),
        .product(name: "ReduxKitExtensions", package: "redux-kit"),
        .product(name: "ReduxKitUI", package: "redux-kit"),
        .product(name: "ReduxKitTesting", package: "redux-kit")
    ]),
]
```

Import in your code

```swift
import ReduxKit
```

## Inspiration Links

- [0.2.6] <https://github.com/mecid/swift-unidirectional-flow/tree/0.2.6> (using combine)
- [Redux-like state container in SwiftUI. Basics](https://swiftwithmajid.com/2019/09/18/redux-like-state-container-in-swiftui/)
- [Redux-like state container in SwiftUI. Best practices](https://swiftwithmajid.com/2019/09/25/redux-like-state-container-in-swiftui-part2/)
- [Redux-like state container in SwiftUI. Container Views.](https://swiftwithmajid.com/2019/10/02/redux-like-state-container-in-swiftui-part3/)
- [Redux-like state container in SwiftUI. Connectors.](https://swiftwithmajid.com/2021/02/03/redux-like-state-container-in-swiftui-part4/)
- [Redux-like state container in SwiftUI. Swift concurrency model.](https://swiftwithmajid.com/2022/02/17/redux-like-state-container-in-swiftui-part5/)

## Informations

> [!warning]
> :warning: This version of package is just a clone for
> [swift-unidirectional-flow-0.2.6](https://github.com/mecid/swift-unidirectional-flow/tree/0.2.6) to be able to use Combine.
> To use the new framework `Observable` please use the last version of [swift-unidirectional-flow](https://github.com/mecid/swift-unidirectional-flow).

## How to Use This Skill

### Option A: Using skills.sh (recommended)

Install this skill with a single command:

```bash
npx skills add https://github.com/amine2233/swift-redux-kit.git --skill dev-skills
```

To install a specific version:

```bash
npx skills add https://github.com/amine2233/swift-redux-kit.git --skill dev-skills --version 1.0.0
```

Then use the skill in your AI agent, for example:
> Use the dev skills and analyze the current project for dev improvements

### Option B: Claude Code Plugin

#### Personal Usage

To install this Skill for your personal use in Claude Code:

1. Add the marketplace:

   ```bash
   /plugin marketplace add https://github.com/amine2233/swift-redux-kit.git
   ```

2. Install the Skill (latest version):

   ```bash
   /plugin install redux-kit-expert@redux-kit-skill
   ```

   Or install a specific version:

   ```bash
   /plugin install redux-kit-expert@redux-kit-skill --version 2.5.0
   ```

#### Project Configuration

To automatically provide this Skill to everyone working in a repository, configure the repository's `.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "rredux-kit-expert@redux-kit-skill": true
  },
  "extraKnownMarketplaces": {
    "dev-skills": {
      "source": {
        "source": "github",
        "repo": "amine2233/swift-redux-kit.git"
      }
    }
  }
}
```

To pin a specific version in your project configuration:

```json
{
  "enabledPlugins": {
    "redux-kit-expert@redux-kit-skill": "1.0.0"
  },
  "extraKnownMarketplaces": {
    "redux-kit-expert": {
      "source": {
        "source": "github",
        "repo": "amine2233/swift-redux-kit.git",
        "version": "1.0.0"
      }
    }
  }
}
```

When team members open the project, Claude Code will prompt them to install the Skill.

### Option C: Manual install

1) **Clone** this repository.
2) **Install or symlink** the `$HOME/Developer/...` folder
   following your tool’s official skills installation docs (see links below).
3) **Use your AI tool** as usual and ask it to use the “dev-skills” skill for dev skills tasks.

#### Where to Save Skills

Follow your tool’s official documentation, here are a few popular ones:

- **Codex:** [Where to save skills](https://developers.openai.com/codex/skills/#where-to-save-skills)
- **Claude:** [Using Skills](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview#using-skills)
- **Cursor:** [Enabling Skills](https://cursor.com/docs/context/skills#enabling-skills)

**How to verify**:

Your agent should reference the triage/playbook in `redux-kit-expert/SKILL.md` and jump into the relevant reference file for your error or task.

## References

- [Claude Skills](https://github.com/Jeffallan/claude-skills/tree/main)
- [Swift-Concurrency-Agent-Skil](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill)
