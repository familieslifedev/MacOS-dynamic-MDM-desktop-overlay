# Dynamic Desktop Manager v0.7.2 — Picker interaction fix

The v0.7.1 scroll-height adjustment did not fix the Section and Wallpaper set controls. This patch replaces those two SwiftUI Pickers with explicit buttons and a Menu to avoid picker selection problems in a MenuBarExtra window. Gallery Previous/Next remains unchanged.

## Install
Quit the existing manager. Copy `DynamicDesktopManager.swift` into your repository, then run `bash build-manager.sh` and `open DynamicDesktopManager.app`. The overlay engine is unchanged.

## Test
Switch Wallpaper / Testing / System using the button strip. Choose a different wallpaper collection from the menu. Verify gallery Previous / Next still works and the desktop selection updates.

This source cannot be compiled on Linux; test on macOS before committing.
