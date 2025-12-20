# swiftui navigation

**Total: 61 results** found in 4 sources

## 1. Apple Documentation (20) 📚 `--source apple-docs`

### 1.1 SwiftUI | Apple Developer Documentation
Framework SwiftUI

Declare the user interface and behavior for your app on every platform.iOS 13.0+iPadOS 13.0+Mac Catalyst 13.0+macOS 10.15+tvOS 13.0+visionOS 1.0+watchOS 6.0+ [Overview](/documentation/swiftui#Overview)

SwiftUI provides views, controls, and layout structures for declaring your app’s user interface. The framework provides event handlers for delivering taps, gestures, and other types of input to your app, and tools to manage the flow of data from your app’s models down to the views and controls that users see and interact with.

Define your app structure using the [`App`](/documentation/swiftui/app) protocol, and populate it with scenes that contain the views that make up your app’s user interface. Create your own custom views that conform to the [`View`](/documentation/sw...
- **URI:** `apple-docs://swiftui/documentation_swiftui`
- **Availability:** iOS 13.0+, macOS 10.15+, tvOS 13.0+, watchOS 6.0+, visionOS 1.0+

### 1.2 SwiftUI updates
**Article**

Learn about important changes to SwiftUI.

Overview

Browse notable changes in [doc://com.apple.documentation/documentation/SwiftUI].

June 2025

General

- Apply Liquid Glass effects to views using [doc://com.apple.documentation/documentation/SwiftUI/View/glassEffect(_:in:)].

- Use [doc://com.apple.documentation/documentation/SwiftUI/Primitive buttonstyle/glass] with the [doc://com.apple.documentation/documentation/SwiftUI/View/ buttonstyle(_:)-66fbx] modifier to apply Liquid Glass to instances of `Button`.

- [doc://com.apple.documentation/documentation/SwiftUI/Tool barspacer] creates a visual break between items in tool bars containing Liquid Glass.

- Use [doc://com.apple.documentation/documentation/SwiftUI/View/scrollEdgeEffectStyle(_:for:)] to configure the scroll edge ...
- **URI:** `apple-docs://updates/documentation_updates_swiftui`
- **Availability:** iOS 26.0+, macOS 26.0+, tvOS 26.0+, watchOS 26.0+, visionOS 26.0+

### 1.3 NavigationControlGroupStyle
The navigation control group style.

struct NavigationControlGroupStyle

Overview

You can also use [doc://com.apple.SwiftUI/documentation/SwiftUI/ControlGroupStyle/navigation] to construct this style.
- **URI:** `apple-docs://swiftui/documentation_swiftui_navigationcontrolgroupstyle`
- **Availability:** iOS 15.0+, macOS 12.0+, visionOS 1.0+

### 1.4 NavigationBarItem
A configuration for a navigation bar that represents a view at the top of a navigation stack.

struct NavigationBarItem

Overview

Use one of the [doc://com.apple.SwiftUI/documentation/SwiftUI/NavigationBarItem/TitleDisplayMode] values to configure a navigation bar title’s display mode with the [doc://com.apple.SwiftUI/documentation/SwiftUI/View/navigationBarTitleDisplayMode(_:)] view modifier.
- **URI:** `apple-docs://swiftui/documentation_swiftui_navigationbaritem`
- **Availability:** iOS 13.0+, tvOS 13.0+, watchOS 6.0+, visionOS 1.0+

### 1.5 NavigationView
A view for presenting a stack of views that represents a visible path in a navigation hierarchy.

struct NavigationView<Content> where Content : View

Overview

Use a `NavigationView` to create a navigation-based app in which the user can traverse a collection of views. Users navigate to a destination view by selecting a [doc://com.apple.SwiftUI/documentation/SwiftUI/NavigationLink] that you provide. On iPadOS and macOS, the destination content appears in the next column. Other platforms push a new view onto the stack, and enable removing items from the stack with platform-specific controls, like a Back button or a swipe gesture.

Use the [doc://com.apple.SwiftUI/documentation/SwiftUI/NavigationView/init(content:)] initializer to create a navigation view that directly associates navigation...
- **URI:** `apple-docs://swiftui/documentation_swiftui_navigationview`
- **Availability:** iOS 13.0+, macOS 10.15+, tvOS 13.0+, watchOS 7.0+, visionOS 1.0+

### 1.6 DoubleColumnNavigation viewstyle
A navigation view style represented by a primary view stack that navigates to a detail view.
- **URI:** `apple-docs://swiftui/documentation_swiftui_doublecolumnnavigationviewstyle`
- **Availability:** iOS 13.0+, macOS 10.15+, tvOS 13.0+, visionOS 1.0+

### 1.7 NavigationLinkPickerStyle
A picker style represented by a navigation link that presents the options by pushing a List-style picker view.

struct NavigationLinkPickerStyle

Overview

In navigation stacks, prefer the default [doc://com.apple.SwiftUI/documentation/SwiftUI/PickerStyle/menu] style. Consider the navigation link style when you have a large number of options or your design is better expressed by pushing onto a stack.

You can also use [doc://com.apple.SwiftUI/documentation/SwiftUI/PickerStyle/navigationLink] to construct this style.
- **URI:** `apple-docs://swiftui/documentation_swiftui_navigationlinkpickerstyle`
- **Availability:** iOS 16.0+, tvOS 16.0+, watchOS 9.0+, visionOS 1.0+

### 1.8 NavigationLink
A view that controls a navigation presentation.

struct NavigationLink<Label, Destination> where Label : View, Destination : View

Overview

People click or tap a navigation link to present a view inside a [doc://com.apple.SwiftUI/documentation/SwiftUI/NavigationStack] or [doc://com.apple.SwiftUI/documentation/SwiftUI/NavigationSplitView]. You control the visual appearance of the link by providing view content in the link’s `label` closure. For example, you can use a [doc://com.apple.SwiftUI/documentation/SwiftUI/Label] to display a link:

For a link composed only of text, you can use one of the convenience initializers that takes a string and creates a [doc://com.apple.SwiftUI/documentation/SwiftUI/Text] view for you:

Link to a destination view

You can perform navigation by initializing...
- **URI:** `apple-docs://swiftui/documentation_swiftui_navigationlink`
- **Availability:** iOS 13.0+, macOS 10.15+, tvOS 13.0+, watchOS 6.0+, visionOS 1.0+

### 1.9 SwiftUI apps
Build your app for all Apple platforms using the Swift programming language and a modern approach.

[doc://com.apple.documentation/documentation/SwiftUI] is the best choice for creating new apps, the preferred choice for visionOS apps, and required for watchOS apps. Its declarative programming model and approach to interface construction makes it easier to create and maintain your app’s interface on multiple platforms simultaneously.

Assemble your app’s core content

When someone launches your app, your app needs to initialize itself, prepare its interface, check in with the system, begin its main event loop, and start handling events as quickly as possible. When you build your app using SwiftUI, you initialize your app’s custom data and SwiftUI handles the rest.

The main entry point for...
- **URI:** `apple-docs://technologyoverviews/documentation_technologyoverviews_swiftui`
- **Availability:** iOS 18.0+, macOS 15.0+, tvOS 18.0+, watchOS 8.0+, visionOS 2.0+

### 1.10 DefaultNavigation viewstyle
The default navigation view style.

struct DefaultNavigation viewstyle

Overview

Use [doc://com.apple.SwiftUI/documentation/SwiftUI/Navigation viewstyle/automatic] to construct this style.
- **URI:** `apple-docs://swiftui/documentation_swiftui_defaultnavigationviewstyle`
- **Availability:** iOS 13.0+, macOS 10.15+, tvOS 13.0+, watchOS 7.0+, visionOS 1.0+

### 1.11 NavigationSplit viewstyleConfiguration
The properties of a navigation split view instance.
- **URI:** `apple-docs://swiftui/documentation_swiftui_navigationsplitviewstyleconfiguration`
- **Availability:** iOS 16.0+, macOS 13.0+, tvOS 16.0+, watchOS 9.0+, visionOS 1.0+

### 1.12 NavigationSplitViewColumn
A view that represents a column in a navigation split view.

struct NavigationSplitViewColumn

Overview

A [doc://com.apple.SwiftUI/documentation/SwiftUI/NavigationSplitView] collapses into a single stack in some contexts, like on iPhone or Apple Watch. Use this type with the `preferredCompactColumn` parameter to control which column of the navigation split view appears on top of the collapsed stack.
- **URI:** `apple-docs://swiftui/documentation_swiftui_navigationsplitviewcolumn`
- **Availability:** iOS 17.0+, macOS 14.0+, tvOS 17.0+, watchOS 10.0+, visionOS 1.0+

### 1.13 Navigation viewstyle
A specification for the appearance and interaction of a navigation view.
- **URI:** `apple-docs://swiftui/documentation_swiftui_navigationviewstyle`
- **Availability:** iOS 13.0+, macOS 10.15+, tvOS 13.0+, watchOS 7.0+, visionOS 1.0+

### 1.14 NavigationStack
A view that displays a root view and enables you to present additional views over the root view.

@MainActor @preconcurrency struct NavigationStack<Data, Root> where Root : View

Overview

Use a navigation stack to present a stack of views over a root view. People can add views to the top of the stack by clicking or tapping a [doc://com.apple.SwiftUI/documentation/SwiftUI/NavigationLink], and remove views using built-in, platform-appropriate controls, like a Back button or a swipe gesture. The stack always displays the most recently added view that hasn’t been removed, and doesn’t allow the root view to be removed.

To create navigation links, associate a view with a data type by adding a [doc://com.apple.SwiftUI/documentation/SwiftUI/View/navigationDestination(for:destination:)] modifier ...
- **URI:** `apple-docs://swiftui/documentation_swiftui_navigationstack`
- **Availability:** iOS 16.0+, macOS 13.0+, tvOS 16.0+, watchOS 9.0+, visionOS 1.0+

### 1.15 NavigationTransition
A type that defines the transition to use when navigating to a view.
- **URI:** `apple-docs://swiftui/documentation_swiftui_navigationtransition`
- **Availability:** iOS 18.0+, macOS 15.0+, tvOS 18.0+, watchOS 11.0+, visionOS 2.0+

### 1.16 ColumnNavigation viewstyle
A navigation view style represented by a series of views in columns.

struct ColumnNavigation viewstyle

Overview

Use [doc://com.apple.SwiftUI/documentation/SwiftUI/Navigation viewstyle/columns] to construct this style.
- **URI:** `apple-docs://swiftui/documentation_swiftui_columnnavigationviewstyle`
- **Availability:** iOS 15.0+, macOS 12.0+, visionOS 1.0+

### 1.17 NavigationSplitViewVisibility
The visibility of the leading columns in a navigation split view.

struct NavigationSplitViewVisibility

Overview

Use a value of this type to control the visibility of the columns of a [doc://com.apple.SwiftUI/documentation/SwiftUI/NavigationSplitView]. Create a [doc://com.apple.SwiftUI/documentation/SwiftUI/State] property with a value of this type, and pass a [doc://com.apple.SwiftUI/documentation/SwiftUI/Binding] to that state to the [doc://com.apple.SwiftUI/documentation/SwiftUI/NavigationSplitView/init(columnVisibility:sidebar:detail:)] or [doc://com.apple.SwiftUI/documentation/SwiftUI/NavigationSplitView/init(columnVisibility:sidebar:content:detail:)] initializer when you create the navigation split view.
- **URI:** `apple-docs://swiftui/documentation_swiftui_navigationsplitviewvisibility`
- **Availability:** iOS 16.0+, macOS 13.0+, tvOS 16.0+, watchOS 9.0+, visionOS 1.0+

### 1.18 AutomaticNavigationSplit viewstyle
A navigation split style that resolves its appearance automatically based on the current context.

@MainActor @preconcurrency struct AutomaticNavigationSplit viewstyle

Overview

Use [doc://com.apple.SwiftUI/documentation/SwiftUI/NavigationSplit viewstyle/automatic] to construct this style.
- **URI:** `apple-docs://swiftui/documentation_swiftui_automaticnavigationsplitviewstyle`
- **Availability:** iOS 16.0+, macOS 13.0+, tvOS 16.0+, watchOS 9.0+, visionOS 1.0+

### 1.19 StackNavigation viewstyle
A navigation view style represented by a view stack that only shows a single top view at a time.

struct StackNavigation viewstyle

Overview

Use [doc://com.apple.SwiftUI/documentation/SwiftUI/Navigation viewstyle/stack] to construct this style.
- **URI:** `apple-docs://swiftui/documentation_swiftui_stacknavigationviewstyle`
- **Availability:** iOS 13.0+, tvOS 13.0+, watchOS 7.0+, visionOS 1.0+

### 1.20 ProminentDetailNavigationSplit viewstyle
A navigation split style that attempts to maintain the size of the detail content when hiding or showing the leading columns.

@MainActor @preconcurrency struct ProminentDetailNavigationSplit viewstyle

Overview

Use [doc://com.apple.SwiftUI/documentation/SwiftUI/NavigationSplit viewstyle/prominentDetail] to construct this style.
- **URI:** `apple-docs://swiftui/documentation_swiftui_prominentdetailnavigationsplitviewstyle`
- **Availability:** iOS 16.0+, macOS 13.0+, tvOS 16.0+, watchOS 9.0+, visionOS 1.0+

## 2. Sample Code (20) 📦 `--source samples`

### 2.1 Bringing robust navigation structure to your SwiftUI app
Use navigation links, stacks, destinations, and paths to provide a streamlined experience for all platforms, as well as behaviors such as deep linking and state restoration.
- **ID:** `swiftui-bringing-robust-navigation-structure-to-your-swiftui-app`

### 2.2 Enhancing your app’s content with tab navigation
Keep your app content front and center while providing quick access to navigation using the tab bar.
- **ID:** `swiftui-enhancing-your-app-content-with-tab-navigation`

### 2.3 Customizing window styles and state-restoration behavior in macOS
Configure how your app’s windows look and function in macOS to provide an engaging and more coherent experience.
- **ID:** `swiftui-customizing-window-styles-and-state-restoration-behavior-in-macos`

### 2.4 Enhancing the accessibility of your SwiftUI app
Support advancements in SwiftUI accessibility to make your app accessible to everyone.
- **ID:** `accessibility-enhancing-the-accessibility-of-your-swiftui-app`

### 2.5 Destination Video
Leverage SwiftUI to build an immersive media experience in a multiplatform app.
- **ID:** `visionos-destination-video`

### 2.6 Updating your app and widgets for watchOS 10
Integrate SwiftUI elements and watch-specific features, and build widgets for the Smart Stack.
- **ID:** `watchos-apps-updating-your-app-and-widgets-for-watchos-10`

### 2.7 Enabling video reflections in an immersive environment
Create a more immersive experience by adding video reflections in a custom environment.
- **ID:** `visionos-enabling-video-reflections-in-an-immersive-environment`

### 2.8 Building an immersive media viewing experience
Add a deeper level of immersion to media playback in your app with RealityKit and Reality Composer Pro.
- **ID:** `visionos-building-an-immersive-media-viewing-experience`

### 2.9 Food Truck: Building a SwiftUI multiplatform app
Create a single codebase and app target for Mac, iPad, and iPhone.
- **ID:** `swiftui-food-truck-building-a-swiftui-multiplatform-app`

### 2.10 Fruta: Building a feature-rich app with SwiftUI
Create a shared codebase to build a multiplatform app that offers widgets and an App Clip.
- **ID:** `appclip-fruta-building-a-feature-rich-app-with-swiftui`

### 2.11 Restoring your app’s state with SwiftUI
Provide app continuity for users by preserving their current activities.
- **ID:** `swiftui-restoring-your-app-s-state-with-swiftui`

### 2.12 Interacting with nearby points of interest
Provide automatic search completions for a partial search query, search the map for relevant locations nearby, and retrieve details for selected points of interest.
- **ID:** `mapkit-interacting-with-nearby-points-of-interest`

### 2.13 Communicating between a DriverKit extension and a client app
Send and receive different kinds of data securely by validating inputs and asynchronously by storing and using a callback.
- **ID:** `driverkit-communicating-between-a-driverkit-extension-and-a-client-app`

### 2.14 Updating an App to Use Swift Concurrency
Improve your app’s performance by refactoring your code to take advantage of asynchronous functions in Swift.
- **ID:** `swift-updating_an_app_to_use_swift_concurrency`

### 2.15 Highlighting app features with TipKit
Bring attention to new features in your app by using tips.
- **ID:** `tipkit-highlightingappfeatureswithtipkit`

### 2.16 Developing a browser app that uses an alternative browser engine
Create a web browser app and associated extensions.
- **ID:** `browserenginekit-developing-a-browser-app-that-uses-an-alternative-browser-engine`

### 2.17 Connecting a network driver
Create an Ethernet driver that interfaces with the system’s network protocol stack.
- **ID:** `pcidriverkit-connecting_a_network_driver`

### 2.18 Accelerating app interactions with App Intents
Enable people to use your app’s features quickly through Siri, Spotlight, and Shortcuts.
- **ID:** `appintents-acceleratingappinteractionswithappintents`

### 2.19 Creating real-time games
Develop games where multiple players interact in real time.
- **ID:** `gamekit-creating-real-time-games`

### 2.20 Creating and updating a complication’s timeline
Create complications that batch-load a timeline of future entries and run periodic background sessions to update the timeline.
- **ID:** `clockkit-creating-and-updating-a-complication-s-timeline`

## 3. Human Interface Guidelines (20) 🎨 `--source hig`

### 3.1 Tab bars
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Tab bars

A tab bar lets people navigate between top-level sections of your app.

Tab bars help people understand the different types of information or functionality that an app provides. They also let people quickly switch between sections of the view while preserving the current navigation state within each section.

[Best practices](/design/human-interface-guidelines/tab- bars#Best-practices)

**Use a tab bar to support navigation, not to provide actions.** A tab bar lets people navigate among different sections of an app, like the Alarm, Stopwatch, and Timer tabs in the Clock app. If you need to provide controls that act on elements in the current view, use a [toolbar](/design/human-interface-guidelines/tool...
- **URI:** `hig://general/tabbars-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.2 Side bars
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Side bars

A sidebar appears on the leading side of a view and lets people navigate between sections in your app or game.

A sidebar floats above content without being anchored to the edges of the view. It provides a broad, flat view of an app’s information hierarchy, giving people access to several peer content areas or modes at the same time.

A sidebar requires a large amount of vertical and horizontal space. When space is limited or you want to devote more of the screen to other information or functionality, a more compact control such as a [tab bar](/design/human-interface-guidelines/tab- bars) may provide a better navigation experience. For guidance, see [Layout](/design/human-interface-guidelines/layout)....
- **URI:** `hig://general/sidebars-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.3 Split views
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Split views

A split view manages the presentation of multiple adjacent panes of content, each of which can contain a variety of components, including tables, collections, images, and custom views.

Typically, you use a split view to show multiple levels of your app’s hierarchy at once and support navigation between them. In this scenario, selecting an item in the view’s primary pane displays the item’s contents in the secondary pane. Similarly, a split view can display a tertiary pane if items in the secondary pane contain additional content.

It’s common to use a split view to display a [sidebar](/design/human-interface-guidelines/side bars) for navigation, where the leading pane lists the top-level items or c...
- **URI:** `hig://general/splitviews-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.4 Voice over
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

voice over

voice over is a screen reader that lets people experience your app’s interface without needing to see the screen.

By supporting voice over, you help people who are blind or have low vision access information in your app and navigate its interface and content when they can’t see the display.

voice over is supported in apps and games built for Apple platforms. It’s also supported in apps and games developed in Unity using [Apple’s Unity plug-ins](https://github.com/apple/unityplugins). For related guidance, see [Accessibility](/design/human-interface-guidelines/accessibility).

[Descriptions](/design/human-interface-guidelines/voice over#Descriptions)

You inform voice over about your app’s content b...
- **URI:** `hig://general/voiceover-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.5 Disclosure controls
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Disclosure controls

Disclosure controls reveal and hide information and functionality related to specific controls or views.

[Best practices](/design/human-interface-guidelines/disclosure- controls#Best-practices)

**Use a disclosure control to hide details until they’re relevant.** Place controls that people are most likely to use at the top of the disclosure hierarchy so they’re always visible, with more advanced functionality hidden by default. This organization helps people quickly find the most essential information without overwhelming them with too many detailed options.

[Disclosure triangles](/design/human-interface-guidelines/disclosure- controls#Disclosure-triangles)

A disclosure triangle shows and...
- **URI:** `hig://general/disclosurecontrols-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.6 Tool bars
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Tool bars

A toolbar provides convenient access to frequently used commands, controls, navigation, and search.

A toolbar consists of one or more sets of controls arranged horizontally along the top or bottom edge of the view, grouped into logical sections.

Tool bars act on content in the view, facilitate navigation, and help orient people in the app. They include three types of content:

The title of the current view

Navigation controls, like back and forward, and [search fields](/design/human-interface-guidelines/search- fields)

Actions, or bar items, like [ buttons](/design/human-interface-guidelines/ buttons) and [menus](/design/human-interface-guidelines/menus)

In contrast to a toolbar, a [tab bar](/des...
- **URI:** `hig://general/toolbars-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.7 Materials
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Materials

A material is a visual effect that creates a sense of depth, layering, and hierarchy between foreground and background elements.

Materials help visually separate foreground elements, such as text and controls, from background elements, such as content and solid colors. By allowing color to pass through from background to foreground, a material establishes visual hierarchy to help people more easily retain a sense of place.

Apple platforms feature two types of materials: Liquid Glass, and standard materials. [Liquid Glass](/design/human-interface-guidelines/materials#Liquid-Glass) is a dynamic material that unifies the design language across Apple platforms, allowing you to present controls and navig...
- **URI:** `hig://general/materials-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.8 Lists and tables
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Lists and tables

Lists and tables present data in one or more columns of rows.

A table or list can represent data that’s organized in groups or hierarchies, and it can support user interactions like selecting, adding, deleting, and reordering. Apps and games in all platforms can use tables to present content and options; many apps use lists to express an overall information hierarchy and help people navigate it. For example, iOS Settings uses a hierarchy of lists to help people choose options, and several apps — such as Mail in iPadOS and macOS — use a table within a [split view](https://developer.apple.com/design/human-interface-guidelines/split- views).

Sometimes, people need to work with complex data in a ...
- **URI:** `hig://general/listsandtables-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.9 Search fields
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Search fields

A search field lets people search a collection of content for specific terms they enter.

A search field is an editable text field that displays a Search icon, a Clear button, and placeholder text where people can enter what they are searching for. Search fields can use a [scope control](/design/human-interface-guidelines/search- fields#Scope- controls-and-tokens) as well as [tokens](/design/human-interface-guidelines/search- fields#Scope- controls-and-tokens) to help filter and refine the scope of their search. Across each platform, there are different patterns for accessing search based on the goals and design of your app.

For developer guidance, see [Adding a search interface to your app](/doc...
- **URI:** `hig://general/searchfields-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.10 Page controls
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Page controls

A page control displays a row of indicator images, each of which represents a page in a flat list.

The scrolling row of indicators helps people navigate the list to find the page they want. Page controls can handle an arbitrary number of pages, making them particularly useful in situations where people can create custom lists.

Page controls appear as a series of small indicator dots by default, representing the available pages. A solid dot denotes the current page. Visually, these dots are always equidistant, and are clipped if there are too many to fit in the window.

[Best practices](/design/human-interface-guidelines/page- controls#Best-practices)

**Use page controls to represent movement be...
- **URI:** `hig://general/pagecontrols-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.11 Page controls
> **Category:** Components

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Page controls

A page control displays a row of indicator images, each of which represents a page in a flat list.

The scrolling row of indicators helps people navigate the list to find the page they want. Page controls can handle an arbitrary number of pages, making them particularly useful in situations where people can create custom lists.

Page controls appear as a series of small indicator dots by default, representing the available pages. A solid dot denotes the current page. Visually, these dots are always equidistant, and are clipped if there are too many to fit in the window.

[Best practices](/design/human-interface-guidelines/page- controls#Best-practices)

**Use page controls to represent movement...
- **URI:** `hig://components/pagecontrols-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.12 Going full screen
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Going full screen

iPhone, iPad, and Mac offer full-screen modes that let people expand a window to fill the screen, hiding system controls and providing a distraction-free environment.

Apple TV and Apple Watch don’t offer full-screen modes because apps and games already fill the screen by default. Apple Vision Pro doesn’t offer a full-screen mode because people can expand a window to fill more of their view or use the Digital Crown to hide passthrough and transition to a more immersive experience (for guidance, see [Immersive experiences](/design/human-interface-guidelines/immersive-experiences)).

[Best practices](/design/human-interface-guidelines/going-full-screen#Best-practices)

**Support full-screen mode...
- **URI:** `hig://general/goingfullscreen-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.13 Outline views
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Outline views

An outline view presents hierarchical data in a scrolling list of cells that are organized into columns and rows.

An outline view includes at least one column that contains primary hierarchical data, such as a set of parent containers and their children. You can add columns, as needed, to display attributes that supplement the primary data; for example, sizes and modification dates. Parent containers have disclosure triangles that expand to reveal their children.

Finder windows offer an outline view for navigating the file system.

[Best practices](/design/human-interface-guidelines/outline- views#Best-practices)

Outline views work well to display text-based content and often appear in the lead...
- **URI:** `hig://general/outlineviews-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.14 Pickers
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Pickers

A picker displays one or more scrollable lists of distinct values that people can choose from.

The system provides several styles of pickers, each of which offers different types of selectable values and has a different appearance. The exact values shown in a picker, and their order, depend on the device language.

Pickers help people enter information by letting them choose single or multipart values. Date pickers specifically offer additional ways to choose values, like selecting a day in a calendar view or entering dates and times using a numeric keypad.

[Best practices](/design/human-interface-guidelines/pickers#Best-practices)

**Consider using a picker to offer medium-to-long lists of items.** I...
- **URI:** `hig://general/pickers-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.15 Windows
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Windows

A window presents UI views and components in your app or game.

In iPadOS, macOS, and visionOS, windows help define the visual boundaries of app content and separate it from other areas of the system, and enable multitasking workflows both within and between apps. Windows include system-provided interface elements such as frames and window controls that let people open, close, resize, and relocate them.

Conceptually, apps use two types of windows to display content:

A *primary* window presents the main navigation and content of an app, and actions associated with them.

An *auxiliary* window presents a specific task or area in an app. Dedicated to one experience, an auxiliary window doesn’t allow navi...
- **URI:** `hig://general/windows-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.16 Segmented controls
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Segmented controls

A segmented control is a linear set of two or more segments, each of which functions as a button.

Within a segmented control, all segments are usually equal in width. Like buttons, segments can contain text or images. Segments can also have text labels beneath them (or beneath the control as a whole).

[Best practices](/design/human-interface-guidelines/segmented- controls#Best-practices)

A segmented control can offer a single choice or multiple choices. For example, in Keynote people can select only one segment in the alignment options control to align selected text. In contrast, people can choose multiple segments in the font attributes control to combine styles like bold, italics, and un...
- **URI:** `hig://general/segmentedcontrols-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.17 Scroll views
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Scroll views

A scroll view lets people view content that’s larger than the view’s boundaries by moving the content vertically or horizontally.

The scroll view itself has no appearance, but it can display a translucent *scroll indicator* that typically appears after people begin scrolling the view’s content. Although the appearance and behavior of scroll indicators can vary per platform, all indicators provide visual feedback about the scrolling action. For example, in iOS, iPadOS, macOS, visionOS, and watchOS, the indicator shows whether the currently visible content is near the beginning, middle, or end of the view.

[Best practices](/design/human-interface-guidelines/scroll- views#Best-practices)

**Support ...
- **URI:** `hig://general/scrollviews-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.18 Color
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Color

Judicious use of color can enhance communication, evoke your brand, provide visual continuity, communicate status and feedback, and help people understand information.

The system defines colors that look good on various backgrounds and appearance modes, and can automatically adapt to vibrancy and accessibility settings. Using system colors is a convenient way to make your experience feel at home on the device.

You may also want to use custom colors to enhance the visual experience of your app or game and express its unique personality. The following guidelines can help you use color in ways that people appreciate, regardless of whether you use system-defined or custom colors.

[Best practices](/design/h...
- **URI:** `hig://general/color-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.19 Keyboards
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Keyboards

A physical keyboard can be an essential input device for entering text, playing games, controlling apps, and more.

People can connect a physical keyboard to any device except Apple Watch. Mac users tend to use a physical keyboard all the time and iPad users often do. Many games work well with a physical keyboard, and people can prefer using one instead of a [virtual keyboard](/design/human-interface-guidelines/virtual-keyboards) when entering a lot of text.

Keyboard users often appreciate using keyboard shortcuts to speed up their interactions with apps and games. A *keyboard shortcut* is a combination of a primary key and one or more modifier keys (Control, Option, Shift, and Command) that map to a...
- **URI:** `hig://general/keyboards-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

### 3.20 Pop-up buttons
> **Category:** General

> **Platforms:** iOS, macOS, watchOS, visionOS, tvOS

Pop-up buttons

A pop-up button displays a menu of mutually exclusive options.

After people choose an item from a pop-up button’s menu, the menu closes, and the button can update its content to indicate the current selection.

[Best practices](/design/human-interface-guidelines/pop-up- buttons#Best-practices)

**Use a pop-up button to present a flat list of mutually exclusive options or states.** A pop-up button helps people make a choice that affects their content or the surrounding view. Use a [pull-down button](https://developer.apple.com/design/human-interface-guidelines/pull-down- buttons) instead if you need to:

Offer a list of actions

Let people select multiple items

Include a submenu

**Provide a use...
- **URI:** `hig://general/pop-upbuttons-appledeveloperdocumentation`
- **Availability:** iOS 2.0+, macOS 10.0+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+

## 4. Swift Evolution (1) 🔄 `--source swift-evolution`

### 4.1 Swift Snippets
* Proposal: [SE-0356](0356-swift-snippets.md)

* Authors: [Ashley Garland](https://github.com/bitjammer)

* Review Manager: [Tom Doron](https://github.com/tomerd)

* Status: **Implemented (Swift 5.7)**

* Implementation:

Available in [recent nightly](https://swift.org/download/#snapshots) snapshots. Requires `--enable-experimental-snippet-support` feature flag when using the [Swift DocC Plugin](https://github.com/apple/swift-docc-plugin). Related pull requests:

* Swift DocC

* [Add snippet support](https://github.com/apple/swift-docc/pull/61)

* Swift Package Manager:

* [Introduce the snippet target type](https://github.com/apple/swift-package-manager/pull/3694)

* [Rename _main symbol when linking snippets](https://github.com/apple/swift-package-manager/pull/3732)

* SymbolKit:

* [Add...
- **URI:** `swift-evolution://SE-0356`
- **Availability:** iOS 16.0+, macOS 13.0+

---

**More results available:**
- Apple Documentation: use `source: apple-docs` for more
- Sample Code: use `source: samples` for more
- Human Interface Guidelines: use `source: hig` for more

_To narrow results, use source parameter: apple-docs, samples, hig, apple-archive, swift-evolution, swift-org, swift-book, packages_

🔍 **AST search:** Use `search_symbols`, `search_property_wrappers`, `search_concurrency`, or `search_conformances` for semantic code discovery via AST extraction.

💡 **Tip:** Filter by platform: `min_ios`, `min_macos`, `min_tvos`, `min_watchos`, `min_visionos`

