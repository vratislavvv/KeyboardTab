# KeyboardTab

A macOS menu-bar app that replaces the system keyboard-layout switcher with a look-alike panel that shows a country flag next to each layout.

- Works with the shortcuts you already use (⌃Space, ⌃⌥Space, 🌐 Globe key), and you can add your own.
- Flags are picked automatically, e.g. *Slovak – QWERTY* → 🇸🇰, *British* → 🇬🇧, *Finnish* → 🇫🇮.

Requires macOS 14 (Sonoma) or newer, on Apple Silicon or Intel.

---

## Installation

### 1. Install Apple's command-line tools (one time)

KeyboardTab is built from source on your Mac. You don't need Xcode, only Apple's free command-line tools. Open **Terminal** (Applications → Utilities → Terminal) and run:

```sh
xcode-select --install
```

Click **Install** in the window that appears and wait for it to finish. If it says the tools are already installed, you can skip this step.

### 2. Download and build

In Terminal:

```sh
git clone https://github.com/vratislavvv/KeyboardTab.git
cd KeyboardTab
./build.sh --install
```

This builds the app, copies it to your **Applications** folder and starts it. It takes about a minute.

### 3. Start it

The install step starts KeyboardTab for you. Later you can start it from Launchpad, Spotlight or the Applications folder, like any other app. KeyboardTab has no Dock icon. It lives in the menu bar as the flag of your current layout.

### 4. Give it Accessibility access

The first time it starts, macOS asks for permission. KeyboardTab needs it to notice your switching shortcuts.

1. Click **Open System Settings** in the prompt, or go to *System Settings → Privacy & Security → Accessibility*.
2. Turn on **KeyboardTab**. If it isn't listed, click **+** and pick it from Applications.
3. Wait a couple of seconds. The ⚠️ next to the menu-bar flag disappears once it's working, and KeyboardTab's panel replaces the macOS one from then on.

### 5. Check the settings

The **Settings** window opens by itself the first time. Check that the shortcuts you use are listed (see [Settings](#settings)), and turn on **Launch at login** if you want KeyboardTab to start with your Mac.

---

## Using KeyboardTab

### Switching layouts

**With ⌃Space (or any shortcut that includes ⌃, ⌥ or ⌘), AltTab-style:**

1. Hold **⌃** and press **Space**: the panel appears with the next layout selected.
2. Keep holding **⌃** and press **Space** again to move further down the list. Add **⇧** to move back up, or use the arrow keys.
3. Release **⌃** to switch to the selected layout. Press **Esc** instead to cancel.

**With the 🌐 Globe key (or an F-key):**

- Each quick tap switches to the next layout straight away. The panel shows where you are and fades out on its own.
- Holding 🌐 or using it together with another key (🌐+arrow, 🌐+F, …) does **not** switch layouts, so dictation apps and fn shortcuts keep working.

**From the menu bar:** click the flag and pick a layout.

### Opening Settings

Click the menu-bar flag → **Settings…** (or press ⌘, while the menu is open). Opening KeyboardTab again from Launchpad or Spotlight while it's running also opens Settings.

---

## Settings

### Shortcuts that switch the keyboard

- **Filled in automatically.** Shortcuts already set up in macOS appear with a **macOS** label. These are *System Settings → Keyboard → Keyboard Shortcuts → Input Sources* (normally ⌃Space and ⌃⌥Space) and the 🌐 key when *"Press 🌐 key to"* is *Change Input Source*. The list updates within a couple of seconds when you change those settings.
- **⊖ Remove.** Removing a **macOS** shortcut hands it back to macOS, which then shows its usual switcher for it. It stays listed in grey with a **⊕** to take it back. Removing a shortcut you added deletes it.
- **Add Shortcut…** Click it, then press the key combination you want (Esc cancels). It must include ⌃, ⌥ or ⌘, or be an F-key, so normal typing is never blocked.
- **Add 🌐 Globe Key.** Lets the Globe/fn key switch layouts even if macOS isn't set up for it.
- **Reset.** Goes back to exactly the shortcuts macOS has, removing the ones you added.

### General

- **Launch at login.** Starts KeyboardTab automatically when you log in.
- **Accessibility status.** Shows whether access is granted, with a button to the right page in System Settings.

### What KeyboardTab changes on your Mac

- **macOS input-source shortcuts.** While KeyboardTab runs, it temporarily switches off the ones it handles, so the macOS switcher doesn't appear as well. It doesn't change System Settings for this, and they work as before as soon as KeyboardTab quits.
- **🌐 key setting.** While KeyboardTab runs and 🌐 is in its list, it sets *System Settings → Keyboard → "Press 🌐 key to"* to **Do Nothing**. It puts the previous value back when you quit KeyboardTab or remove 🌐 from the list. If you changed the setting yourself in the meantime, your choice is kept.

---

## Updating

```sh
cd KeyboardTab
git pull
./build.sh --install
```

After an update, macOS treats KeyboardTab as a new app. `./build.sh --install` clears the old Accessibility approval and starts the app, so macOS asks once more. Allow it, as in step 4.

## Uninstalling

1. Click the menu-bar flag → **Quit KeyboardTab**. Quitting normally restores your macOS shortcut and 🌐 key settings.
2. If you turned on **Launch at login**, turn it off first in Settings, or later in *System Settings → General → Login Items*.
3. Delete **KeyboardTab** from the Applications folder.
4. Optionally, remove it from *System Settings → Privacy & Security → Accessibility*, and delete its settings with `defaults delete local.keyboardtab`.

---

## Troubleshooting

**The shortcuts do nothing, or the old macOS panel (without flags) appears.**
KeyboardTab doesn't have Accessibility access. A ⚠️ next to the menu-bar flag means the same. Turn it on in *System Settings → Privacy & Security → Accessibility*. If KeyboardTab is already listed and on, remove it with **−**, then quit and reopen KeyboardTab and allow it again. This is always needed after rebuilding or updating.

**Two panels appear on top of each other.**
macOS is still reacting to the shortcut too. Make sure Accessibility access is granted, because KeyboardTab only takes shortcuts over once it has access. For 🌐, check that *System Settings → Keyboard → "Press 🌐 key to"* shows **Do Nothing** while KeyboardTab runs.

**After quitting or a crash, 🌐 no longer switches layouts.**
If KeyboardTab was force-quit or crashed, the 🌐 key may still be on "Do Nothing". Start KeyboardTab and quit it normally, or set *"Press 🌐 key to"* back to *Change Input Source* in *System Settings → Keyboard*.

**macOS says the app "can't be opened" after copying it from another Mac.**
The app isn't notarized by Apple, which is why building it on each Mac (as above) is recommended. To open a copied app anyway, right-click it → **Open**, or run `xattr -dr com.apple.quarantine /Applications/KeyboardTab.app`.

**A layout shows ⌨️ instead of a flag.**
KeyboardTab couldn't tell which country the layout belongs to. Flags come from the table in `Sources/InputSources.swift`, and additions are welcome.

---

## Building without installing

`./build.sh` (without `--install`) only builds `build/KeyboardTab.app` inside the project folder.
