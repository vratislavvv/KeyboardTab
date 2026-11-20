# KeyboardTab

A macOS menu-bar app that replaces the system keyboard input-source switcher with a look-alike panel that shows a country flag next to each layout.

## Usage

- Hold **⌃** and tap **Space** to cycle through layouts, release **⌃** to switch (**⇧** goes backwards, **Esc** cancels).
- Optional: use the **🌐 Globe** key (enable it in the menu-bar menu and set *System Settings → Keyboard → Press 🌐 key to → Do Nothing*).
- The menu-bar icon shows the current layout's flag.

## Build

```sh
./build.sh            # builds build/KeyboardTab.app
./build.sh --install  # also copies it to /Applications
```

On first launch, grant Accessibility access in *System Settings → Privacy & Security → Accessibility*. Requires macOS 14+.
