# Change Log
All notable changes to this project will be documented in this file.

## [1.1.4](https://github.com/SwiftKickMobile/SwiftMessages/releases/tag/1.1.4)

### Bug Fixes

* Fix #16 Preserve status bar visibility when displaying message in a new window.

## [1.1.3](https://github.com/SwiftKickMobile/SwiftMessages/releases/tag/1.1.3)

### Features

* Add default configuration `SwiftMessages.defaultConfig` that can be used when calling the variants of `show()` that don't take a `config` argument or as a global base for custom configs.
* Add `Array.sm_random()` function that returns a random element from the array. Can be used to create a playful
     message that cycles randomly through a set of emoji icons, for example.

### Bug Fixes

* Fix #5 Emoji not shown!
* Fix #6 There is no way to create SwiftMessages instance as there is no public initializer

## [1.1.2](https://github.com/SwiftKickMobile/SwiftMessages/releases/tag/1.1.2)

### Bug Fixes

* Fix Carthage-related issues.

## [1.1.1](https://github.com/SwiftKickMobile/SwiftMessages/releases/tag/1.1.1)

### Features

* New layout `Layout.TabView` — like `Layout.CardView` with one end attached to the super view.

### Bug Fixes

* Fix spacing between title and body text in `Layout.CardView` when body text wraps.

## [1.1.0](https://github.com/SwiftKickMobile/SwiftMessages/releases/tag/1.1.0)

### Improvements

### API Changes

* The `BaseView.contentView` property of was removed because it no longer had any functionality in the framework.

    This is a minor backwards incompatible change. If you've copied one of the included nib files from a previous release, you may get a key-value coding runtime error related to contentView, in which case you can subclass the view and add a `contentView` property or you can remove the outlet connection in Interface Builder.

## [1.0.3](https://github.com/SwiftKickMobile/SwiftMessages/releases/tag/1.0.2)

### Improvements

* Remove the `iconContainer` property from `MessageView`.

### Bug Fixes

* Fix constraints generated by `BaseView.installContentView()`.

## [1.0.2](https://github.com/SwiftKickMobile/SwiftMessages/releases/tag/1.0.2)

### Features

* Add support for specifying an `IconStyle` in the `MessageView.configureTheme()` convenience function.

## [1.0.1](https://github.com/SwiftKickMobile/SwiftMessages/releases/tag/1.0.1)

* Add code comments.

## [1.0.0](https://github.com/SwiftKickMobile/SwiftMessages/releases/tag/1.0.0)

* Initial release.
