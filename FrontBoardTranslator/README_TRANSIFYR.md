# Transifyr FrontBoard Shell

This folder is a FrontBoardAppLauncher-based TrollStore IPA shell for Transifyr subtitles.

What this build does now:

- Uses the upstream FrontBoard scene creation path (`UIRootWindowScenePresentationBinder`, `FBSceneManager`, `FBSMutableSceneDefinition`).
- Signs with the private FrontBoard/displayable-context style entitlements plus `group.com.vteen.RealtimeTranslator`.
- Renders only the translated subtitle text from the shared app group keys.
- Drops stale subtitle text after 4 seconds, so old sentences do not stick to the screen.

Shared keys read by this shell:

- `broadcast_current_translation`
- `broadcast_current_translation_at`

Build on macOS with Theos:

```sh
make package
```

The Windows workspace does not have Theos or the iOS clang toolchain, so this folder is prepared for build but cannot be packaged locally here.
