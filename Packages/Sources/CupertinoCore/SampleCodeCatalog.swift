// This file is AUTO-GENERATED from the Apple Sample Code Library
// Last updated: 2025-11-17
// DO NOT EDIT MANUALLY - Update via cupertino-sample-code-updater

// swiftlint:disable file_length line_length type_body_length
// Justification: Auto-generated catalog of 4,900+ Apple sample code entries.
// Contains long URLs and descriptions from Apple's documentation.
// File is generated programmatically and should not be manually edited.
// Splitting would reduce discoverability and complicate updates.

import Foundation

/// Represents a sample code project from Apple
public struct SampleCodeEntry: Codable, Sendable {
    public let title: String
    public let url: String
    public let framework: String
    public let description: String
    public let zipFilename: String
    public let webURL: String

    public init(title: String, url: String, framework: String, description: String, zipFilename: String, webURL: String) {
        self.title = title
        self.url = url
        self.framework = framework
        self.description = description
        self.zipFilename = zipFilename
        self.webURL = webURL
    }
}

/// Complete catalog of all Apple sample code projects
public enum SampleCodeCatalog {
    /// Total number of sample code entries
    public static let count = 606

    /// All sample code entries
    public static let allEntries: [SampleCodeEntry] = [
        SampleCodeEntry(
            title: "Adding realistic reflections to an AR experience",
            url: "/documentation/ARKit/adding-realistic-reflections-to-an-ar-experience",
            framework: "ARKit",
            description: "Use ARKit to generate environment probe textures from camera imagery and render reflective virtual objects.",
            zipFilename: "arkit-adding-realistic-reflections-to-an-ar-experience.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/adding-realistic-reflections-to-an-ar-experience"
        ),
        SampleCodeEntry(
            title: "Capturing Body Motion in 3D",
            url: "/documentation/ARKit/capturing-body-motion-in-3d",
            framework: "ARKit",
            description: "Track a person in the physical environment and visualize their motion by applying the same body movements to a virtual character.",
            zipFilename: "arkit-capturing-body-motion-in-3d.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/capturing-body-motion-in-3d"
        ),
        SampleCodeEntry(
            title: "Combining user face-tracking and world tracking",
            url: "/documentation/ARKit/combining-user-face-tracking-and-world-tracking",
            framework: "ARKit",
            description: "Track the user’s face in an app that displays an AR experience with the rear camera.",
            zipFilename: "arkit-combining-user-face-tracking-and-world-tracking.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/combining-user-face-tracking-and-world-tracking"
        ),
        SampleCodeEntry(
            title: "Creating a collaborative session",
            url: "/documentation/ARKit/creating-a-collaborative-session",
            framework: "ARKit",
            description: "Enable nearby devices to share an AR experience by using a peer-to-peer multiuser strategy.",
            zipFilename: "arkit-creating-a-collaborative-session.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/creating-a-collaborative-session"
        ),
        SampleCodeEntry(
            title: "Creating a fog effect using scene depth",
            url: "/documentation/ARKit/creating-a-fog-effect-using-scene-depth",
            framework: "ARKit",
            description: "Apply virtual fog to the physical environment.",
            zipFilename: "arkit-creating-a-fog-effect-using-scene-depth.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/creating-a-fog-effect-using-scene-depth"
        ),
        SampleCodeEntry(
            title: "Creating a multiuser AR experience",
            url: "/documentation/ARKit/creating-a-multiuser-ar-experience",
            framework: "ARKit",
            description: "Enable nearby devices to share an AR experience by using a host-guest multiuser strategy.",
            zipFilename: "arkit-creating-a-multiuser-ar-experience.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/creating-a-multiuser-ar-experience"
        ),
        SampleCodeEntry(
            title: "Creating an immersive ar experience with audio",
            url: "/documentation/ARKit/creating-an-immersive-ar-experience-with-audio",
            framework: "ARKit",
            description: "Use sound effects and environmental sound layers to create an engaging AR experience.",
            zipFilename: "arkit-creating-an-immersive-ar-experience-with-audio.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/creating-an-immersive-ar-experience-with-audio"
        ),
        SampleCodeEntry(
            title: "Creating screen annotations for objects in an AR experience",
            url: "/documentation/ARKit/creating-screen-annotations-for-objects-in-an-ar-experience",
            framework: "ARKit",
            description: "Annotate an AR experience with virtual sticky notes that you display onscreen over real and virtual objects.",
            zipFilename: "arkit-creating-screen-annotations-for-objects-in-an-ar-experience.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/creating-screen-annotations-for-objects-in-an-ar-experience"
        ),
        SampleCodeEntry(
            title: "Detecting Images in an AR Experience",
            url: "/documentation/ARKit/detecting-images-in-an-ar-experience",
            framework: "ARKit",
            description: "React to known 2D images in the user’s environment, and use their positions to place AR content.",
            zipFilename: "arkit-detecting-images-in-an-ar-experience.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/detecting-images-in-an-ar-experience"
        ),
        SampleCodeEntry(
            title: "Displaying a point cloud using scene depth",
            url: "/documentation/ARKit/displaying-a-point-cloud-using-scene-depth",
            framework: "ARKit",
            description: "Present a visualization of the physical environment by placing points based a scene’s depth data.",
            zipFilename: "arkit-displaying-a-point-cloud-using-scene-depth.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/displaying-a-point-cloud-using-scene-depth"
        ),
        SampleCodeEntry(
            title: "Effecting People Occlusion in Custom Renderers",
            url: "/documentation/ARKit/effecting-people-occlusion-in-custom-renderers",
            framework: "ARKit",
            description: "Occlude your app’s virtual content where ARKit recognizes people in the camera feed by using matte generator.",
            zipFilename: "arkit-effecting-people-occlusion-in-custom-renderers.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/effecting-people-occlusion-in-custom-renderers"
        ),
        SampleCodeEntry(
            title: "Occluding virtual content with people",
            url: "/documentation/ARKit/occluding-virtual-content-with-people",
            framework: "ARKit",
            description: "Cover your app’s virtual content with people that ARKit perceives in the camera feed.",
            zipFilename: "arkit-occluding-virtual-content-with-people.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/occluding-virtual-content-with-people"
        ),
        SampleCodeEntry(
            title: "Placing objects and handling 3D interaction",
            url: "/documentation/ARKit/placing-objects-and-handling-3d-interaction",
            framework: "ARKit",
            description: "Place virtual content at tracked, real-world locations, and enable the user to interact with virtual content by using gestures.",
            zipFilename: "arkit-placing-objects-and-handling-3d-interaction.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/placing-objects-and-handling-3d-interaction"
        ),
        SampleCodeEntry(
            title: "Recognizing and Labeling Arbitrary Objects",
            url: "/documentation/ARKit/recognizing-and-labeling-arbitrary-objects",
            framework: "ARKit",
            description: "Create anchors that track objects you recognize in the camera feed, using a custom optical-recognition algorithm.",
            zipFilename: "arkit-recognizing-and-labeling-arbitrary-objects.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/recognizing-and-labeling-arbitrary-objects"
        ),
        SampleCodeEntry(
            title: "Saving and loading world data",
            url: "/documentation/ARKit/saving-and-loading-world-data",
            framework: "ARKit",
            description: "Serialize a world-tracking session to resume it later on.",
            zipFilename: "arkit-saving-and-loading-world-data.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/saving-and-loading-world-data"
        ),
        SampleCodeEntry(
            title: "Scanning and Detecting 3D Objects",
            url: "/documentation/ARKit/scanning-and-detecting-3d-objects",
            framework: "ARKit",
            description: "Record spatial features of real-world objects, then use the results to find those objects in the user’s environment and trigger AR content.",
            zipFilename: "arkit-scanning-and-detecting-3d-objects.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/scanning-and-detecting-3d-objects"
        ),
        SampleCodeEntry(
            title: "Streaming an AR experience",
            url: "/documentation/ARKit/streaming-an-ar-experience",
            framework: "ARKit",
            description: "Control an AR experience remotely by transferring sensor and user input over the network.",
            zipFilename: "arkit-streaming-an-ar-experience.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/streaming-an-ar-experience"
        ),
        SampleCodeEntry(
            title: "Tracking a handheld accessory as a virtual sculpting tool",
            url: "/documentation/ARKit/tracking-a-handheld-accessory-as-a-virtual-sculpting-tool",
            framework: "ARKit",
            description: "Use a tracked accessory with Apple Vision Pro to create a virtual sculpture.",
            zipFilename: "arkit-tracking-a-handheld-accessory-as-a-virtual-sculpting-tool.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/tracking-a-handheld-accessory-as-a-virtual-sculpting-tool"
        ),
        SampleCodeEntry(
            title: "Tracking accessories in volumetric windows",
            url: "/documentation/ARKit/tracking-accessories-in-volumetric-windows",
            framework: "ARKit",
            description: "Translate the position and velocity of tracked handheld accessories to throw virtual balls at a stack of cans.",
            zipFilename: "arkit-tracking-accessories-in-volumetric-windows.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/tracking-accessories-in-volumetric-windows"
        ),
        SampleCodeEntry(
            title: "Tracking and altering images",
            url: "/documentation/ARKit/tracking-and-altering-images",
            framework: "ARKit",
            description: "Create images from rectangular shapes found in the user’s environment, and augment their appearance.",
            zipFilename: "arkit-tracking-and-altering-images.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/tracking-and-altering-images"
        ),
        SampleCodeEntry(
            title: "Tracking and visualizing faces",
            url: "/documentation/ARKit/tracking-and-visualizing-faces",
            framework: "ARKit",
            description: "Detect faces in a front-camera AR experience, overlay virtual content, and animate facial expressions in real-time.",
            zipFilename: "arkit-tracking-and-visualizing-faces.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/tracking-and-visualizing-faces"
        ),
        SampleCodeEntry(
            title: "Tracking and visualizing planes",
            url: "/documentation/ARKit/tracking-and-visualizing-planes",
            framework: "ARKit",
            description: "Detect surfaces in the physical environment and visualize their shape and location in 3D space.",
            zipFilename: "arkit-tracking-and-visualizing-planes.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/tracking-and-visualizing-planes"
        ),
        SampleCodeEntry(
            title: "Tracking geographic locations in AR",
            url: "/documentation/ARKit/tracking-geographic-locations-in-ar",
            framework: "ARKit",
            description: "Track specific geographic areas of interest and render them in an AR experience.",
            zipFilename: "arkit-tracking-geographic-locations-in-ar.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/tracking-geographic-locations-in-ar"
        ),
        SampleCodeEntry(
            title: "Visualizing and interacting with a reconstructed scene",
            url: "/documentation/ARKit/visualizing-and-interacting-with-a-reconstructed-scene",
            framework: "ARKit",
            description: "Estimate the shape of the physical environment using a polygonal mesh.###",
            zipFilename: "arkit-visualizing-and-interacting-with-a-reconstructed-scene.zip",
            webURL: "https://developer.apple.com/documentation/ARKit/visualizing-and-interacting-with-a-reconstructed-scene"
        ),
        SampleCodeEntry(
            title: "Adding synthesized speech to calls",
            url: "/documentation/AVFAudio/Adding-synthesized-speech-to-calls",
            framework: "AVFAudio",
            description: "Provide a more accessible experience by adding your app’s audio to a call.",
            zipFilename: "avfaudio-adding-synthesized-speech-to-calls.zip",
            webURL: "https://developer.apple.com/documentation/AVFAudio/Adding-synthesized-speech-to-calls"
        ),
        SampleCodeEntry(
            title: "Building a signal generator",
            url: "/documentation/AVFAudio/building-a-signal-generator",
            framework: "AVFAudio",
            description: "Generate audio signals using an audio source node and a custom render callback.",
            zipFilename: "avfaudio-building-a-signal-generator.zip",
            webURL: "https://developer.apple.com/documentation/AVFAudio/building-a-signal-generator"
        ),
        SampleCodeEntry(
            title: "Capturing stereo audio from built-In microphones",
            url: "/documentation/AVFAudio/capturing-stereo-audio-from-built-in-microphones",
            framework: "AVFAudio",
            description: "Configure an iOS device’s built-in microphones to add stereo recording capabilities to your app.",
            zipFilename: "avfaudio-capturing-stereo-audio-from-built-in-microphones.zip",
            webURL: "https://developer.apple.com/documentation/AVFAudio/capturing-stereo-audio-from-built-in-microphones"
        ),
        SampleCodeEntry(
            title: "Creating a custom speech synthesizer",
            url: "/documentation/AVFAudio/creating-a-custom-speech-synthesizer",
            framework: "AVFAudio",
            description: "Use your custom voices to synthesize speech by building a speech synthesis provider.",
            zipFilename: "avfaudio-creating-a-custom-speech-synthesizer.zip",
            webURL: "https://developer.apple.com/documentation/AVFAudio/creating-a-custom-speech-synthesizer"
        ),
        SampleCodeEntry(
            title: "Creating custom audio effects",
            url: "/documentation/AVFAudio/creating-custom-audio-effects",
            framework: "AVFAudio",
            description: "Add custom audio-effect processing to apps like Logic Pro X and GarageBand by creating Audio Unit (AU) plug-ins.",
            zipFilename: "avfaudio-creating-custom-audio-effects.zip",
            webURL: "https://developer.apple.com/documentation/AVFAudio/creating-custom-audio-effects"
        ),
        SampleCodeEntry(
            title: "Performing offline audio processing",
            url: "/documentation/AVFAudio/performing-offline-audio-processing",
            framework: "AVFAudio",
            description: "Add offline audio processing features to your app by enabling offline manual rendering mode.",
            zipFilename: "avfaudio-performing-offline-audio-processing.zip",
            webURL: "https://developer.apple.com/documentation/AVFAudio/performing-offline-audio-processing"
        ),
        SampleCodeEntry(
            title: "Playing custom audio with your own player",
            url: "/documentation/AVFAudio/playing-custom-audio-with-your-own-player",
            framework: "AVFAudio",
            description: "Construct an audio player to play your custom audio data, and optionally take advantage of the advanced features of AirPlay 2.",
            zipFilename: "avfaudio-playing-custom-audio-with-your-own-player.zip",
            webURL: "https://developer.apple.com/documentation/AVFAudio/playing-custom-audio-with-your-own-player"
        ),
        SampleCodeEntry(
            title: "Using voice processing",
            url: "/documentation/AVFAudio/using-voice-processing",
            framework: "AVFAudio",
            description: "Add voice-processing capabilities to your app by using audio engine.###",
            zipFilename: "avfaudio-using-voice-processing.zip",
            webURL: "https://developer.apple.com/documentation/AVFAudio/using-voice-processing"
        ),
        SampleCodeEntry(
            title: "AVCam: Building a camera app",
            url: "/documentation/AVFoundation/avcam-building-a-camera-app",
            framework: "AVFoundation",
            description: "Capture photos and record video using the front and rear iPhone and iPad cameras.",
            zipFilename: "avfoundation-avcam-building-a-camera-app.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/avcam-building-a-camera-app"
        ),
        SampleCodeEntry(
            title: "AVCamBarcode: detecting barcodes and faces",
            url: "/documentation/AVFoundation/avcambarcode-detecting-barcodes-and-faces",
            framework: "AVFoundation",
            description: "Identify machine readable codes or faces by using the camera.",
            zipFilename: "avfoundation-avcambarcode-detecting-barcodes-and-faces.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/avcambarcode-detecting-barcodes-and-faces"
        ),
        SampleCodeEntry(
            title: "AVCamFilter: Applying filters to a capture stream",
            url: "/documentation/AVFoundation/avcamfilter-applying-filters-to-a-capture-stream",
            framework: "AVFoundation",
            description: "Render a capture stream with rose-colored filtering and depth effects.",
            zipFilename: "avfoundation-avcamfilter-applying-filters-to-a-capture-stream.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/avcamfilter-applying-filters-to-a-capture-stream"
        ),
        SampleCodeEntry(
            title: "AVMultiCamPiP: Capturing from Multiple Cameras",
            url: "/documentation/AVFoundation/avmulticampip-capturing-from-multiple-cameras",
            framework: "AVFoundation",
            description: "Simultaneously record the output from the front and back cameras into a single movie file by using a multi-camera capture session.",
            zipFilename: "avfoundation-avmulticampip-capturing-from-multiple-cameras.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/avmulticampip-capturing-from-multiple-cameras"
        ),
        SampleCodeEntry(
            title: "Capturing Cinematic video",
            url: "/documentation/AVFoundation/capturing-cinematic-video",
            framework: "AVFoundation",
            description: "Capture video with an adjustable depth of field and focus points.",
            zipFilename: "avfoundation-capturing-cinematic-video.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/capturing-cinematic-video"
        ),
        SampleCodeEntry(
            title: "Capturing Spatial Audio in your iOS app",
            url: "/documentation/AVFoundation/capturing-spatial-audio-in-your-ios-app",
            framework: "AVFoundation",
            description: "Enhance your app’s audio recording capabilities by supporting Spatial Audio capture.",
            zipFilename: "avfoundation-capturing-spatial-audio-in-your-ios-app.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/capturing-spatial-audio-in-your-ios-app"
        ),
        SampleCodeEntry(
            title: "Capturing consistent color images",
            url: "/documentation/AVFoundation/capturing-consistent-color-images",
            framework: "AVFoundation",
            description: "Add the power of a photography studio and lighting rig to your app with the new Constant Color API.",
            zipFilename: "avfoundation-capturing-consistent-color-images.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/capturing-consistent-color-images"
        ),
        SampleCodeEntry(
            title: "Capturing depth using the LiDAR camera",
            url: "/documentation/AVFoundation/capturing-depth-using-the-lidar-camera",
            framework: "AVFoundation",
            description: "Access the LiDAR camera on supporting devices to capture precise depth data.",
            zipFilename: "avfoundation-capturing-depth-using-the-lidar-camera.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/capturing-depth-using-the-lidar-camera"
        ),
        SampleCodeEntry(
            title: "Converting projected video to Apple Projected Media Profile",
            url: "/documentation/AVFoundation/converting-projected-video-to-apple-projected-media-profile",
            framework: "AVFoundation",
            description: "Convert content with equirectangular or half-equirectangular projection to APMP.",
            zipFilename: "avfoundation-converting-projected-video-to-apple-projected-media-profile.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/converting-projected-video-to-apple-projected-media-profile"
        ),
        SampleCodeEntry(
            title: "Converting side-by-side 3D video to multiview HEVC and spatial video",
            url: "/documentation/AVFoundation/converting-side-by-side-3d-video-to-multiview-hevc-and-spatial-video",
            framework: "AVFoundation",
            description: "Create video content for visionOS by converting an existing 3D HEVC file to a multiview HEVC format, optionally adding spatial metadata to create a spatial video.",
            zipFilename: "avfoundation-converting-side-by-side-3d-video-to-multiview-hevc-and-spatial-video.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/converting-side-by-side-3d-video-to-multiview-hevc-and-spatial-video"
        ),
        SampleCodeEntry(
            title: "Creating a seamless multiview playback experience",
            url: "/documentation/AVFoundation/creating-a-seamless-multiview-playback-experience",
            framework: "AVFoundation",
            description: "Build advanced multiview playback experiences with the AVFoundation and AVRouting frameworks.",
            zipFilename: "avfoundation-creating-a-seamless-multiview-playback-experience.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/creating-a-seamless-multiview-playback-experience"
        ),
        SampleCodeEntry(
            title: "Debugging AVFoundation audio mixes, compositions, and video compositions",
            url: "/documentation/AVFoundation/debugging-avfoundation-audio-mixes-compositions-and-video-compositions",
            framework: "AVFoundation",
            description: "Resolve common problems when creating compositions, video compositions, and audio mixes.",
            zipFilename: "avfoundation-debugging-avfoundation-audio-mixes-compositions-and-video-compositions.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/debugging-avfoundation-audio-mixes-compositions-and-video-compositions"
        ),
        SampleCodeEntry(
            title: "Editing and playing HDR video",
            url: "/documentation/AVFoundation/editing-and-playing-hdr-video",
            framework: "AVFoundation",
            description: "Support high-dynamic-range (HDR) video content in your app by using the HDR editing and playback capabilities of AVFoundation.",
            zipFilename: "avfoundation-editing-and-playing-hdr-video.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/editing-and-playing-hdr-video"
        ),
        SampleCodeEntry(
            title: "Enhancing live video by leveraging TrueDepth camera data",
            url: "/documentation/AVFoundation/enhancing-live-video-by-leveraging-truedepth-camera-data",
            framework: "AVFoundation",
            description: "Apply your own background to a live capture feed streamed from the front-facing TrueDepth camera.",
            zipFilename: "avfoundation-enhancing-live-video-by-leveraging-truedepth-camera-data.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/enhancing-live-video-by-leveraging-truedepth-camera-data"
        ),
        SampleCodeEntry(
            title: "Integrating AirPlay for long-form video apps",
            url: "/documentation/AVFoundation/integrating-airplay-for-long-form-video-apps",
            framework: "AVFoundation",
            description: "Integrate AirPlay features and implement a dedicated external playback experience by preparing the routing system for long-form video playback.",
            zipFilename: "avfoundation-integrating-airplay-for-long-form-video-apps.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/integrating-airplay-for-long-form-video-apps"
        ),
        SampleCodeEntry(
            title: "Processing spatial video with a custom video compositor",
            url: "/documentation/AVFoundation/processing-spatial-video-with-a-custom-video-compositor",
            framework: "AVFoundation",
            description: "Create a custom video compositor to edit spatial video for playback and export.",
            zipFilename: "avfoundation-processing-spatial-video-with-a-custom-video-compositor.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/processing-spatial-video-with-a-custom-video-compositor"
        ),
        SampleCodeEntry(
            title: "Providing an integrated view of your timeline when playing HLS interstitials",
            url: "/documentation/AVFoundation/providing-an-integrated-view-of-your-timeline-when-playing-hls-interstitials",
            framework: "AVFoundation",
            description: "Go beyond simple ad insertion with point and fill occupancy HLS interstitials.",
            zipFilename: "avfoundation-providing-an-integrated-view-of-your-timeline-when-playing-hls-interstitials.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/providing-an-integrated-view-of-your-timeline-when-playing-hls-interstitials"
        ),
        SampleCodeEntry(
            title: "Reading multiview 3D video files",
            url: "/documentation/AVFoundation/reading-multiview-3d-video-files",
            framework: "AVFoundation",
            description: "Render single images for the left eye and right eye from a multiview High Efficiency Video Coding format file by reading individual video frames.",
            zipFilename: "avfoundation-reading-multiview-3d-video-files.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/reading-multiview-3d-video-files"
        ),
        SampleCodeEntry(
            title: "Streaming depth data from the TrueDepth camera",
            url: "/documentation/AVFoundation/streaming-depth-data-from-the-truedepth-camera",
            framework: "AVFoundation",
            description: "Visualize depth data in 2D and 3D from the TrueDepth camera.",
            zipFilename: "avfoundation-streaming-depth-data-from-the-truedepth-camera.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/streaming-depth-data-from-the-truedepth-camera"
        ),
        SampleCodeEntry(
            title: "Supporting Continuity Camera in your macOS app",
            url: "/documentation/AVFoundation/supporting-continuity-camera-in-your-macos-app",
            framework: "AVFoundation",
            description: "Enable high-quality photo and video capture by using an iPhone camera as an external capture device.",
            zipFilename: "avfoundation-supporting-continuity-camera-in-your-macos-app.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/supporting-continuity-camera-in-your-macos-app"
        ),
        SampleCodeEntry(
            title: "Supporting coordinated media playback",
            url: "/documentation/AVFoundation/supporting-coordinated-media-playback",
            framework: "AVFoundation",
            description: "Create synchronized media experiences that enable users to watch and listen across devices.",
            zipFilename: "avfoundation-supporting-coordinated-media-playback.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/supporting-coordinated-media-playback"
        ),
        SampleCodeEntry(
            title: "Supporting remote interactions in tvOS",
            url: "/documentation/AVFoundation/supporting-remote-interactions-in-tvos",
            framework: "AVFoundation",
            description: "Set up your app to support remote commands and events in a variety of scenarios by using the relevant approach.",
            zipFilename: "avfoundation-supporting-remote-interactions-in-tvos.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/supporting-remote-interactions-in-tvos"
        ),
        SampleCodeEntry(
            title: "Using AVFoundation to play and persist HTTP live streams",
            url: "/documentation/AVFoundation/using-avfoundation-to-play-and-persist-http-live-streams",
            framework: "AVFoundation",
            description: "Play HTTP Live Streams and persist streams on disk for offline playback using AVFoundation.",
            zipFilename: "avfoundation-using-avfoundation-to-play-and-persist-http-live-streams.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/using-avfoundation-to-play-and-persist-http-live-streams"
        ),
        SampleCodeEntry(
            title: "Using HEVC video with alpha",
            url: "/documentation/AVFoundation/using-hevc-video-with-alpha",
            framework: "AVFoundation",
            description: "Play, write, and export HEVC video with an alpha channel to add overlay effects to your video processing.",
            zipFilename: "avfoundation-using-hevc-video-with-alpha.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/using-hevc-video-with-alpha"
        ),
        SampleCodeEntry(
            title: "Writing fragmented MPEG-4 files for HTTP Live Streaming",
            url: "/documentation/AVFoundation/writing-fragmented-mpeg-4-files-for-http-live-streaming",
            framework: "AVFoundation",
            description: "Create an HTTP Live Streaming presentation by turning a movie file into a sequence of fragmented MPEG-4 files.###",
            zipFilename: "avfoundation-writing-fragmented-mpeg-4-files-for-http-live-streaming.zip",
            webURL: "https://developer.apple.com/documentation/AVFoundation/writing-fragmented-mpeg-4-files-for-http-live-streaming"
        ),
        SampleCodeEntry(
            title: "Adopting Picture in Picture Playback in tvOS",
            url: "/documentation/AVKit/adopting-picture-in-picture-playback-in-tvos",
            framework: "AVKit",
            description: "Add advanced multitasking capabilities to your video apps by using Picture in Picture playback in tvOS.",
            zipFilename: "avkit-adopting-picture-in-picture-playback-in-tvos.zip",
            webURL: "https://developer.apple.com/documentation/AVKit/adopting-picture-in-picture-playback-in-tvos"
        ),
        SampleCodeEntry(
            title: "Creating a multiview video playback experience in visionOS",
            url: "/documentation/AVKit/creating-a-multiview-video-playback-experience-in-visionos",
            framework: "AVKit",
            description: "Build an interface that plays multiple videos simultaneously and handles transitions to different experience types gracefully.",
            zipFilename: "avkit-creating-a-multiview-video-playback-experience-in-visionos.zip",
            webURL: "https://developer.apple.com/documentation/AVKit/creating-a-multiview-video-playback-experience-in-visionos"
        ),
        SampleCodeEntry(
            title: "Playing immersive media with AVKit",
            url: "/documentation/AVKit/playing-immersive-media-with-avkit",
            framework: "AVKit",
            description: "Adopt the system playback interface to provide an immersive video watching experience.",
            zipFilename: "avkit-playing-immersive-media-with-avkit.zip",
            webURL: "https://developer.apple.com/documentation/AVKit/playing-immersive-media-with-avkit"
        ),
        SampleCodeEntry(
            title: "Playing video content in a standard user interface",
            url: "/documentation/AVKit/playing-video-content-in-a-standard-user-interface",
            framework: "AVKit",
            description: "Play media full screen, embedded inline, or in a floating Picture in Picture (PiP) window using a player view controller.",
            zipFilename: "avkit-playing-video-content-in-a-standard-user-interface.zip",
            webURL: "https://developer.apple.com/documentation/AVKit/playing-video-content-in-a-standard-user-interface"
        ),
        SampleCodeEntry(
            title: "Supporting Continuity Camera in your tvOS app",
            url: "/documentation/AVKit/supporting-continuity-camera-in-your-tvos-app",
            framework: "AVKit",
            description: "Capture high-quality photos, video, and audio in your Apple TV app by connecting an iPhone or iPad as a continuity device.",
            zipFilename: "avkit-supporting-continuity-camera-in-your-tvos-app.zip",
            webURL: "https://developer.apple.com/documentation/AVKit/supporting-continuity-camera-in-your-tvos-app"
        ),
        SampleCodeEntry(
            title: "Working with Overlays and Parental Controls in tvOS",
            url: "/documentation/AVKit/working-with-overlays-and-parental-controls-in-tvos",
            framework: "AVKit",
            description: "Add interactive overlays, parental controls, and livestream channel flipping using a player view controller.###",
            zipFilename: "avkit-working-with-overlays-and-parental-controls-in-tvos.zip",
            webURL: "https://developer.apple.com/documentation/AVKit/working-with-overlays-and-parental-controls-in-tvos"
        ),
        SampleCodeEntry(
            title: "Adding a bokeh effect to images",
            url: "/documentation/Accelerate/adding-a-bokeh-effect-to-images",
            framework: "Accelerate",
            description: "Simulate a bokeh effect by applying dilation.",
            zipFilename: "accelerate-adding-a-bokeh-effect-to-images.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/adding-a-bokeh-effect-to-images"
        ),
        SampleCodeEntry(
            title: "Adjusting saturation and applying tone mapping",
            url: "/documentation/Accelerate/adjusting-saturation-and-applying-tone-mapping",
            framework: "Accelerate",
            description: "Convert an RGB image to discrete luminance and chrominance channels, and apply color and contrast treatments.",
            zipFilename: "accelerate-adjusting-saturation-and-applying-tone-mapping.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/adjusting-saturation-and-applying-tone-mapping"
        ),
        SampleCodeEntry(
            title: "Adjusting the brightness and contrast of an image",
            url: "/documentation/Accelerate/adjusting-the-brightness-and-contrast-of-an-image",
            framework: "Accelerate",
            description: "Use a gamma function to apply a linear or exponential curve.",
            zipFilename: "accelerate-adjusting-the-brightness-and-contrast-of-an-image.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/adjusting-the-brightness-and-contrast-of-an-image"
        ),
        SampleCodeEntry(
            title: "Adjusting the hue of an image",
            url: "/documentation/Accelerate/adjusting-the-hue-of-an-image",
            framework: "Accelerate",
            description: "Convert an image to L*a*b* color space and apply hue adjustment.",
            zipFilename: "accelerate-adjusting-the-hue-of-an-image.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/adjusting-the-hue-of-an-image"
        ),
        SampleCodeEntry(
            title: "Applying biquadratic filters to a music loop",
            url: "/documentation/Accelerate/applying-biquadratic-filters-to-a-music-loop",
            framework: "Accelerate",
            description: "Change the frequency response of an audio signal using a cascaded biquadratic filter.",
            zipFilename: "accelerate-applying-biquadratic-filters-to-a-music-loop.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/applying-biquadratic-filters-to-a-music-loop"
        ),
        SampleCodeEntry(
            title: "Applying tone curve adjustments to images",
            url: "/documentation/Accelerate/applying-tone-curve-adjustments-to-images",
            framework: "Accelerate",
            description: "Use the vImage library’s polynomial transform to apply tone curve adjustments to images.",
            zipFilename: "accelerate-applying-tone-curve-adjustments-to-images.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/applying-tone-curve-adjustments-to-images"
        ),
        SampleCodeEntry(
            title: "Applying transformations to selected colors in an image",
            url: "/documentation/Accelerate/applying-transformations-to-selected-colors-in-an-image",
            framework: "Accelerate",
            description: "Desaturate a range of colors in an image with a multidimensional lookup table.",
            zipFilename: "accelerate-applying-transformations-to-selected-colors-in-an-image.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/applying-transformations-to-selected-colors-in-an-image"
        ),
        SampleCodeEntry(
            title: "Applying vImage operations to video sample buffers",
            url: "/documentation/Accelerate/applying-vimage-operations-to-video-sample-buffers",
            framework: "Accelerate",
            description: "Use the vImage convert-any-to-any functionality to perform real-time image processing of video frames streamed from your device’s camera.",
            zipFilename: "accelerate-applying-vimage-operations-to-video-sample-buffers.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/applying-vimage-operations-to-video-sample-buffers"
        ),
        SampleCodeEntry(
            title: "Blurring an image",
            url: "/documentation/Accelerate/blurring-an-image",
            framework: "Accelerate",
            description: "Filter an image by convolving it with custom and high-speed kernels.",
            zipFilename: "accelerate-blurring-an-image.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/blurring-an-image"
        ),
        SampleCodeEntry(
            title: "Calculating the dominant colors in an image",
            url: "/documentation/Accelerate/calculating-the-dominant-colors-in-an-image",
            framework: "Accelerate",
            description: "Find the main colors in an image by implementing k-means clustering using the Accelerate framework.",
            zipFilename: "accelerate-calculating-the-dominant-colors-in-an-image.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/calculating-the-dominant-colors-in-an-image"
        ),
        SampleCodeEntry(
            title: "Compressing an image using linear algebra",
            url: "/documentation/Accelerate/compressing-an-image-using-linear-algebra",
            framework: "Accelerate",
            description: "Reduce the storage size of an image using singular value decomposition (SVD).",
            zipFilename: "accelerate-compressing-an-image-using-linear-algebra.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/compressing-an-image-using-linear-algebra"
        ),
        SampleCodeEntry(
            title: "Compressing and decompressing files with stream compression",
            url: "/documentation/Accelerate/compressing-and-decompressing-files-with-stream-compression",
            framework: "Accelerate",
            description: "Perform compression for all files and decompression for files with supported extension types.",
            zipFilename: "accelerate-compressing-and-decompressing-files-with-stream-compression.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/compressing-and-decompressing-files-with-stream-compression"
        ),
        SampleCodeEntry(
            title: "Converting color images to grayscale",
            url: "/documentation/Accelerate/converting-color-images-to-grayscale",
            framework: "Accelerate",
            description: "Convert an RGB image to grayscale using matrix multiplication.",
            zipFilename: "accelerate-converting-color-images-to-grayscale.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/converting-color-images-to-grayscale"
        ),
        SampleCodeEntry(
            title: "Converting luminance and chrominance planes to an ARGB image",
            url: "/documentation/Accelerate/converting-luminance-and-chrominance-planes-to-an-argb-image",
            framework: "Accelerate",
            description: "Create a displayable ARGB image using the luminance and chrominance information from your device’s camera.",
            zipFilename: "accelerate-converting-luminance-and-chrominance-planes-to-an-argb-image.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/converting-luminance-and-chrominance-planes-to-an-argb-image"
        ),
        SampleCodeEntry(
            title: "Creating an audio unit extension using the vDSP library",
            url: "/documentation/Accelerate/creating-an-audio-unit-extension-using-the-vdsp-library",
            framework: "Accelerate",
            description: "Add biquadratic filter audio-effect processing to apps like Logic Pro X and GarageBand with the Accelerate framework.",
            zipFilename: "accelerate-creating-an-audio-unit-extension-using-the-vdsp-library.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/creating-an-audio-unit-extension-using-the-vdsp-library"
        ),
        SampleCodeEntry(
            title: "Cropping to the subject in a chroma-keyed image",
            url: "/documentation/Accelerate/cropping-to-the-subject-in-a-chroma-keyed-image",
            framework: "Accelerate",
            description: "Convert a chroma-key color to alpha values and trim transparent pixels using Accelerate.",
            zipFilename: "accelerate-cropping-to-the-subject-in-a-chroma-keyed-image.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/cropping-to-the-subject-in-a-chroma-keyed-image"
        ),
        SampleCodeEntry(
            title: "Equalizing audio with discrete cosine transforms (DCTs)",
            url: "/documentation/Accelerate/equalizing-audio-with-discrete-cosine-transforms-dcts",
            framework: "Accelerate",
            description: "Change the frequency response of an audio signal by manipulating frequency-domain data.",
            zipFilename: "accelerate-equalizing-audio-with-discrete-cosine-transforms-dcts.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/equalizing-audio-with-discrete-cosine-transforms-dcts"
        ),
        SampleCodeEntry(
            title: "Finding the sharpest image in a sequence of captured images",
            url: "/documentation/Accelerate/finding-the-sharpest-image-in-a-sequence-of-captured-images",
            framework: "Accelerate",
            description: "Share image data between vDSP and vImage to compute the sharpest image from a bracketed photo sequence.",
            zipFilename: "accelerate-finding-the-sharpest-image-in-a-sequence-of-captured-images.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/finding-the-sharpest-image-in-a-sequence-of-captured-images"
        ),
        SampleCodeEntry(
            title: "Halftone descreening with 2D fast Fourier transform",
            url: "/documentation/Accelerate/halftone-descreening-with-2d-fast-fourier-transform",
            framework: "Accelerate",
            description: "Reduce or remove periodic artifacts from images.",
            zipFilename: "accelerate-halftone-descreening-with-2d-fast-fourier-transform.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/halftone-descreening-with-2d-fast-fourier-transform"
        ),
        SampleCodeEntry(
            title: "Improving the quality of quantized images with dithering",
            url: "/documentation/Accelerate/improving-the-quality-of-quantized-images-with-dithering",
            framework: "Accelerate",
            description: "Apply dithering to simulate colors that are unavailable in reduced bit depths.",
            zipFilename: "accelerate-improving-the-quality-of-quantized-images-with-dithering.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/improving-the-quality-of-quantized-images-with-dithering"
        ),
        SampleCodeEntry(
            title: "Integrating vImage pixel buffers into a Core Image workflow",
            url: "/documentation/Accelerate/integrating-vimage-pixel-buffers-into-a-core-image-workflow",
            framework: "Accelerate",
            description: "Share image data between Core Video pixel buffers and vImage buffers to integrate vImage operations into a Core Image workflow.",
            zipFilename: "accelerate-integrating-vimage-pixel-buffers-into-a-core-image-workflow.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/integrating-vimage-pixel-buffers-into-a-core-image-workflow"
        ),
        SampleCodeEntry(
            title: "Reducing artifacts with custom resampling filters",
            url: "/documentation/Accelerate/reducing-artifacts-with-custom-resampling-filters",
            framework: "Accelerate",
            description: "Implement custom linear interpolation to prevent the ringing effects associated with scaling an image with the default Lanczos algorithm.",
            zipFilename: "accelerate-reducing-artifacts-with-custom-resampling-filters.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/reducing-artifacts-with-custom-resampling-filters"
        ),
        SampleCodeEntry(
            title: "Rotating a cube by transforming its vertices",
            url: "/documentation/Accelerate/rotating-a-cube-by-transforming-its-vertices",
            framework: "Accelerate",
            description: "Rotate a cube through a series of keyframes using quaternion interpolation to transition between them.",
            zipFilename: "accelerate-rotating-a-cube-by-transforming-its-vertices.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/rotating-a-cube-by-transforming-its-vertices"
        ),
        SampleCodeEntry(
            title: "Sharing texture data between the Model I/O framework and the vImage library",
            url: "/documentation/Accelerate/sharing-texture-data-between-the-model-io-framework-and-the-vimage-library",
            framework: "Accelerate",
            description: "Use Model I/O and vImage to composite a photograph over a computer-generated sky.",
            zipFilename: "accelerate-sharing-texture-data-between-the-model-io-framework-and-the-vimage-library.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/sharing-texture-data-between-the-model-io-framework-and-the-vimage-library"
        ),
        SampleCodeEntry(
            title: "Signal extraction from noise",
            url: "/documentation/Accelerate/signal-extraction-from-noise",
            framework: "Accelerate",
            description: "Use Accelerate’s discrete cosine transform to remove noise from a signal.",
            zipFilename: "accelerate-signal-extraction-from-noise.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/signal-extraction-from-noise"
        ),
        SampleCodeEntry(
            title: "Solving systems of linear equations with LAPACK",
            url: "/documentation/Accelerate/solving-systems-of-linear-equations-with-lapack",
            framework: "Accelerate",
            description: "Select the optimal LAPACK routine to solve a system of linear equations.",
            zipFilename: "accelerate-solving-systems-of-linear-equations-with-lapack.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/solving-systems-of-linear-equations-with-lapack"
        ),
        SampleCodeEntry(
            title: "Specifying histograms with vImage",
            url: "/documentation/Accelerate/specifying-histograms-with-vimage",
            framework: "Accelerate",
            description: "Calculate the histogram of one image, and apply it to a second image.",
            zipFilename: "accelerate-specifying-histograms-with-vimage.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/specifying-histograms-with-vimage"
        ),
        SampleCodeEntry(
            title: "Supporting real-time ML inference on the CPU",
            url: "/documentation/Accelerate/supporting-real-time-ml-inference-on-the-cpu",
            framework: "Accelerate",
            description: "Add real-time digital signal processing to apps like Logic Pro X and GarageBand with the BNNS Graph API.",
            zipFilename: "accelerate-supporting-real-time-ml-inference-on-the-cpu.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/supporting-real-time-ml-inference-on-the-cpu"
        ),
        SampleCodeEntry(
            title: "Training a neural network to recognize digits",
            url: "/documentation/Accelerate/training-a-neural-network-to-recognize-digits",
            framework: "Accelerate",
            description: "Build a simple neural network and train it to recognize randomly generated numbers.",
            zipFilename: "accelerate-training-a-neural-network-to-recognize-digits.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/training-a-neural-network-to-recognize-digits"
        ),
        SampleCodeEntry(
            title: "Using vImage pixel buffers to generate video effects",
            url: "/documentation/Accelerate/using-vimage-pixel-buffers-to-generate-video-effects",
            framework: "Accelerate",
            description: "Render real-time video effects with the vImage Pixel Buffer.",
            zipFilename: "accelerate-using-vimage-pixel-buffers-to-generate-video-effects.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/using-vimage-pixel-buffers-to-generate-video-effects"
        ),
        SampleCodeEntry(
            title: "Visualizing sound as an audio spectrogram",
            url: "/documentation/Accelerate/visualizing-sound-as-an-audio-spectrogram",
            framework: "Accelerate",
            description: "Share image data between vDSP and vImage to visualize audio that a device microphone captures.###",
            zipFilename: "accelerate-visualizing-sound-as-an-audio-spectrogram.zip",
            webURL: "https://developer.apple.com/documentation/Accelerate/visualizing-sound-as-an-audio-spectrogram"
        ),
        SampleCodeEntry(
            title: "Accessibility design for Mac Catalyst",
            url: "/documentation/Accessibility/accessibility_design_for_mac_catalyst",
            framework: "Accessibility",
            description: "Improve navigation in your app by using keyboard shortcuts and accessibility containers.",
            zipFilename: "accessibility-accessibility_design_for_mac_catalyst.zip",
            webURL: "https://developer.apple.com/documentation/Accessibility/accessibility_design_for_mac_catalyst"
        ),
        SampleCodeEntry(
            title: "Delivering an exceptional accessibility experience",
            url: "/documentation/Accessibility/delivering_an_exceptional_accessibility_experience",
            framework: "Accessibility",
            description: "Make improvements to your app’s interaction model to support assistive technologies such as VoiceOver.",
            zipFilename: "accessibility-delivering_an_exceptional_accessibility_experience.zip",
            webURL: "https://developer.apple.com/documentation/Accessibility/delivering_an_exceptional_accessibility_experience"
        ),
        SampleCodeEntry(
            title: "Enhancing the accessibility of your SwiftUI app",
            url: "/documentation/Accessibility/enhancing-the-accessibility-of-your-swiftui-app",
            framework: "Accessibility",
            description: "Support advancements in SwiftUI accessibility to make your app accessible to everyone.",
            zipFilename: "accessibility-enhancing-the-accessibility-of-your-swiftui-app.zip",
            webURL: "https://developer.apple.com/documentation/Accessibility/enhancing-the-accessibility-of-your-swiftui-app"
        ),
        SampleCodeEntry(
            title: "Integrating accessibility into your app",
            url: "/documentation/Accessibility/integrating_accessibility_into_your_app",
            framework: "Accessibility",
            description: "Make your app more accessible to users with disabilities by adding accessibility features.",
            zipFilename: "accessibility-integrating_accessibility_into_your_app.zip",
            webURL: "https://developer.apple.com/documentation/Accessibility/integrating_accessibility_into_your_app"
        ),
        SampleCodeEntry(
            title: "WWDC21 Challenge: Large Text Challenge",
            url: "/documentation/Accessibility/wwdc21_challenge_large_text_challenge",
            framework: "Accessibility",
            description: "Design for large text sizes by modifying the user interface.",
            zipFilename: "accessibility-wwdc21_challenge_large_text_challenge.zip",
            webURL: "https://developer.apple.com/documentation/Accessibility/wwdc21_challenge_large_text_challenge"
        ),
        SampleCodeEntry(
            title: "WWDC21 Challenge: Speech Synthesizer Simulator",
            url: "/documentation/Accessibility/wwdc21_challenge_speech_synthesizer_simulator",
            framework: "Accessibility",
            description: "Simulate a conversation using speech synthesis.",
            zipFilename: "accessibility-wwdc21_challenge_speech_synthesizer_simulator.zip",
            webURL: "https://developer.apple.com/documentation/Accessibility/wwdc21_challenge_speech_synthesizer_simulator"
        ),
        SampleCodeEntry(
            title: "WWDC21 Challenge: VoiceOver Maze",
            url: "/documentation/Accessibility/wwdc21_challenge_voiceover_maze",
            framework: "Accessibility",
            description: "Navigate to the end of a dark maze using VoiceOver as your guide.",
            zipFilename: "accessibility-wwdc21_challenge_voiceover_maze.zip",
            webURL: "https://developer.apple.com/documentation/Accessibility/wwdc21_challenge_voiceover_maze"
        ),
        SampleCodeEntry(
            title: "WWDC22 Challenge: Learn Switch Control through gaming",
            url: "/documentation/Accessibility/wwdc22_challenge_learn_switch_control_through_gaming",
            framework: "Accessibility",
            description: "Play a card-matching game using Switch Control.###",
            zipFilename: "accessibility-wwdc22_challenge_learn_switch_control_through_gaming.zip",
            webURL: "https://developer.apple.com/documentation/Accessibility/wwdc22_challenge_learn_switch_control_through_gaming"
        ),
        SampleCodeEntry(
            title: "Setting up and authorizing a Bluetooth accessory",
            url: "/documentation/AccessorySetupKit/setting-up-and-authorizing-a-bluetooth-accessory",
            framework: "AccessorySetupKit",
            description: "Discover, select, and set up a specific Bluetooth accessory without requesting permission to use Bluetooth.",
            zipFilename: "accessorysetupkit-setting-up-and-authorizing-a-bluetooth-accessory.zip",
            webURL: "https://developer.apple.com/documentation/AccessorySetupKit/setting-up-and-authorizing-a-bluetooth-accessory"
        ),
        SampleCodeEntry(
            title: "Scheduling an alarm with AlarmKit",
            url: "/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit",
            framework: "AlarmKit",
            description: "Create prominent alerts at specified dates for your iOS app.",
            zipFilename: "alarmkit-scheduling-an-alarm-with-alarmkit.zip",
            webURL: "https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit"
        ),
        SampleCodeEntry(
            title: "Fruta: Building a feature-rich app with SwiftUI",
            url: "/documentation/AppClip/fruta-building-a-feature-rich-app-with-swiftui",
            framework: "AppClip",
            description: "Create a shared codebase to build a multiplatform app that offers widgets and an App Clip.",
            zipFilename: "appclip-fruta-building-a-feature-rich-app-with-swiftui.zip",
            webURL: "https://developer.apple.com/documentation/AppClip/fruta-building-a-feature-rich-app-with-swiftui"
        ),
        SampleCodeEntry(
            title: "Interacting with App Clip Codes in AR",
            url: "/documentation/AppClip/interacting-with-app-clip-codes-in-ar",
            framework: "AppClip",
            description: "Display content and provide services in an AR experience with App Clip Codes.",
            zipFilename: "appclip-interacting-with-app-clip-codes-in-ar.zip",
            webURL: "https://developer.apple.com/documentation/AppClip/interacting-with-app-clip-codes-in-ar"
        ),
        SampleCodeEntry(
            title: "Accelerating app interactions with App Intents",
            url: "/documentation/AppIntents/AcceleratingAppInteractionsWithAppIntents",
            framework: "AppIntents",
            description: "Enable people to use your app’s features quickly through Siri, Spotlight, and Shortcuts.",
            zipFilename: "appintents-acceleratingappinteractionswithappintents.zip",
            webURL: "https://developer.apple.com/documentation/AppIntents/AcceleratingAppInteractionsWithAppIntents"
        ),
        SampleCodeEntry(
            title: "Adopting App Intents to support system experiences",
            url: "/documentation/AppIntents/adopting-app-intents-to-support-system-experiences",
            framework: "AppIntents",
            description: "Create app intents and entities to incorporate system experiences such as Spotlight, visual intelligence, and Shortcuts.",
            zipFilename: "appintents-adopting-app-intents-to-support-system-experiences.zip",
            webURL: "https://developer.apple.com/documentation/AppIntents/adopting-app-intents-to-support-system-experiences"
        ),
        SampleCodeEntry(
            title: "Defining your app’s Focus filter",
            url: "/documentation/AppIntents/defining-your-app-s-focus-filter",
            framework: "AppIntents",
            description: "Customize your app’s behavior to reflect the device’s current Focus.",
            zipFilename: "appintents-defining-your-app-s-focus-filter.zip",
            webURL: "https://developer.apple.com/documentation/AppIntents/defining-your-app-s-focus-filter"
        ),
        SampleCodeEntry(
            title: "Making your app’s functionality available to Siri",
            url: "/documentation/AppIntents/making-your-app-s-functionality-available-to-siri",
            framework: "AppIntents",
            description: "Add app intent schemas to your app so Siri can complete requests, and integrate your app with Apple Intelligence, Spotlight, and other system experiences.",
            zipFilename: "appintents-making-your-app-s-functionality-available-to-siri.zip",
            webURL: "https://developer.apple.com/documentation/AppIntents/making-your-app-s-functionality-available-to-siri"
        ),
        SampleCodeEntry(
            title: "Add Functionality to Finder with Action Extensions",
            url: "/documentation/AppKit/add-functionality-to-finder-with-action-extensions",
            framework: "AppKit",
            description: "Implement Action Extensions to provide quick access to commonly used features of your app.",
            zipFilename: "appkit-add-functionality-to-finder-with-action-extensions.zip",
            webURL: "https://developer.apple.com/documentation/AppKit/add-functionality-to-finder-with-action-extensions"
        ),
        SampleCodeEntry(
            title: "Creating and Customizing the Touch Bar",
            url: "/documentation/AppKit/creating-and-customizing-the-touch-bar",
            framework: "AppKit",
            description: "Adopt Touch Bar support by displaying interactive content and controls for your macOS apps.",
            zipFilename: "appkit-creating-and-customizing-the-touch-bar.zip",
            webURL: "https://developer.apple.com/documentation/AppKit/creating-and-customizing-the-touch-bar"
        ),
        SampleCodeEntry(
            title: "Developing a Document-Based App",
            url: "/documentation/AppKit/developing-a-document-based-app",
            framework: "AppKit",
            description: "Write an app that creates, manages, edits, and saves text documents.",
            zipFilename: "appkit-developing-a-document-based-app.zip",
            webURL: "https://developer.apple.com/documentation/AppKit/developing-a-document-based-app"
        ),
        SampleCodeEntry(
            title: "Enhancing your custom text engine with Writing Tools",
            url: "/documentation/AppKit/enhancing-your-custom-text-engine-with-writing-tools",
            framework: "AppKit",
            description: "Add Writing Tools support to your custom text engine to enhance the text editing experience.",
            zipFilename: "appkit-enhancing-your-custom-text-engine-with-writing-tools.zip",
            webURL: "https://developer.apple.com/documentation/AppKit/enhancing-your-custom-text-engine-with-writing-tools"
        ),
        SampleCodeEntry(
            title: "Integrating a Toolbar and Touch Bar into Your App",
            url: "/documentation/AppKit/integrating-a-toolbar-and-touch-bar-into-your-app",
            framework: "AppKit",
            description: "Provide users quick access to your app’s features from a toolbar and corresponding Touch Bar.",
            zipFilename: "appkit-integrating-a-toolbar-and-touch-bar-into-your-app.zip",
            webURL: "https://developer.apple.com/documentation/AppKit/integrating-a-toolbar-and-touch-bar-into-your-app"
        ),
        SampleCodeEntry(
            title: "Navigating Hierarchical Data Using Outline and Split Views",
            url: "/documentation/AppKit/navigating-hierarchical-data-using-outline-and-split-views",
            framework: "AppKit",
            description: "Build a structured user interface that simplifies navigation in your app.",
            zipFilename: "appkit-navigating-hierarchical-data-using-outline-and-split-views.zip",
            webURL: "https://developer.apple.com/documentation/AppKit/navigating-hierarchical-data-using-outline-and-split-views"
        ),
        SampleCodeEntry(
            title: "Organize Your User Interface with a Stack View",
            url: "/documentation/AppKit/organize-your-user-interface-with-a-stack-view",
            framework: "AppKit",
            description: "Group individual views in your app’s user interface into a scrollable stack view.",
            zipFilename: "appkit-organize-your-user-interface-with-a-stack-view.zip",
            webURL: "https://developer.apple.com/documentation/AppKit/organize-your-user-interface-with-a-stack-view"
        ),
        SampleCodeEntry(
            title: "Supporting Collection View Drag and Drop Through File Promises",
            url: "/documentation/AppKit/supporting-collection-view-drag-and-drop-through-file-promises",
            framework: "AppKit",
            description: "Share data between macOS apps during drag and drop by using an item provider.",
            zipFilename: "appkit-supporting-collection-view-drag-and-drop-through-file-promises.zip",
            webURL: "https://developer.apple.com/documentation/AppKit/supporting-collection-view-drag-and-drop-through-file-promises"
        ),
        SampleCodeEntry(
            title: "Supporting Drag and Drop Through File Promises",
            url: "/documentation/AppKit/supporting-drag-and-drop-through-file-promises",
            framework: "AppKit",
            description: "Receive and provide file promises to support dragged app files and pasteboard operations.",
            zipFilename: "appkit-supporting-drag-and-drop-through-file-promises.zip",
            webURL: "https://developer.apple.com/documentation/AppKit/supporting-drag-and-drop-through-file-promises"
        ),
        SampleCodeEntry(
            title: "Supporting Table View Drag and Drop Through File Promises",
            url: "/documentation/AppKit/supporting-table-view-drag-and-drop-through-file-promises",
            framework: "AppKit",
            description: "Share data between macOS apps during drag and drop by using an item provider.###",
            zipFilename: "appkit-supporting-table-view-drag-and-drop-through-file-promises.zip",
            webURL: "https://developer.apple.com/documentation/AppKit/supporting-table-view-drag-and-drop-through-file-promises"
        ),
        SampleCodeEntry(
            title: "Retrieve Power and Performance Metrics and Log Insights",
            url: "/documentation/AppStoreConnectAPI/retrieve-power-and-performance-metrics-and-log-insights",
            framework: "AppStoreConnectAPI",
            description: "Use the App Store Connect API to collect and parse diagnostic logs and metrics for your apps.",
            zipFilename: "appstoreconnectapi-retrieve-power-and-performance-metrics-and-log-insights.zip",
            webURL: "https://developer.apple.com/documentation/AppStoreConnectAPI/retrieve-power-and-performance-metrics-and-log-insights"
        ),
        SampleCodeEntry(
            title: "Uploading App Previews",
            url: "/documentation/AppStoreConnectAPI/uploading-app-previews",
            framework: "AppStoreConnectAPI",
            description: "Upload your app previews, including video files, to App Store Connect by using the asset upload APIs.",
            zipFilename: "appstoreconnectapi-uploading-app-previews.zip",
            webURL: "https://developer.apple.com/documentation/AppStoreConnectAPI/uploading-app-previews"
        ),
        SampleCodeEntry(
            title: "Providing an edge-to-edge, full-screen experience in your iPad app running on a Mac",
            url: "/documentation/Apple-Silicon/providing-an-edge-to-edge-full-screen-experience-in-your-ipad-app-running-on-a-mac",
            framework: "Apple-Silicon",
            description: "Take advantage of the true native resolution of a Mac display when running your iPad app in full-screen mode on a Mac.",
            zipFilename: "apple-silicon-providing-an-edge-to-edge-full-screen-experience-in-your-ipad-app-running-on-a-mac.zip",
            webURL: "https://developer.apple.com/documentation/Apple-Silicon/providing-an-edge-to-edge-full-screen-experience-in-your-ipad-app-running-on-a-mac"
        ),
        SampleCodeEntry(
            title: "Providing touch gesture equivalents using Touch Alternatives",
            url: "/documentation/Apple-Silicon/providing-touch-gesture-equivalents-using-touch-alternatives",
            framework: "Apple-Silicon",
            description: "Enable Touch Alternatives to provide keyboard, mouse, and trackpad equivalents to your iOS app when it runs on a Mac with Apple silicon.",
            zipFilename: "apple-silicon-providing-touch-gesture-equivalents-using-touch-alternatives.zip",
            webURL: "https://developer.apple.com/documentation/Apple-Silicon/providing-touch-gesture-equivalents-using-touch-alternatives"
        ),
        SampleCodeEntry(
            title: "Encrypting and Decrypting Directories",
            url: "/documentation/AppleArchive/encrypting-and-decrypting-directories",
            framework: "AppleArchive",
            description: "Compress and encrypt the contents of an entire directory or decompress and decrypt an archived directory using Apple Encrypted Archive.",
            zipFilename: "applearchive-encrypting-and-decrypting-directories.zip",
            webURL: "https://developer.apple.com/documentation/AppleArchive/encrypting-and-decrypting-directories"
        ),
        SampleCodeEntry(
            title: "Encrypting and Decrypting a Single File",
            url: "/documentation/AppleArchive/encrypting-and-decrypting-a-single-file",
            framework: "AppleArchive",
            description: "Encrypt a single file and save the result to the file system, then decrypt and recreate the original file from the archive file using Apple Encrypted Archive.",
            zipFilename: "applearchive-encrypting-and-decrypting-a-single-file.zip",
            webURL: "https://developer.apple.com/documentation/AppleArchive/encrypting-and-decrypting-a-single-file"
        ),
        SampleCodeEntry(
            title: "Encrypting and Decrypting a String",
            url: "/documentation/AppleArchive/encrypting-and-decrypting-a-string",
            framework: "AppleArchive",
            description: "Encrypt the contents of a string and save the result to the file system, then decrypt and recreate the string from the archive file using Apple Encrypted Archive.",
            zipFilename: "applearchive-encrypting-and-decrypting-a-string.zip",
            webURL: "https://developer.apple.com/documentation/AppleArchive/encrypting-and-decrypting-a-string"
        ),
        SampleCodeEntry(
            title: "Integrating the Apple Maps Server API into Java server applications",
            url: "/documentation/AppleMapsServerAPI/integrating-the-apple-maps-server-api-into-java-server-applications",
            framework: "AppleMapsServerAPI",
            description: "Streamline your app’s API by moving georelated searches from inside your app to your server.",
            zipFilename: "applemapsserverapi-integrating-the-apple-maps-server-api-into-java-server-applications.zip",
            webURL: "https://developer.apple.com/documentation/AppleMapsServerAPI/integrating-the-apple-maps-server-api-into-java-server-applications"
        ),
        SampleCodeEntry(
            title: "Creating an audio device driver",
            url: "/documentation/AudioDriverKit/creating-an-audio-device-driver",
            framework: "AudioDriverKit",
            description: "Implement a configurable audio input source as a driver extension that runs in user space in macOS and iPadOS.",
            zipFilename: "audiodriverkit-creating-an-audio-device-driver.zip",
            webURL: "https://developer.apple.com/documentation/AudioDriverKit/creating-an-audio-device-driver"
        ),
        SampleCodeEntry(
            title: "Encoding and decoding audio",
            url: "/documentation/AudioToolbox/encoding-and-decoding-audio",
            framework: "AudioToolbox",
            description: "Convert audio formats to efficiently manage data and quality.",
            zipFilename: "audiotoolbox-encoding-and-decoding-audio.zip",
            webURL: "https://developer.apple.com/documentation/AudioToolbox/encoding-and-decoding-audio"
        ),
        SampleCodeEntry(
            title: "Generating spatial audio from a multichannel audio stream",
            url: "/documentation/AudioToolbox/generating-spatial-audio-from-a-multichannel-audio-stream",
            framework: "AudioToolbox",
            description: "Convert 8-channel audio to 2-channel spatial audio by using a spatial mixer audio unit.",
            zipFilename: "audiotoolbox-generating-spatial-audio-from-a-multichannel-audio-stream.zip",
            webURL: "https://developer.apple.com/documentation/AudioToolbox/generating-spatial-audio-from-a-multichannel-audio-stream"
        ),
        SampleCodeEntry(
            title: "Incorporating Audio Effects and Instruments",
            url: "/documentation/AudioToolbox/incorporating-audio-effects-and-instruments",
            framework: "AudioToolbox",
            description: "Add custom audio processing and MIDI instruments to your app by hosting Audio Unit (AU) plug-ins.",
            zipFilename: "audiotoolbox-incorporating-audio-effects-and-instruments.zip",
            webURL: "https://developer.apple.com/documentation/AudioToolbox/incorporating-audio-effects-and-instruments"
        ),
        SampleCodeEntry(
            title: "Connecting to a service with passkeys",
            url: "/documentation/AuthenticationServices/connecting-to-a-service-with-passkeys",
            framework: "AuthenticationServices",
            description: "Allow users to sign in to a service without typing a password.",
            zipFilename: "authenticationservices-connecting-to-a-service-with-passkeys.zip",
            webURL: "https://developer.apple.com/documentation/AuthenticationServices/connecting-to-a-service-with-passkeys"
        ),
        SampleCodeEntry(
            title: "Implementing User Authentication with Sign in with Apple",
            url: "/documentation/AuthenticationServices/implementing-user-authentication-with-sign-in-with-apple",
            framework: "AuthenticationServices",
            description: "Provide a way for users of your app to set up an account and start using your services.",
            zipFilename: "authenticationservices-implementing-user-authentication-with-sign-in-with-apple.zip",
            webURL: "https://developer.apple.com/documentation/AuthenticationServices/implementing-user-authentication-with-sign-in-with-apple"
        ),
        SampleCodeEntry(
            title: "Performing fast account creation with passkeys",
            url: "/documentation/AuthenticationServices/performing-fast-account-creation-with-passkeys",
            framework: "AuthenticationServices",
            description: "Allow people to quickly create an account with passkeys and associated domains.",
            zipFilename: "authenticationservices-performing-fast-account-creation-with-passkeys.zip",
            webURL: "https://developer.apple.com/documentation/AuthenticationServices/performing-fast-account-creation-with-passkeys"
        ),
        SampleCodeEntry(
            title: "Simplifying User Authentication in a tvOS App",
            url: "/documentation/AuthenticationServices/simplifying-user-authentication-in-a-tvos-app",
            framework: "AuthenticationServices",
            description: "Build a fluid sign-in experience for your tvOS apps using AuthenticationServices.###",
            zipFilename: "authenticationservices-simplifying-user-authentication-in-a-tvos-app.zip",
            webURL: "https://developer.apple.com/documentation/AuthenticationServices/simplifying-user-authentication-in-a-tvos-app"
        ),
        SampleCodeEntry(
            title: "Build an Educational Assessment App",
            url: "/documentation/AutomaticAssessmentConfiguration/build-an-educational-assessment-app",
            framework: "AutomaticAssessmentConfiguration",
            description: "Ensure the academic integrity of your assessment app by using Automatic Assessment Configuration.",
            zipFilename: "automaticassessmentconfiguration-build-an-educational-assessment-app.zip",
            webURL: "https://developer.apple.com/documentation/AutomaticAssessmentConfiguration/build-an-educational-assessment-app"
        ),
        SampleCodeEntry(
            title: "Downloading essential assets in the background",
            url: "/documentation/BackgroundAssets/downloading-essential-assets-in-the-background",
            framework: "BackgroundAssets",
            description: "Fetch the assets your app requires before its first launch using an app extension and the Background Assets framework.",
            zipFilename: "backgroundassets-downloading-essential-assets-in-the-background.zip",
            webURL: "https://developer.apple.com/documentation/BackgroundAssets/downloading-essential-assets-in-the-background"
        ),
        SampleCodeEntry(
            title: "Refreshing and Maintaining Your App Using Background Tasks",
            url: "/documentation/BackgroundTasks/refreshing-and-maintaining-your-app-using-background-tasks",
            framework: "BackgroundTasks",
            description: "Use scheduled background tasks for refreshing your app content and for performing maintenance.",
            zipFilename: "backgroundtasks-refreshing-and-maintaining-your-app-using-background-tasks.zip",
            webURL: "https://developer.apple.com/documentation/BackgroundTasks/refreshing-and-maintaining-your-app-using-background-tasks"
        ),
        SampleCodeEntry(
            title: "Developing a browser app that uses an alternative browser engine",
            url: "/documentation/BrowserEngineKit/developing-a-browser-app-that-uses-an-alternative-browser-engine",
            framework: "BrowserEngineKit",
            description: "Create a web browser app and associated extensions.",
            zipFilename: "browserenginekit-developing-a-browser-app-that-uses-an-alternative-browser-engine.zip",
            webURL: "https://developer.apple.com/documentation/BrowserEngineKit/developing-a-browser-app-that-uses-an-alternative-browser-engine"
        ),
        SampleCodeEntry(
            title: "VoIP calling with CallKit",
            url: "/documentation/CallKit/voip-calling-with-callkit",
            framework: "CallKit",
            description: "Use the CallKit framework to integrate native VoIP calling.###",
            zipFilename: "callkit-voip-calling-with-callkit.zip",
            webURL: "https://developer.apple.com/documentation/CallKit/voip-calling-with-callkit"
        ),
        SampleCodeEntry(
            title: "Integrating CarPlay with Your Music App",
            url: "/documentation/CarPlay/integrating-carplay-with-your-music-app",
            framework: "CarPlay",
            description: "Configure your music app to work with CarPlay by displaying a custom UI.",
            zipFilename: "carplay-integrating-carplay-with-your-music-app.zip",
            webURL: "https://developer.apple.com/documentation/CarPlay/integrating-carplay-with-your-music-app"
        ),
        SampleCodeEntry(
            title: "Integrating CarPlay with Your Navigation App",
            url: "/documentation/CarPlay/integrating-carplay-with-your-navigation-app",
            framework: "CarPlay",
            description: "Configure your navigation app to work with CarPlay by displaying your custom map and directions.",
            zipFilename: "carplay-integrating-carplay-with-your-navigation-app.zip",
            webURL: "https://developer.apple.com/documentation/CarPlay/integrating-carplay-with-your-navigation-app"
        ),
        SampleCodeEntry(
            title: "Integrating CarPlay with your quick-ordering app",
            url: "/documentation/CarPlay/integrating-carplay-with-your-quick-ordering-app",
            framework: "CarPlay",
            description: "Configure your food-ordering app to work with CarPlay.",
            zipFilename: "carplay-integrating-carplay-with-your-quick-ordering-app.zip",
            webURL: "https://developer.apple.com/documentation/CarPlay/integrating-carplay-with-your-quick-ordering-app"
        ),
        SampleCodeEntry(
            title: "Creating a data visualization dashboard with Swift Charts",
            url: "/documentation/Charts/creating-a-data-visualization-dashboard-with-swift-charts",
            framework: "Charts",
            description: "Visualize an entire data collection efficiently by instantiating a single vectorized plot in Swift Charts.",
            zipFilename: "charts-creating-a-data-visualization-dashboard-with-swift-charts.zip",
            webURL: "https://developer.apple.com/documentation/Charts/creating-a-data-visualization-dashboard-with-swift-charts"
        ),
        SampleCodeEntry(
            title: "Visualizing your app’s data",
            url: "/documentation/Charts/visualizing-your-app-s-data",
            framework: "Charts",
            description: "Build complex and interactive charts using Swift Charts.",
            zipFilename: "charts-visualizing-your-app-s-data.zip",
            webURL: "https://developer.apple.com/documentation/Charts/visualizing-your-app-s-data"
        ),
        SampleCodeEntry(
            title: "Editing Spatial Audio with an audio mix",
            url: "/documentation/Cinematic/editing-spatial-audio-with-an-audio-mix",
            framework: "Cinematic",
            description: "Add Spatial Audio editing capabilities with the Audio Mix API in the Cinematic framework.",
            zipFilename: "cinematic-editing-spatial-audio-with-an-audio-mix.zip",
            webURL: "https://developer.apple.com/documentation/Cinematic/editing-spatial-audio-with-an-audio-mix"
        ),
        SampleCodeEntry(
            title: "Playing and editing Cinematic mode video",
            url: "/documentation/Cinematic/playing-and-editing-cinematic-mode-video",
            framework: "Cinematic",
            description: "Play and edit Cinematic mode video with an adjustable depth of field and focus points.",
            zipFilename: "cinematic-playing-and-editing-cinematic-mode-video.zip",
            webURL: "https://developer.apple.com/documentation/Cinematic/playing-and-editing-cinematic-mode-video"
        ),
        SampleCodeEntry(
            title: "Incorporating ClassKit into an Educational App",
            url: "/documentation/ClassKit/incorporating-classkit-into-an-educational-app",
            framework: "ClassKit",
            description: "Walk through the process of setting up assignments and recording student progress.",
            zipFilename: "classkit-incorporating-classkit-into-an-educational-app.zip",
            webURL: "https://developer.apple.com/documentation/ClassKit/incorporating-classkit-into-an-educational-app"
        ),
        SampleCodeEntry(
            title: "Creating and updating a complication’s timeline",
            url: "/documentation/ClockKit/creating-and-updating-a-complication-s-timeline",
            framework: "ClockKit",
            description: "Create complications that batch-load a timeline of future entries and run periodic background sessions to update the timeline.",
            zipFilename: "clockkit-creating-and-updating-a-complication-s-timeline.zip",
            webURL: "https://developer.apple.com/documentation/ClockKit/creating-and-updating-a-complication-s-timeline"
        ),
        SampleCodeEntry(
            title: "Displaying essential information on a watch face",
            url: "/documentation/ClockKit/displaying-essential-information-on-a-watch-face",
            framework: "ClockKit",
            description: "Implement complications in a watch app to display essential information on a watch face.",
            zipFilename: "clockkit-displaying-essential-information-on-a-watch-face.zip",
            webURL: "https://developer.apple.com/documentation/ClockKit/displaying-essential-information-on-a-watch-face"
        ),
        SampleCodeEntry(
            title: "Providing Multiple Complications",
            url: "/documentation/ClockKit/providing-multiple-complications",
            framework: "ClockKit",
            description: "Present multiple complications for a single complication family using descriptors.",
            zipFilename: "clockkit-providing-multiple-complications.zip",
            webURL: "https://developer.apple.com/documentation/ClockKit/providing-multiple-complications"
        ),
        SampleCodeEntry(
            title: "Sharing CloudKit Data with Other iCloud Users",
            url: "/documentation/CloudKit/sharing-cloudkit-data-with-other-icloud-users",
            framework: "CloudKit",
            description: "Create and share private CloudKit data with other users by implementing the sharing UI.",
            zipFilename: "cloudkit-sharing-cloudkit-data-with-other-icloud-users.zip",
            webURL: "https://developer.apple.com/documentation/CloudKit/sharing-cloudkit-data-with-other-icloud-users"
        ),
        SampleCodeEntry(
            title: "Interacting with virtual content blended with passthrough",
            url: "/documentation/CompositorServices/interacting-with-virtual-content-blended-with-passthrough",
            framework: "CompositorServices",
            description: "Present a mixed immersion style space to draw content in a person’s surroundings, and choose how upper limbs appear with respect to rendered content.",
            zipFilename: "compositorservices-interacting-with-virtual-content-blended-with-passthrough.zip",
            webURL: "https://developer.apple.com/documentation/CompositorServices/interacting-with-virtual-content-blended-with-passthrough"
        ),
        SampleCodeEntry(
            title: "Rendering hover effects in Metal immersive apps",
            url: "/documentation/CompositorServices/rendering_hover_effects_in_metal_immersive_apps",
            framework: "CompositorServices",
            description: "Change the appearance of a rendered onscreen element when a player gazes at it.",
            zipFilename: "compositorservices-rendering_hover_effects_in_metal_immersive_apps.zip",
            webURL: "https://developer.apple.com/documentation/CompositorServices/rendering_hover_effects_in_metal_immersive_apps"
        ),
        SampleCodeEntry(
            title: "Accessing a person’s contact data using Contacts and ContactsUI",
            url: "/documentation/Contacts/accessing-a-person-s-contact-data-using-contacts-and-contactsui",
            framework: "Contacts",
            description: "Allow people to grant your app access to contact data by adding the Contact access button and Contact access picker to your app.",
            zipFilename: "contacts-accessing-a-person-s-contact-data-using-contacts-and-contactsui.zip",
            webURL: "https://developer.apple.com/documentation/Contacts/accessing-a-person-s-contact-data-using-contacts-and-contactsui"
        ),
        SampleCodeEntry(
            title: "Building an Audio Server Plug-in and Driver Extension",
            url: "/documentation/CoreAudio/building-an-audio-server-plug-in-and-driver-extension",
            framework: "CoreAudio",
            description: "Create a plug-in and driver extension to support an audio device in macOS.",
            zipFilename: "coreaudio-building-an-audio-server-plug-in-and-driver-extension.zip",
            webURL: "https://developer.apple.com/documentation/CoreAudio/building-an-audio-server-plug-in-and-driver-extension"
        ),
        SampleCodeEntry(
            title: "Capturing system audio with Core Audio taps",
            url: "/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps",
            framework: "CoreAudio",
            description: "Use a Core Audio tap to capture outgoing audio from a process or group of processes.",
            zipFilename: "coreaudio-capturing-system-audio-with-core-audio-taps.zip",
            webURL: "https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps"
        ),
        SampleCodeEntry(
            title: "Creating an Audio Server Driver Plug-in",
            url: "/documentation/CoreAudio/creating-an-audio-server-driver-plug-in",
            framework: "CoreAudio",
            description: "Build a virtual audio device by creating a custom driver plug-in.",
            zipFilename: "coreaudio-creating-an-audio-server-driver-plug-in.zip",
            webURL: "https://developer.apple.com/documentation/CoreAudio/creating-an-audio-server-driver-plug-in"
        ),
        SampleCodeEntry(
            title: "Transferring Data Between Bluetooth Low Energy Devices",
            url: "/documentation/CoreBluetooth/transferring-data-between-bluetooth-low-energy-devices",
            framework: "CoreBluetooth",
            description: "Create a Bluetooth low energy central and peripheral device, and allow them to discover each other and exchange data.",
            zipFilename: "corebluetooth-transferring-data-between-bluetooth-low-energy-devices.zip",
            webURL: "https://developer.apple.com/documentation/CoreBluetooth/transferring-data-between-bluetooth-low-energy-devices"
        ),
        SampleCodeEntry(
            title: "Using Core Bluetooth Classic",
            url: "/documentation/CoreBluetooth/using-core-bluetooth-classic",
            framework: "CoreBluetooth",
            description: "Discover and communicate with a Bluetooth Classic device by using the Core Bluetooth APIs.",
            zipFilename: "corebluetooth-using-core-bluetooth-classic.zip",
            webURL: "https://developer.apple.com/documentation/CoreBluetooth/using-core-bluetooth-classic"
        ),
        SampleCodeEntry(
            title: "Adopting SwiftData for a Core Data app",
            url: "/documentation/CoreData/adopting-swiftdata-for-a-core-data-app",
            framework: "CoreData",
            description: "Persist data in your app intuitively with the Swift native persistence framework.",
            zipFilename: "coredata-adopting-swiftdata-for-a-core-data-app.zip",
            webURL: "https://developer.apple.com/documentation/CoreData/adopting-swiftdata-for-a-core-data-app"
        ),
        SampleCodeEntry(
            title: "Handling Different Data Types in Core Data",
            url: "/documentation/CoreData/handling-different-data-types-in-core-data",
            framework: "CoreData",
            description: "Create, store, and present records for a variety of data types.",
            zipFilename: "coredata-handling-different-data-types-in-core-data.zip",
            webURL: "https://developer.apple.com/documentation/CoreData/handling-different-data-types-in-core-data"
        ),
        SampleCodeEntry(
            title: "Linking Data Between Two Core Data Stores",
            url: "/documentation/CoreData/linking-data-between-two-core-data-stores",
            framework: "CoreData",
            description: "Organize data in two different stores and implement a link between them.",
            zipFilename: "coredata-linking-data-between-two-core-data-stores.zip",
            webURL: "https://developer.apple.com/documentation/CoreData/linking-data-between-two-core-data-stores"
        ),
        SampleCodeEntry(
            title: "Sharing Core Data objects between iCloud users",
            url: "/documentation/CoreData/sharing-core-data-objects-between-icloud-users",
            framework: "CoreData",
            description: "Use Core Data and CloudKit to synchronize data between devices of an iCloud user and share data between different iCloud users.",
            zipFilename: "coredata-sharing-core-data-objects-between-icloud-users.zip",
            webURL: "https://developer.apple.com/documentation/CoreData/sharing-core-data-objects-between-icloud-users"
        ),
        SampleCodeEntry(
            title: "Showcase App Data in Spotlight",
            url: "/documentation/CoreData/showcase-app-data-in-spotlight",
            framework: "CoreData",
            description: "Index app data so users can find it by using Spotlight search.",
            zipFilename: "coredata-showcase-app-data-in-spotlight.zip",
            webURL: "https://developer.apple.com/documentation/CoreData/showcase-app-data-in-spotlight"
        ),
        SampleCodeEntry(
            title: "Synchronizing a local store to the cloud",
            url: "/documentation/CoreData/synchronizing-a-local-store-to-the-cloud",
            framework: "CoreData",
            description: "Share data between a user’s devices and other iCloud users.",
            zipFilename: "coredata-synchronizing-a-local-store-to-the-cloud.zip",
            webURL: "https://developer.apple.com/documentation/CoreData/synchronizing-a-local-store-to-the-cloud"
        ),
        SampleCodeEntry(
            title: "Delivering Rich App Experiences with Haptics",
            url: "/documentation/CoreHaptics/delivering-rich-app-experiences-with-haptics",
            framework: "CoreHaptics",
            description: "Enhance your app’s experience by incorporating haptic and sound feedback into key interactive moments.",
            zipFilename: "corehaptics-delivering-rich-app-experiences-with-haptics.zip",
            webURL: "https://developer.apple.com/documentation/CoreHaptics/delivering-rich-app-experiences-with-haptics"
        ),
        SampleCodeEntry(
            title: "Playing Collision-Based Haptic Patterns",
            url: "/documentation/CoreHaptics/playing-collision-based-haptic-patterns",
            framework: "CoreHaptics",
            description: "Play a custom haptic pattern whose strength depends on an object’s collision speed.",
            zipFilename: "corehaptics-playing-collision-based-haptic-patterns.zip",
            webURL: "https://developer.apple.com/documentation/CoreHaptics/playing-collision-based-haptic-patterns"
        ),
        SampleCodeEntry(
            title: "Playing Haptics on Game Controllers",
            url: "/documentation/CoreHaptics/playing-haptics-on-game-controllers",
            framework: "CoreHaptics",
            description: "Add haptic feedback to supported game controllers by using Core Haptics.",
            zipFilename: "corehaptics-playing-haptics-on-game-controllers.zip",
            webURL: "https://developer.apple.com/documentation/CoreHaptics/playing-haptics-on-game-controllers"
        ),
        SampleCodeEntry(
            title: "Playing a Custom Haptic Pattern from a File",
            url: "/documentation/CoreHaptics/playing-a-custom-haptic-pattern-from-a-file",
            framework: "CoreHaptics",
            description: "Sample predesigned Apple Haptic Audio Pattern files, and learn how to play your own.",
            zipFilename: "corehaptics-playing-a-custom-haptic-pattern-from-a-file.zip",
            webURL: "https://developer.apple.com/documentation/CoreHaptics/playing-a-custom-haptic-pattern-from-a-file"
        ),
        SampleCodeEntry(
            title: "Updating Continuous and Transient Haptic Parameters in Real Time",
            url: "/documentation/CoreHaptics/updating-continuous-and-transient-haptic-parameters-in-real-time",
            framework: "CoreHaptics",
            description: "Generate continuous and transient haptic patterns in response to user touch.",
            zipFilename: "corehaptics-updating-continuous-and-transient-haptic-parameters-in-real-time.zip",
            webURL: "https://developer.apple.com/documentation/CoreHaptics/updating-continuous-and-transient-haptic-parameters-in-real-time"
        ),
        SampleCodeEntry(
            title: "Generating an animation with a Core Image Render Destination",
            url: "/documentation/CoreImage/generating-an-animation-with-a-core-image-render-destination",
            framework: "CoreImage",
            description: "Animate a filtered image to a Metal view in a SwiftUI app using a Core Image Render Destination.",
            zipFilename: "coreimage-generating-an-animation-with-a-core-image-render-destination.zip",
            webURL: "https://developer.apple.com/documentation/CoreImage/generating-an-animation-with-a-core-image-render-destination"
        ),
        SampleCodeEntry(
            title: "Adopting live updates in Core Location",
            url: "/documentation/CoreLocation/adopting-live-updates-in-core-location",
            framework: "CoreLocation",
            description: "Simplify location delivery using asynchronous events in Swift.",
            zipFilename: "corelocation-adopting-live-updates-in-core-location.zip",
            webURL: "https://developer.apple.com/documentation/CoreLocation/adopting-live-updates-in-core-location"
        ),
        SampleCodeEntry(
            title: "Monitoring location changes with Core Location",
            url: "/documentation/CoreLocation/monitoring-location-changes-with-core-location",
            framework: "CoreLocation",
            description: "Define boundaries and act on user location updates.",
            zipFilename: "corelocation-monitoring-location-changes-with-core-location.zip",
            webURL: "https://developer.apple.com/documentation/CoreLocation/monitoring-location-changes-with-core-location"
        ),
        SampleCodeEntry(
            title: "Ranging for Beacons",
            url: "/documentation/CoreLocation/ranging-for-beacons",
            framework: "CoreLocation",
            description: "Configure a device to act as a beacon and to detect surrounding beacons.",
            zipFilename: "corelocation-ranging-for-beacons.zip",
            webURL: "https://developer.apple.com/documentation/CoreLocation/ranging-for-beacons"
        ),
        SampleCodeEntry(
            title: "Sharing Your Location to Find a Park",
            url: "/documentation/CoreLocationUI/sharing-your-location-to-find-a-park",
            framework: "CoreLocationUI",
            description: "Ask for location access using a customizable location button.###",
            zipFilename: "corelocationui-sharing-your-location-to-find-a-park.zip",
            webURL: "https://developer.apple.com/documentation/CoreLocationUI/sharing-your-location-to-find-a-park"
        ),
        SampleCodeEntry(
            title: "Incorporating MIDI 2 into your apps",
            url: "/documentation/CoreMIDI/incorporating-midi-2-into-your-apps",
            framework: "CoreMIDI",
            description: "Add precision and improve musical control for your MIDI apps.",
            zipFilename: "coremidi-incorporating-midi-2-into-your-apps.zip",
            webURL: "https://developer.apple.com/documentation/CoreMIDI/incorporating-midi-2-into-your-apps"
        ),
        SampleCodeEntry(
            title: "Classifying Images with Vision and Core ML",
            url: "/documentation/CoreML/classifying-images-with-vision-and-core-ml",
            framework: "CoreML",
            description: "Crop and scale photos using the Vision framework and classify them with a Core ML model.",
            zipFilename: "coreml-classifying-images-with-vision-and-core-ml.zip",
            webURL: "https://developer.apple.com/documentation/CoreML/classifying-images-with-vision-and-core-ml"
        ),
        SampleCodeEntry(
            title: "Detecting human body poses in an image",
            url: "/documentation/CoreML/detecting-human-body-poses-in-an-image",
            framework: "CoreML",
            description: "Locate people and the stance of their bodies by analyzing an image with a PoseNet model.",
            zipFilename: "coreml-detecting-human-body-poses-in-an-image.zip",
            webURL: "https://developer.apple.com/documentation/CoreML/detecting-human-body-poses-in-an-image"
        ),
        SampleCodeEntry(
            title: "Finding answers to questions in a text document",
            url: "/documentation/CoreML/finding-answers-to-questions-in-a-text-document",
            framework: "CoreML",
            description: "Locate relevant passages in a document by asking the Bidirectional Encoder Representations from Transformers (BERT) model a question.",
            zipFilename: "coreml-finding-answers-to-questions-in-a-text-document.zip",
            webURL: "https://developer.apple.com/documentation/CoreML/finding-answers-to-questions-in-a-text-document"
        ),
        SampleCodeEntry(
            title: "Integrating a Core ML Model into Your App",
            url: "/documentation/CoreML/integrating-a-core-ml-model-into-your-app",
            framework: "CoreML",
            description: "Add a simple model to an app, pass input data to the model, and process the model’s predictions.",
            zipFilename: "coreml-integrating-a-core-ml-model-into-your-app.zip",
            webURL: "https://developer.apple.com/documentation/CoreML/integrating-a-core-ml-model-into-your-app"
        ),
        SampleCodeEntry(
            title: "Personalizing a Model with On-Device Updates",
            url: "/documentation/CoreML/personalizing-a-model-with-on-device-updates",
            framework: "CoreML",
            description: "Modify an updatable Core ML model by running an update task with labeled data.",
            zipFilename: "coreml-personalizing-a-model-with-on-device-updates.zip",
            webURL: "https://developer.apple.com/documentation/CoreML/personalizing-a-model-with-on-device-updates"
        ),
        SampleCodeEntry(
            title: "Understanding a Dice Roll with Vision and Object Detection",
            url: "/documentation/CoreML/understanding-a-dice-roll-with-vision-and-object-detection",
            framework: "CoreML",
            description: "Detect dice position and values shown in a camera frame, and determine the end of a roll by leveraging a dice detection model.",
            zipFilename: "coreml-understanding-a-dice-roll-with-vision-and-object-detection.zip",
            webURL: "https://developer.apple.com/documentation/CoreML/understanding-a-dice-roll-with-vision-and-object-detection"
        ),
        SampleCodeEntry(
            title: "Using Core ML for semantic image segmentation",
            url: "/documentation/CoreML/using-core-ml-for-semantic-image-segmentation",
            framework: "CoreML",
            description: "Identify multiple objects in an image by using the DEtection TRansformer image-segmentation model.###",
            zipFilename: "coreml-using-core-ml-for-semantic-image-segmentation.zip",
            webURL: "https://developer.apple.com/documentation/CoreML/using-core-ml-for-semantic-image-segmentation"
        ),
        SampleCodeEntry(
            title: "Getting motion-activity data from headphones",
            url: "/documentation/CoreMotion/getting-motion-activity-data-from-headphones",
            framework: "CoreMotion",
            description: "Configure your app to listen for motion-activity changes from headphones.",
            zipFilename: "coremotion-getting-motion-activity-data-from-headphones.zip",
            webURL: "https://developer.apple.com/documentation/CoreMotion/getting-motion-activity-data-from-headphones"
        ),
        SampleCodeEntry(
            title: "Building an NFC Tag-Reader App",
            url: "/documentation/CoreNFC/building-an-nfc-tag-reader-app",
            framework: "CoreNFC",
            description: "Read NFC tags with NDEF messages in your app.",
            zipFilename: "corenfc-building-an-nfc-tag-reader-app.zip",
            webURL: "https://developer.apple.com/documentation/CoreNFC/building-an-nfc-tag-reader-app"
        ),
        SampleCodeEntry(
            title: "Creating NFC Tags from Your iPhone",
            url: "/documentation/CoreNFC/creating-nfc-tags-from-your-iphone",
            framework: "CoreNFC",
            description: "Save data to tags, and interact with them using native tag protocols.",
            zipFilename: "corenfc-creating-nfc-tags-from-your-iphone.zip",
            webURL: "https://developer.apple.com/documentation/CoreNFC/creating-nfc-tags-from-your-iphone"
        ),
        SampleCodeEntry(
            title: "Creating a model from tabular data",
            url: "/documentation/CreateML/creating-a-model-from-tabular-data",
            framework: "CreateML",
            description: "Train a machine learning model by using Core ML to import and manage tabular data.",
            zipFilename: "createml-creating-a-model-from-tabular-data.zip",
            webURL: "https://developer.apple.com/documentation/CreateML/creating-a-model-from-tabular-data"
        ),
        SampleCodeEntry(
            title: "Detecting human actions in a live video feed",
            url: "/documentation/CreateML/detecting-human-actions-in-a-live-video-feed",
            framework: "CreateML",
            description: "Identify body movements by sending a person’s pose data from a series of video frames to an action-classification model.",
            zipFilename: "createml-detecting-human-actions-in-a-live-video-feed.zip",
            webURL: "https://developer.apple.com/documentation/CreateML/detecting-human-actions-in-a-live-video-feed"
        ),
        SampleCodeEntry(
            title: "Counting human body action repetitions in a live video feed",
            url: "/documentation/CreateMLComponents/counting-human-body-action-repetitions-in-a-live-video-feed",
            framework: "CreateMLComponents",
            description: "Use Create ML Components to analyze a series of video frames and count a person’s repetitive or periodic body movements.",
            zipFilename: "createmlcomponents-counting-human-body-action-repetitions-in-a-live-video-feed.zip",
            webURL: "https://developer.apple.com/documentation/CreateMLComponents/counting-human-body-action-repetitions-in-a-live-video-feed"
        ),
        SampleCodeEntry(
            title: "Enhancing your app’s privacy and security with quantum-secure workflows",
            url: "/documentation/CryptoKit/enhancing-your-app-s-privacy-and-security-with-quantum-secure-workflows",
            framework: "CryptoKit",
            description: "Use quantum-secure cryptography to protect your app from quantum attacks.",
            zipFilename: "cryptokit-enhancing-your-app-s-privacy-and-security-with-quantum-secure-workflows.zip",
            webURL: "https://developer.apple.com/documentation/CryptoKit/enhancing-your-app-s-privacy-and-security-with-quantum-secure-workflows"
        ),
        SampleCodeEntry(
            title: "Performing Common Cryptographic Operations",
            url: "/documentation/CryptoKit/performing-common-cryptographic-operations",
            framework: "CryptoKit",
            description: "Use CryptoKit to carry out operations like hashing, key generation, and encryption.",
            zipFilename: "cryptokit-performing-common-cryptographic-operations.zip",
            webURL: "https://developer.apple.com/documentation/CryptoKit/performing-common-cryptographic-operations"
        ),
        SampleCodeEntry(
            title: "Discovering a third-party media-streaming device",
            url: "/documentation/DeviceDiscoveryExtension/discovering-a-third-party-media-streaming-device",
            framework: "DeviceDiscoveryExtension",
            description: "Build an extension that streams media to a server app in iOS or macOS.",
            zipFilename: "devicediscoveryextension-discovering-a-third-party-media-streaming-device.zip",
            webURL: "https://developer.apple.com/documentation/DeviceDiscoveryExtension/discovering-a-third-party-media-streaming-device"
        ),
        SampleCodeEntry(
            title: "Controlling a DockKit accessory using your camera app",
            url: "/documentation/DockKit/controlling-a-dockkit-accessory-using-your-camera-app",
            framework: "DockKit",
            description: "Follow subjects in real time using an iPhone that you mount on a DockKit accessory.",
            zipFilename: "dockkit-controlling-a-dockkit-accessory-using-your-camera-app.zip",
            webURL: "https://developer.apple.com/documentation/DockKit/controlling-a-dockkit-accessory-using-your-camera-app"
        ),
        SampleCodeEntry(
            title: "Communicating between a DriverKit extension and a client app",
            url: "/documentation/DriverKit/communicating-between-a-driverkit-extension-and-a-client-app",
            framework: "DriverKit",
            description: "Send and receive different kinds of data securely by validating inputs and asynchronously by storing and using a callback.",
            zipFilename: "driverkit-communicating-between-a-driverkit-extension-and-a-client-app.zip",
            webURL: "https://developer.apple.com/documentation/DriverKit/communicating-between-a-driverkit-extension-and-a-client-app"
        ),
        SampleCodeEntry(
            title: "Monitoring System Events with Endpoint Security",
            url: "/documentation/EndpointSecurity/monitoring-system-events-with-endpoint-security",
            framework: "EndpointSecurity",
            description: "Receive notifications and authorization requests for sensitive operations by creating an Endpoint Security client for your app.",
            zipFilename: "endpointsecurity-monitoring-system-events-with-endpoint-security.zip",
            webURL: "https://developer.apple.com/documentation/EndpointSecurity/monitoring-system-events-with-endpoint-security"
        ),
        SampleCodeEntry(
            title: "Optimizing home electricity usage",
            url: "/documentation/EnergyKit/optimizing-home-electricity-usage",
            framework: "EnergyKit",
            description: "Shift electric vehicle charging schedules to times when the grid is cleaner and potentially less expensive.",
            zipFilename: "energykit-optimizing-home-electricity-usage.zip",
            webURL: "https://developer.apple.com/documentation/EnergyKit/optimizing-home-electricity-usage"
        ),
        SampleCodeEntry(
            title: "Accessing Calendar using EventKit and EventKitUI",
            url: "/documentation/EventKit/accessing-calendar-using-eventkit-and-eventkitui",
            framework: "EventKit",
            description: "Choose and implement the appropriate Calendar access level in your app.",
            zipFilename: "eventkit-accessing-calendar-using-eventkit-and-eventkitui.zip",
            webURL: "https://developer.apple.com/documentation/EventKit/accessing-calendar-using-eventkit-and-eventkitui"
        ),
        SampleCodeEntry(
            title: "Managing location-based reminders",
            url: "/documentation/EventKit/managing-location-based-reminders",
            framework: "EventKit",
            description: "Access reminders set up with geofence-enabled alarms on a person’s calendars.",
            zipFilename: "eventkit-managing-location-based-reminders.zip",
            webURL: "https://developer.apple.com/documentation/EventKit/managing-location-based-reminders"
        ),
        SampleCodeEntry(
            title: "Building an App to Notify Users of COVID-19 Exposure",
            url: "/documentation/ExposureNotification/building-an-app-to-notify-users-of-covid-19-exposure",
            framework: "ExposureNotification",
            description: "Inform people when they may have been exposed to COVID-19.",
            zipFilename: "exposurenotification-building-an-app-to-notify-users-of-covid-19-exposure.zip",
            webURL: "https://developer.apple.com/documentation/ExposureNotification/building-an-app-to-notify-users-of-covid-19-exposure"
        ),
        SampleCodeEntry(
            title: "Synchronizing files using file provider extensions",
            url: "/documentation/FileProvider/synchronizing-files-using-file-provider-extensions",
            framework: "FileProvider",
            description: "Make remote files available in macOS and iOS, and synchronize their states by using file provider extensions.",
            zipFilename: "fileprovider-synchronizing-files-using-file-provider-extensions.zip",
            webURL: "https://developer.apple.com/documentation/FileProvider/synchronizing-files-using-file-provider-extensions"
        ),
        SampleCodeEntry(
            title: "Implementing a background delivery extension",
            url: "/documentation/FinanceKit/implementing-a-background-delivery-extension",
            framework: "FinanceKit",
            description: "Receive up-to-date financial data in your app and its extensions by adding a background delivery extension.",
            zipFilename: "financekit-implementing-a-background-delivery-extension.zip",
            webURL: "https://developer.apple.com/documentation/FinanceKit/implementing-a-background-delivery-extension"
        ),
        SampleCodeEntry(
            title: "Building a resumable upload server with SwiftNIO",
            url: "/documentation/Foundation/building-a-resumable-upload-server-with-swiftnio",
            framework: "Foundation",
            description: "Support HTTP resumable upload protocol in SwiftNIO by translating resumable uploads to regular uploads.",
            zipFilename: "foundation-building-a-resumable-upload-server-with-swiftnio.zip",
            webURL: "https://developer.apple.com/documentation/Foundation/building-a-resumable-upload-server-with-swiftnio"
        ),
        SampleCodeEntry(
            title: "Continuing User Activities with Handoff",
            url: "/documentation/Foundation/continuing-user-activities-with-handoff",
            framework: "Foundation",
            description: "Define and manage which of your app’s activities can be continued between devices.",
            zipFilename: "foundation-continuing-user-activities-with-handoff.zip",
            webURL: "https://developer.apple.com/documentation/Foundation/continuing-user-activities-with-handoff"
        ),
        SampleCodeEntry(
            title: "Language Introspector",
            url: "/documentation/Foundation/language-introspector",
            framework: "Foundation",
            description: "Converts data into human-readable text using formatters and locales.",
            zipFilename: "foundation-language-introspector.zip",
            webURL: "https://developer.apple.com/documentation/Foundation/language-introspector"
        ),
        SampleCodeEntry(
            title: "Adding intelligent app features with generative models",
            url: "/documentation/FoundationModels/adding-intelligent-app-features-with-generative-models",
            framework: "FoundationModels",
            description: "Build robust apps with guided generation and tool calling by adopting the Foundation Models framework.",
            zipFilename: "foundationmodels-adding-intelligent-app-features-with-generative-models.zip",
            webURL: "https://developer.apple.com/documentation/FoundationModels/adding-intelligent-app-features-with-generative-models"
        ),
        SampleCodeEntry(
            title: "Generate dynamic game content with guided generation and tools",
            url: "/documentation/FoundationModels/generate-dynamic-game-content-with-guided-generation-and-tools",
            framework: "FoundationModels",
            description: "Make gameplay more lively with AI generated dialog and encounters personalized to the player.",
            zipFilename: "foundationmodels-generate-dynamic-game-content-with-guided-generation-and-tools.zip",
            webURL: "https://developer.apple.com/documentation/FoundationModels/generate-dynamic-game-content-with-guided-generation-and-tools"
        ),
        SampleCodeEntry(
            title: "Supporting Game Controllers",
            url: "/documentation/GameController/supporting-game-controllers",
            framework: "GameController",
            description: "Support a physical controller or add a virtual controller to enhance how people interact with your game through haptics, lighting, and motion sensing.###",
            zipFilename: "gamecontroller-supporting-game-controllers.zip",
            webURL: "https://developer.apple.com/documentation/GameController/supporting-game-controllers"
        ),
        SampleCodeEntry(
            title: "Adding Recurring Leaderboards to Your Game",
            url: "/documentation/GameKit/adding-recurring-leaderboards-to-your-game",
            framework: "GameKit",
            description: "Encourage competition in your games by adding leaderboards that have a duration and repeat.",
            zipFilename: "gamekit-adding-recurring-leaderboards-to-your-game.zip",
            webURL: "https://developer.apple.com/documentation/GameKit/adding-recurring-leaderboards-to-your-game"
        ),
        SampleCodeEntry(
            title: "Creating real-time games",
            url: "/documentation/GameKit/creating-real-time-games",
            framework: "GameKit",
            description: "Develop games where multiple players interact in real time.",
            zipFilename: "gamekit-creating-real-time-games.zip",
            webURL: "https://developer.apple.com/documentation/GameKit/creating-real-time-games"
        ),
        SampleCodeEntry(
            title: "Creating turn-based games",
            url: "/documentation/GameKit/creating-turn-based-games",
            framework: "GameKit",
            description: "Develop games where multiple players take turns and can exchange data while waiting for their turn.",
            zipFilename: "gamekit-creating-turn-based-games.zip",
            webURL: "https://developer.apple.com/documentation/GameKit/creating-turn-based-games"
        ),
        SampleCodeEntry(
            title: "Building a guessing game for visionOS",
            url: "/documentation/GroupActivities/building-a-guessing-game-for-visionos",
            framework: "GroupActivities",
            description: "Create a team-based guessing game for visionOS using Group Activities.",
            zipFilename: "groupactivities-building-a-guessing-game-for-visionos.zip",
            webURL: "https://developer.apple.com/documentation/GroupActivities/building-a-guessing-game-for-visionos"
        ),
        SampleCodeEntry(
            title: "Handling Keyboard Events from a Human Interface Device",
            url: "/documentation/HIDDriverKit/handling-keyboard-events-from-a-human-interface-device",
            framework: "HIDDriverKit",
            description: "Process keyboard-related data from a human interface device and dispatch events to the system.",
            zipFilename: "hiddriverkit-handling-keyboard-events-from-a-human-interface-device.zip",
            webURL: "https://developer.apple.com/documentation/HIDDriverKit/handling-keyboard-events-from-a-human-interface-device"
        ),
        SampleCodeEntry(
            title: "Handling Stylus Input from a Human Interface Device",
            url: "/documentation/HIDDriverKit/handling-stylus-input-from-a-human-interface-device",
            framework: "HIDDriverKit",
            description: "Process stylus-related input from a human interface device and dispatch events to the system.",
            zipFilename: "hiddriverkit-handling-stylus-input-from-a-human-interface-device.zip",
            webURL: "https://developer.apple.com/documentation/HIDDriverKit/handling-stylus-input-from-a-human-interface-device"
        ),
        SampleCodeEntry(
            title: "Accessing Data from a SMART Health Card",
            url: "/documentation/HealthKit/accessing-data-from-a-smart-health-card",
            framework: "HealthKit",
            description: "Query for and validate a verifiable clinical record.",
            zipFilename: "healthkit-accessing-data-from-a-smart-health-card.zip",
            webURL: "https://developer.apple.com/documentation/HealthKit/accessing-data-from-a-smart-health-card"
        ),
        SampleCodeEntry(
            title: "Accessing a User’s Clinical Records",
            url: "/documentation/HealthKit/accessing-a-user-s-clinical-records",
            framework: "HealthKit",
            description: "Request authorization to query HealthKit for a user’s clinical records and display them in your app.",
            zipFilename: "healthkit-accessing-a-user-s-clinical-records.zip",
            webURL: "https://developer.apple.com/documentation/HealthKit/accessing-a-user-s-clinical-records"
        ),
        SampleCodeEntry(
            title: "Build a workout app for Apple Watch",
            url: "/documentation/HealthKit/build-a-workout-app-for-apple-watch",
            framework: "HealthKit",
            description: "Create your own workout app, quickly and easily, with HealthKit and SwiftUI.",
            zipFilename: "healthkit-build-a-workout-app-for-apple-watch.zip",
            webURL: "https://developer.apple.com/documentation/HealthKit/build-a-workout-app-for-apple-watch"
        ),
        SampleCodeEntry(
            title: "Building a multidevice workout app",
            url: "/documentation/HealthKit/building-a-multidevice-workout-app",
            framework: "HealthKit",
            description: "Mirror a workout from a watchOS app to its companion iOS app, and perform bidirectional communication between them.",
            zipFilename: "healthkit-building-a-multidevice-workout-app.zip",
            webURL: "https://developer.apple.com/documentation/HealthKit/building-a-multidevice-workout-app"
        ),
        SampleCodeEntry(
            title: "Building a workout app for iPhone and iPad",
            url: "/documentation/HealthKit/building-a-workout-app-for-iphone-and-ipad",
            framework: "HealthKit",
            description: "Start a workout in iOS, control it from the Lock Screen with App Intents, and present the workout status with Live Activities.",
            zipFilename: "healthkit-building-a-workout-app-for-iphone-and-ipad.zip",
            webURL: "https://developer.apple.com/documentation/HealthKit/building-a-workout-app-for-iphone-and-ipad"
        ),
        SampleCodeEntry(
            title: "Creating a Mobility Health App",
            url: "/documentation/HealthKit/creating-a-mobility-health-app",
            framework: "HealthKit",
            description: "Create a health app that allows a clinical care team to send and receive mobility data.",
            zipFilename: "healthkit-creating-a-mobility-health-app.zip",
            webURL: "https://developer.apple.com/documentation/HealthKit/creating-a-mobility-health-app"
        ),
        SampleCodeEntry(
            title: "Logging symptoms associated with a medication",
            url: "/documentation/HealthKit/logging-symptoms-associated-with-a-medication",
            framework: "HealthKit",
            description: "Fetch medications and dose events from the HealthKit store, and create symptom samples to associate with them.",
            zipFilename: "healthkit-logging-symptoms-associated-with-a-medication.zip",
            webURL: "https://developer.apple.com/documentation/HealthKit/logging-symptoms-associated-with-a-medication"
        ),
        SampleCodeEntry(
            title: "Reading and Writing HealthKit Series Data",
            url: "/documentation/HealthKit/reading-and-writing-healthkit-series-data",
            framework: "HealthKit",
            description: "Share and read heartbeat and quantity series data using series builders and queries.",
            zipFilename: "healthkit-reading-and-writing-healthkit-series-data.zip",
            webURL: "https://developer.apple.com/documentation/HealthKit/reading-and-writing-healthkit-series-data"
        ),
        SampleCodeEntry(
            title: "Visualizing HealthKit State of Mind in visionOS",
            url: "/documentation/HealthKit/visualizing-healthkit-state-of-mind-in-visionos",
            framework: "HealthKit",
            description: "Incorporate HealthKit State of Mind into your app and visualize the data in visionOS.###",
            zipFilename: "healthkit-visualizing-healthkit-state-of-mind-in-visionos.zip",
            webURL: "https://developer.apple.com/documentation/HealthKit/visualizing-healthkit-state-of-mind-in-visionos"
        ),
        SampleCodeEntry(
            title: "Configuring a home automation device",
            url: "/documentation/HomeKit/configuring-a-home-automation-device",
            framework: "HomeKit",
            description: "Give users a familiar experience when they manage HomeKit accessories.",
            zipFilename: "homekit-configuring-a-home-automation-device.zip",
            webURL: "https://developer.apple.com/documentation/HomeKit/configuring-a-home-automation-device"
        ),
        SampleCodeEntry(
            title: "Interacting with a home automation network",
            url: "/documentation/HomeKit/interacting-with-a-home-automation-network",
            framework: "HomeKit",
            description: "Find all the automation accessories in the primary home and control their state.",
            zipFilename: "homekit-interacting-with-a-home-automation-network.zip",
            webURL: "https://developer.apple.com/documentation/HomeKit/interacting-with-a-home-automation-network"
        ),
        SampleCodeEntry(
            title: "Writing spatial photos",
            url: "/documentation/ImageIO/writing-spatial-photos",
            framework: "ImageIO",
            description: "Create spatial photos for visionOS by packaging a pair of left- and right-eye images as a stereo HEIC file with related spatial metadata.###",
            zipFilename: "imageio-writing-spatial-photos.zip",
            webURL: "https://developer.apple.com/documentation/ImageIO/writing-spatial-photos"
        ),
        SampleCodeEntry(
            title: "Authoring Apple Immersive Video",
            url: "/documentation/ImmersiveMediaSupport/authoring-apple-immersive-video",
            framework: "ImmersiveMediaSupport",
            description: "Prepare and package immersive video content for delivery.",
            zipFilename: "immersivemediasupport-authoring-apple-immersive-video.zip",
            webURL: "https://developer.apple.com/documentation/ImmersiveMediaSupport/authoring-apple-immersive-video"
        ),
        SampleCodeEntry(
            title: "Accessing Keychain Items with Face ID or Touch ID",
            url: "/documentation/LocalAuthentication/accessing-keychain-items-with-face-id-or-touch-id",
            framework: "LocalAuthentication",
            description: "Protect a keychain item with biometric authentication.",
            zipFilename: "localauthentication-accessing-keychain-items-with-face-id-or-touch-id.zip",
            webURL: "https://developer.apple.com/documentation/LocalAuthentication/accessing-keychain-items-with-face-id-or-touch-id"
        ),
        SampleCodeEntry(
            title: "Logging a User into Your App with Face ID or Touch ID",
            url: "/documentation/LocalAuthentication/logging-a-user-into-your-app-with-face-id-or-touch-id",
            framework: "LocalAuthentication",
            description: "Supplement your own authentication scheme with biometric authentication, making it easy for users to access sensitive parts of your app.",
            zipFilename: "localauthentication-logging-a-user-into-your-app-with-face-id-or-touch-id.zip",
            webURL: "https://developer.apple.com/documentation/LocalAuthentication/logging-a-user-into-your-app-with-face-id-or-touch-id"
        ),
        SampleCodeEntry(
            title: "Creating a MIDI device driver",
            url: "/documentation/MIDIDriverKit/creating-a-midi-device-driver",
            framework: "MIDIDriverKit",
            description: "Implement a configurable virtual MIDI driver as a driver extension that runs in user space in macOS and iPadOS.",
            zipFilename: "mididriverkit-creating-a-midi-device-driver.zip",
            webURL: "https://developer.apple.com/documentation/MIDIDriverKit/creating-a-midi-device-driver"
        ),
        SampleCodeEntry(
            title: "Build Mail App Extensions",
            url: "/documentation/MailKit/build-mail-app-extensions",
            framework: "MailKit",
            description: "Create app extensions that block content, perform message and composing actions, and help message security.",
            zipFilename: "mailkit-build-mail-app-extensions.zip",
            webURL: "https://developer.apple.com/documentation/MailKit/build-mail-app-extensions"
        ),
        SampleCodeEntry(
            title: "Annotating a Map with Custom Data",
            url: "/documentation/MapKit/annotating-a-map-with-custom-data",
            framework: "MapKit",
            description: "Annotate a map with location-specific data using default and customized annotation views and callouts.",
            zipFilename: "mapkit-annotating-a-map-with-custom-data.zip",
            webURL: "https://developer.apple.com/documentation/MapKit/annotating-a-map-with-custom-data"
        ),
        SampleCodeEntry(
            title: "Decluttering a Map with MapKit Annotation Clustering",
            url: "/documentation/MapKit/decluttering-a-map-with-mapkit-annotation-clustering",
            framework: "MapKit",
            description: "Enhance the readability of a map by replacing overlapping annotations with a clustering annotation view.",
            zipFilename: "mapkit-decluttering-a-map-with-mapkit-annotation-clustering.zip",
            webURL: "https://developer.apple.com/documentation/MapKit/decluttering-a-map-with-mapkit-annotation-clustering"
        ),
        SampleCodeEntry(
            title: "Displaying an Indoor Map",
            url: "/documentation/MapKit/displaying-an-indoor-map",
            framework: "MapKit",
            description: "Use the Indoor Mapping Data Format (IMDF) to show an indoor map with custom overlays and points of interest.",
            zipFilename: "mapkit-displaying-an-indoor-map.zip",
            webURL: "https://developer.apple.com/documentation/MapKit/displaying-an-indoor-map"
        ),
        SampleCodeEntry(
            title: "Displaying an updating path of a user’s location history",
            url: "/documentation/MapKit/displaying-an-updating-path-of-a-user-s-location-history",
            framework: "MapKit",
            description: "Continually update a MapKit overlay displaying the path a user travels.",
            zipFilename: "mapkit-displaying-an-updating-path-of-a-user-s-location-history.zip",
            webURL: "https://developer.apple.com/documentation/MapKit/displaying-an-updating-path-of-a-user-s-location-history"
        ),
        SampleCodeEntry(
            title: "Displaying overlays on a map",
            url: "/documentation/MapKit/displaying-overlays-on-a-map",
            framework: "MapKit",
            description: "Add regions of layered content to a map view.",
            zipFilename: "mapkit-displaying-overlays-on-a-map.zip",
            webURL: "https://developer.apple.com/documentation/MapKit/displaying-overlays-on-a-map"
        ),
        SampleCodeEntry(
            title: "Interacting with nearby points of interest",
            url: "/documentation/MapKit/interacting-with-nearby-points-of-interest",
            framework: "MapKit",
            description: "Provide automatic search completions for a partial search query, search the map for relevant locations nearby, and retrieve details for selected points of interest.",
            zipFilename: "mapkit-interacting-with-nearby-points-of-interest.zip",
            webURL: "https://developer.apple.com/documentation/MapKit/interacting-with-nearby-points-of-interest"
        ),
        SampleCodeEntry(
            title: "Searching, displaying, and navigating to places",
            url: "/documentation/MapKit/searching-displaying-and-navigating-to-places",
            framework: "MapKit",
            description: "Convert place information between coordinates and user-friendly place names, get cycling directions, and conveniently display formatted addresses.",
            zipFilename: "mapkit-searching-displaying-and-navigating-to-places.zip",
            webURL: "https://developer.apple.com/documentation/MapKit/searching-displaying-and-navigating-to-places"
        ),
        SampleCodeEntry(
            title: "Displaying Indoor Maps with MapKit JS",
            url: "/documentation/MapKitJS/displaying-indoor-maps-with-mapkit-js",
            framework: "MapKitJS",
            description: "Use the Indoor Mapping Data Format (IMDF) to show an indoor map with custom overlays and points of interest in your browser.",
            zipFilename: "mapkitjs-displaying-indoor-maps-with-mapkit-js.zip",
            webURL: "https://developer.apple.com/documentation/MapKitJS/displaying-indoor-maps-with-mapkit-js"
        ),
        SampleCodeEntry(
            title: "Responding to changes in the flashing lights setting",
            url: "/documentation/MediaAccessibility/responding-to-changes-in-the-flashing-lights-setting",
            framework: "MediaAccessibility",
            description: "Adjust your UI when a person chooses to dim flashing lights on their Apple device.",
            zipFilename: "mediaaccessibility-responding-to-changes-in-the-flashing-lights-setting.zip",
            webURL: "https://developer.apple.com/documentation/MediaAccessibility/responding-to-changes-in-the-flashing-lights-setting"
        ),
        SampleCodeEntry(
            title: "Becoming a now playable app",
            url: "/documentation/MediaPlayer/becoming-a-now-playable-app",
            framework: "MediaPlayer",
            description: "Ensure your app is eligible to become the Now Playing app by adopting best practices for providing Now Playing info and registering for remote command center actions.",
            zipFilename: "mediaplayer-becoming-a-now-playable-app.zip",
            webURL: "https://developer.apple.com/documentation/MediaPlayer/becoming-a-now-playable-app"
        ),
        SampleCodeEntry(
            title: "Creating a Sticker App with a Custom Layout",
            url: "/documentation/Messages/creating-a-sticker-app-with-a-custom-layout",
            framework: "Messages",
            description: "Expand on the Messages sticker app template to create an app with a customized user interface.",
            zipFilename: "messages-creating-a-sticker-app-with-a-custom-layout.zip",
            webURL: "https://developer.apple.com/documentation/Messages/creating-a-sticker-app-with-a-custom-layout"
        ),
        SampleCodeEntry(
            title: "IceCreamBuilder: Building an iMessage Extension",
            url: "/documentation/Messages/icecreambuilder-building-an-imessage-extension",
            framework: "Messages",
            description: "Allow users to collaborate on the design of ice cream sundae stickers.",
            zipFilename: "messages-icecreambuilder-building-an-imessage-extension.zip",
            webURL: "https://developer.apple.com/documentation/Messages/icecreambuilder-building-an-imessage-extension"
        ),
        SampleCodeEntry(
            title: "Accelerating ray tracing and motion blur using Metal",
            url: "/documentation/Metal/accelerating-ray-tracing-and-motion-blur-using-metal",
            framework: "Metal",
            description: "Generate ray-traced images with motion blur using GPU-based parallel processing.",
            zipFilename: "metal-accelerating-ray-tracing-and-motion-blur-using-metal.zip",
            webURL: "https://developer.apple.com/documentation/Metal/accelerating-ray-tracing-and-motion-blur-using-metal"
        ),
        SampleCodeEntry(
            title: "Accelerating ray tracing using Metal",
            url: "/documentation/Metal/accelerating-ray-tracing-using-metal",
            framework: "Metal",
            description: "Implement ray-traced rendering using GPU-based parallel processing.",
            zipFilename: "metal-accelerating-ray-tracing-using-metal.zip",
            webURL: "https://developer.apple.com/documentation/Metal/accelerating-ray-tracing-using-metal"
        ),
        SampleCodeEntry(
            title: "Achieving smooth frame rates with a Metal display link",
            url: "/documentation/Metal/achieving-smooth-frame-rates-with-a-metal-display-link",
            framework: "Metal",
            description: "Pace rendering with minimal input latency while providing essential information to the operating system for power-efficient rendering, thermal mitigation, and the scheduling of sustainable workloads.",
            zipFilename: "metal-achieving-smooth-frame-rates-with-a-metal-display-link.zip",
            webURL: "https://developer.apple.com/documentation/Metal/achieving-smooth-frame-rates-with-a-metal-display-link"
        ),
        SampleCodeEntry(
            title: "Adjusting the level of detail using Metal mesh shaders",
            url: "/documentation/Metal/adjusting-the-level-of-detail-using-metal-mesh-shaders",
            framework: "Metal",
            description: "Choose and render meshes with several levels of detail using object and mesh shaders.",
            zipFilename: "metal-adjusting-the-level-of-detail-using-metal-mesh-shaders.zip",
            webURL: "https://developer.apple.com/documentation/Metal/adjusting-the-level-of-detail-using-metal-mesh-shaders"
        ),
        SampleCodeEntry(
            title: "Calculating primitive visibility using depth testing",
            url: "/documentation/Metal/calculating-primitive-visibility-using-depth-testing",
            framework: "Metal",
            description: "Determine which pixels are visible in a scene by using a depth texture.",
            zipFilename: "metal-calculating-primitive-visibility-using-depth-testing.zip",
            webURL: "https://developer.apple.com/documentation/Metal/calculating-primitive-visibility-using-depth-testing"
        ),
        SampleCodeEntry(
            title: "Capturing Metal commands programmatically",
            url: "/documentation/Metal/capturing-metal-commands-programmatically",
            framework: "Metal",
            description: "Invoke a Metal frame capture from your app, then save the resulting GPU trace to a file or view it in Xcode.",
            zipFilename: "metal-capturing-metal-commands-programmatically.zip",
            webURL: "https://developer.apple.com/documentation/Metal/capturing-metal-commands-programmatically"
        ),
        SampleCodeEntry(
            title: "Control the ray tracing process using intersection queries",
            url: "/documentation/Metal/control-the-ray-tracing-process-using-intersection-queries",
            framework: "Metal",
            description: "Explicitly enumerate a ray’s intersections with acceleration structures by creating an intersection query object.",
            zipFilename: "metal-control-the-ray-tracing-process-using-intersection-queries.zip",
            webURL: "https://developer.apple.com/documentation/Metal/control-the-ray-tracing-process-using-intersection-queries"
        ),
        SampleCodeEntry(
            title: "Creating a 3D application with hydra rendering",
            url: "/documentation/Metal/creating-a-3d-application-with-hydra-rendering",
            framework: "Metal",
            description: "Build a 3D application that integrates with Hydra and USD.",
            zipFilename: "metal-creating-a-3d-application-with-hydra-rendering.zip",
            webURL: "https://developer.apple.com/documentation/Metal/creating-a-3d-application-with-hydra-rendering"
        ),
        SampleCodeEntry(
            title: "Creating a Metal dynamic library",
            url: "/documentation/Metal/creating-a-metal-dynamic-library",
            framework: "Metal",
            description: "Compile a library of shaders and write it to a file as a dynamically linked library.",
            zipFilename: "metal-creating-a-metal-dynamic-library.zip",
            webURL: "https://developer.apple.com/documentation/Metal/creating-a-metal-dynamic-library"
        ),
        SampleCodeEntry(
            title: "Creating a custom Metal view",
            url: "/documentation/Metal/creating-a-custom-metal-view",
            framework: "Metal",
            description: "Implement a lightweight view for Metal rendering that’s customized to your app’s needs.",
            zipFilename: "metal-creating-a-custom-metal-view.zip",
            webURL: "https://developer.apple.com/documentation/Metal/creating-a-custom-metal-view"
        ),
        SampleCodeEntry(
            title: "Creating and sampling textures",
            url: "/documentation/Metal/creating-and-sampling-textures",
            framework: "Metal",
            description: "Load image data into a texture and apply it to a quadrangle.",
            zipFilename: "metal-creating-and-sampling-textures.zip",
            webURL: "https://developer.apple.com/documentation/Metal/creating-and-sampling-textures"
        ),
        SampleCodeEntry(
            title: "Culling occluded geometry using the visibility result buffer",
            url: "/documentation/Metal/culling-occluded-geometry-using-the-visibility-result-buffer",
            framework: "Metal",
            description: "Draw a scene without rendering hidden geometry by checking whether each object in the scene is visible.",
            zipFilename: "metal-culling-occluded-geometry-using-the-visibility-result-buffer.zip",
            webURL: "https://developer.apple.com/documentation/Metal/culling-occluded-geometry-using-the-visibility-result-buffer"
        ),
        SampleCodeEntry(
            title: "Customizing a PyTorch operation",
            url: "/documentation/Metal/customizing-a-pytorch-operation",
            framework: "Metal",
            description: "Implement a custom operation in PyTorch that uses Metal kernels to improve performance.",
            zipFilename: "metal-customizing-a-pytorch-operation.zip",
            webURL: "https://developer.apple.com/documentation/Metal/customizing-a-pytorch-operation"
        ),
        SampleCodeEntry(
            title: "Customizing a TensorFlow operation",
            url: "/documentation/Metal/customizing-a-tensorflow-operation",
            framework: "Metal",
            description: "Implement a custom operation that uses Metal kernels to accelerate neural-network training performance.",
            zipFilename: "metal-customizing-a-tensorflow-operation.zip",
            webURL: "https://developer.apple.com/documentation/Metal/customizing-a-tensorflow-operation"
        ),
        SampleCodeEntry(
            title: "Customizing render pass setup",
            url: "/documentation/Metal/customizing-render-pass-setup",
            framework: "Metal",
            description: "Render into an offscreen texture by creating a custom render pass.",
            zipFilename: "metal-customizing-render-pass-setup.zip",
            webURL: "https://developer.apple.com/documentation/Metal/customizing-render-pass-setup"
        ),
        SampleCodeEntry(
            title: "Customizing shaders using function pointers and stitching",
            url: "/documentation/Metal/customizing-shaders-using-function-pointers-and-stitching",
            framework: "Metal",
            description: "Define custom shader behavior at runtime by creating functions from existing ones and preferentially linking to others in a dynamic library.",
            zipFilename: "metal-customizing-shaders-using-function-pointers-and-stitching.zip",
            webURL: "https://developer.apple.com/documentation/Metal/customizing-shaders-using-function-pointers-and-stitching"
        ),
        SampleCodeEntry(
            title: "Drawing a triangle with Metal 4",
            url: "/documentation/Metal/drawing-a-triangle-with-metal-4",
            framework: "Metal",
            description: "Render a colorful, rotating 2D triangle by running draw commands with a render pipeline on a GPU.",
            zipFilename: "metal-drawing-a-triangle-with-metal-4.zip",
            webURL: "https://developer.apple.com/documentation/Metal/drawing-a-triangle-with-metal-4"
        ),
        SampleCodeEntry(
            title: "Encoding argument buffers on the GPU",
            url: "/documentation/Metal/encoding-argument-buffers-on-the-gpu",
            framework: "Metal",
            description: "Use a compute pass to encode an argument buffer and access its arguments in a subsequent render pass.",
            zipFilename: "metal-encoding-argument-buffers-on-the-gpu.zip",
            webURL: "https://developer.apple.com/documentation/Metal/encoding-argument-buffers-on-the-gpu"
        ),
        SampleCodeEntry(
            title: "Encoding indirect command buffers on the CPU",
            url: "/documentation/Metal/encoding-indirect-command-buffers-on-the-cpu",
            framework: "Metal",
            description: "Reduce CPU overhead and simplify your command execution by reusing commands.",
            zipFilename: "metal-encoding-indirect-command-buffers-on-the-cpu.zip",
            webURL: "https://developer.apple.com/documentation/Metal/encoding-indirect-command-buffers-on-the-cpu"
        ),
        SampleCodeEntry(
            title: "Encoding indirect command buffers on the GPU",
            url: "/documentation/Metal/encoding-indirect-command-buffers-on-the-gpu",
            framework: "Metal",
            description: "Maximize CPU to GPU parallelization by generating render commands on the GPU.",
            zipFilename: "metal-encoding-indirect-command-buffers-on-the-gpu.zip",
            webURL: "https://developer.apple.com/documentation/Metal/encoding-indirect-command-buffers-on-the-gpu"
        ),
        SampleCodeEntry(
            title: "Implementing a multistage image filter using heaps and events",
            url: "/documentation/Metal/implementing-a-multistage-image-filter-using-heaps-and-events",
            framework: "Metal",
            description: "Use events to synchronize access to resources allocated on a heap.",
            zipFilename: "metal-implementing-a-multistage-image-filter-using-heaps-and-events.zip",
            webURL: "https://developer.apple.com/documentation/Metal/implementing-a-multistage-image-filter-using-heaps-and-events"
        ),
        SampleCodeEntry(
            title: "Implementing a multistage image filter using heaps and fences",
            url: "/documentation/Metal/implementing-a-multistage-image-filter-using-heaps-and-fences",
            framework: "Metal",
            description: "Use fences to synchronize access to resources allocated on a heap.",
            zipFilename: "metal-implementing-a-multistage-image-filter-using-heaps-and-fences.zip",
            webURL: "https://developer.apple.com/documentation/Metal/implementing-a-multistage-image-filter-using-heaps-and-fences"
        ),
        SampleCodeEntry(
            title: "Implementing order-independent transparency with image blocks",
            url: "/documentation/Metal/implementing-order-independent-transparency-with-image-blocks",
            framework: "Metal",
            description: "Draw overlapping, transparent surfaces in any order by using tile shaders and image blocks.",
            zipFilename: "metal-implementing-order-independent-transparency-with-image-blocks.zip",
            webURL: "https://developer.apple.com/documentation/Metal/implementing-order-independent-transparency-with-image-blocks"
        ),
        SampleCodeEntry(
            title: "Improving edge-rendering quality with multisample antialiasing (MSAA)",
            url: "/documentation/Metal/improving-edge-rendering-quality-with-multisample-antialiasing-msaa",
            framework: "Metal",
            description: "Apply MSAA to enhance the rendering of edges with custom resolve options and immediate and tile-based resolve paths.",
            zipFilename: "metal-improving-edge-rendering-quality-with-multisample-antialiasing-msaa.zip",
            webURL: "https://developer.apple.com/documentation/Metal/improving-edge-rendering-quality-with-multisample-antialiasing-msaa"
        ),
        SampleCodeEntry(
            title: "Loading textures and models using Metal fast resource loading",
            url: "/documentation/Metal/loading-textures-and-models-using-metal-fast-resource-loading",
            framework: "Metal",
            description: "Stream texture and buffer data directly from disk into Metal resources using fast resource loading.",
            zipFilename: "metal-loading-textures-and-models-using-metal-fast-resource-loading.zip",
            webURL: "https://developer.apple.com/documentation/Metal/loading-textures-and-models-using-metal-fast-resource-loading"
        ),
        SampleCodeEntry(
            title: "Managing groups of resources with argument buffers",
            url: "/documentation/Metal/managing-groups-of-resources-with-argument-buffers",
            framework: "Metal",
            description: "Create argument buffers to organize related resources.",
            zipFilename: "metal-managing-groups-of-resources-with-argument-buffers.zip",
            webURL: "https://developer.apple.com/documentation/Metal/managing-groups-of-resources-with-argument-buffers"
        ),
        SampleCodeEntry(
            title: "Migrating OpenGL code to Metal",
            url: "/documentation/Metal/migrating-opengl-code-to-metal",
            framework: "Metal",
            description: "Replace your app’s deprecated OpenGL code with Metal.",
            zipFilename: "metal-migrating-opengl-code-to-metal.zip",
            webURL: "https://developer.apple.com/documentation/Metal/migrating-opengl-code-to-metal"
        ),
        SampleCodeEntry(
            title: "Mixing Metal and OpenGL rendering in a view",
            url: "/documentation/Metal/mixing-metal-and-opengl-rendering-in-a-view",
            framework: "Metal",
            description: "Draw with Metal and OpenGL in the same view using an interoperable texture.",
            zipFilename: "metal-mixing-metal-and-opengl-rendering-in-a-view.zip",
            webURL: "https://developer.apple.com/documentation/Metal/mixing-metal-and-opengl-rendering-in-a-view"
        ),
        SampleCodeEntry(
            title: "Modern rendering with Metal",
            url: "/documentation/Metal/modern-rendering-with-metal",
            framework: "Metal",
            description: "Use advanced Metal features such as indirect command buffers, sparse textures, and variable rate rasterization to implement complex rendering techniques.",
            zipFilename: "metal-modern-rendering-with-metal.zip",
            webURL: "https://developer.apple.com/documentation/Metal/modern-rendering-with-metal"
        ),
        SampleCodeEntry(
            title: "Performing calculations on a GPU",
            url: "/documentation/Metal/performing-calculations-on-a-gpu",
            framework: "Metal",
            description: "Use Metal to find GPUs and perform calculations on them.",
            zipFilename: "metal-performing-calculations-on-a-gpu.zip",
            webURL: "https://developer.apple.com/documentation/Metal/performing-calculations-on-a-gpu"
        ),
        SampleCodeEntry(
            title: "Processing HDR images with Metal",
            url: "/documentation/Metal/processing-hdr-images-with-metal",
            framework: "Metal",
            description: "Implement a post-processing pipeline using the latest features on Apple GPUs.",
            zipFilename: "metal-processing-hdr-images-with-metal.zip",
            webURL: "https://developer.apple.com/documentation/Metal/processing-hdr-images-with-metal"
        ),
        SampleCodeEntry(
            title: "Processing a texture in a compute function",
            url: "/documentation/Metal/processing-a-texture-in-a-compute-function",
            framework: "Metal",
            description: "Create textures by running copy and dispatch commands in a compute pass on a GPU.",
            zipFilename: "metal-processing-a-texture-in-a-compute-function.zip",
            webURL: "https://developer.apple.com/documentation/Metal/processing-a-texture-in-a-compute-function"
        ),
        SampleCodeEntry(
            title: "Reading pixel data from a drawable texture",
            url: "/documentation/Metal/reading-pixel-data-from-a-drawable-texture",
            framework: "Metal",
            description: "Access texture data from the CPU by copying it to a buffer.",
            zipFilename: "metal-reading-pixel-data-from-a-drawable-texture.zip",
            webURL: "https://developer.apple.com/documentation/Metal/reading-pixel-data-from-a-drawable-texture"
        ),
        SampleCodeEntry(
            title: "Rendering a curve primitive in a ray tracing scene",
            url: "/documentation/Metal/rendering-a-curve-primitive-in-a-ray-tracing-scene",
            framework: "Metal",
            description: "Implement ray traced rendering using GPU-based parallel processing.",
            zipFilename: "metal-rendering-a-curve-primitive-in-a-ray-tracing-scene.zip",
            webURL: "https://developer.apple.com/documentation/Metal/rendering-a-curve-primitive-in-a-ray-tracing-scene"
        ),
        SampleCodeEntry(
            title: "Rendering a scene with deferred lighting in C++",
            url: "/documentation/Metal/rendering-a-scene-with-deferred-lighting-in-c++",
            framework: "Metal",
            description: "Avoid expensive lighting calculations by implementing a deferred lighting renderer optimized for immediate mode and tile-based deferred renderer GPUs.",
            zipFilename: "metal-rendering-a-scene-with-deferred-lighting-in-c++.zip",
            webURL: "https://developer.apple.com/documentation/Metal/rendering-a-scene-with-deferred-lighting-in-c++"
        ),
        SampleCodeEntry(
            title: "Rendering a scene with deferred lighting in Objective-C",
            url: "/documentation/Metal/rendering-a-scene-with-deferred-lighting-in-objective-c",
            framework: "Metal",
            description: "Avoid expensive lighting calculations by implementing a deferred lighting renderer optimized for immediate mode and tile-based deferred renderer GPUs.",
            zipFilename: "metal-rendering-a-scene-with-deferred-lighting-in-objective-c.zip",
            webURL: "https://developer.apple.com/documentation/Metal/rendering-a-scene-with-deferred-lighting-in-objective-c"
        ),
        SampleCodeEntry(
            title: "Rendering a scene with deferred lighting in Swift",
            url: "/documentation/Metal/rendering-a-scene-with-deferred-lighting-in-swift",
            framework: "Metal",
            description: "Avoid expensive lighting calculations by implementing a deferred lighting renderer optimized for immediate mode and tile-based deferred renderer GPUs.",
            zipFilename: "metal-rendering-a-scene-with-deferred-lighting-in-swift.zip",
            webURL: "https://developer.apple.com/documentation/Metal/rendering-a-scene-with-deferred-lighting-in-swift"
        ),
        SampleCodeEntry(
            title: "Rendering a scene with forward plus lighting using tile shaders",
            url: "/documentation/Metal/rendering-a-scene-with-forward-plus-lighting-using-tile-shaders",
            framework: "Metal",
            description: "Implement a forward plus renderer using the latest features on Apple GPUs.",
            zipFilename: "metal-rendering-a-scene-with-forward-plus-lighting-using-tile-shaders.zip",
            webURL: "https://developer.apple.com/documentation/Metal/rendering-a-scene-with-forward-plus-lighting-using-tile-shaders"
        ),
        SampleCodeEntry(
            title: "Rendering reflections in real time using ray tracing",
            url: "/documentation/Metal/rendering-reflections-in-real-time-using-ray-tracing",
            framework: "Metal",
            description: "Implement realistic real-time lighting by dynamically generating reflection maps by encoding a ray-tracing compute pass.",
            zipFilename: "metal-rendering-reflections-in-real-time-using-ray-tracing.zip",
            webURL: "https://developer.apple.com/documentation/Metal/rendering-reflections-in-real-time-using-ray-tracing"
        ),
        SampleCodeEntry(
            title: "Rendering reflections with fewer render passes",
            url: "/documentation/Metal/rendering-reflections-with-fewer-render-passes",
            framework: "Metal",
            description: "Use layer selection to reduce the number of render passes needed to generate an environment map.",
            zipFilename: "metal-rendering-reflections-with-fewer-render-passes.zip",
            webURL: "https://developer.apple.com/documentation/Metal/rendering-reflections-with-fewer-render-passes"
        ),
        SampleCodeEntry(
            title: "Rendering terrain dynamically with argument buffers",
            url: "/documentation/Metal/rendering-terrain-dynamically-with-argument-buffers",
            framework: "Metal",
            description: "Use argument buffers to render terrain in real time with a GPU-driven pipeline.",
            zipFilename: "metal-rendering-terrain-dynamically-with-argument-buffers.zip",
            webURL: "https://developer.apple.com/documentation/Metal/rendering-terrain-dynamically-with-argument-buffers"
        ),
        SampleCodeEntry(
            title: "Selecting device objects for compute processing",
            url: "/documentation/Metal/selecting-device-objects-for-compute-processing",
            framework: "Metal",
            description: "Switch dynamically between multiple GPUs to efficiently execute a compute-intensive simulation.",
            zipFilename: "metal-selecting-device-objects-for-compute-processing.zip",
            webURL: "https://developer.apple.com/documentation/Metal/selecting-device-objects-for-compute-processing"
        ),
        SampleCodeEntry(
            title: "Selecting device objects for graphics rendering",
            url: "/documentation/Metal/selecting-device-objects-for-graphics-rendering",
            framework: "Metal",
            description: "Switch dynamically between multiple GPUs to efficiently render to a display.",
            zipFilename: "metal-selecting-device-objects-for-graphics-rendering.zip",
            webURL: "https://developer.apple.com/documentation/Metal/selecting-device-objects-for-graphics-rendering"
        ),
        SampleCodeEntry(
            title: "Streaming large images with Metal sparse textures",
            url: "/documentation/Metal/streaming-large-images-with-metal-sparse-textures",
            framework: "Metal",
            description: "Limit texture memory usage for large textures by loading or unloading image detail on the basis of MIP and tile region.",
            zipFilename: "metal-streaming-large-images-with-metal-sparse-textures.zip",
            webURL: "https://developer.apple.com/documentation/Metal/streaming-large-images-with-metal-sparse-textures"
        ),
        SampleCodeEntry(
            title: "Supporting Simulator in a Metal app",
            url: "/documentation/Metal/supporting-simulator-in-a-metal-app",
            framework: "Metal",
            description: "Configure alternative render paths in your Metal app to enable running your app in Simulator.",
            zipFilename: "metal-supporting-simulator-in-a-metal-app.zip",
            webURL: "https://developer.apple.com/documentation/Metal/supporting-simulator-in-a-metal-app"
        ),
        SampleCodeEntry(
            title: "Synchronizing CPU and GPU work",
            url: "/documentation/Metal/synchronizing-cpu-and-gpu-work",
            framework: "Metal",
            description: "Avoid stalls between CPU and GPU work by using multiple instances of a resource.",
            zipFilename: "metal-synchronizing-cpu-and-gpu-work.zip",
            webURL: "https://developer.apple.com/documentation/Metal/synchronizing-cpu-and-gpu-work"
        ),
        SampleCodeEntry(
            title: "Using Metal to draw a view’s contents",
            url: "/documentation/Metal/using-metal-to-draw-a-view",
            framework: "Metal",
            description: "Create a MetalKit view and a render pass to draw the view’s contents.###",
            zipFilename: "metal-using-metal-to-draw-a-view.zip",
            webURL: "https://developer.apple.com/documentation/Metal/using-metal-to-draw-a-view"
        ),
        SampleCodeEntry(
            title: "Using argument buffers with resource heaps",
            url: "/documentation/Metal/using-argument-buffers-with-resource-heaps",
            framework: "Metal",
            description: "Reduce CPU overhead by using arrays inside argument buffers and combining them with resource heaps.",
            zipFilename: "metal-using-argument-buffers-with-resource-heaps.zip",
            webURL: "https://developer.apple.com/documentation/Metal/using-argument-buffers-with-resource-heaps"
        ),
        SampleCodeEntry(
            title: "Using function specialization to build pipeline variants",
            url: "/documentation/Metal/using-function-specialization-to-build-pipeline-variants",
            framework: "Metal",
            description: "Create pipelines for different levels of detail from a common shader source.",
            zipFilename: "metal-using-function-specialization-to-build-pipeline-variants.zip",
            webURL: "https://developer.apple.com/documentation/Metal/using-function-specialization-to-build-pipeline-variants"
        ),
        SampleCodeEntry(
            title: "Applying temporal antialiasing and upscaling using MetalFX",
            url: "/documentation/MetalFX/applying-temporal-antialiasing-and-upscaling-using-metalfx",
            framework: "MetalFX",
            description: "Reduce render workloads while increasing image detail with MetalFX.",
            zipFilename: "metalfx-applying-temporal-antialiasing-and-upscaling-using-metalfx.zip",
            webURL: "https://developer.apple.com/documentation/MetalFX/applying-temporal-antialiasing-and-upscaling-using-metalfx"
        ),
        SampleCodeEntry(
            title: "Training a Neural Network with Metal Performance Shaders",
            url: "/documentation/MetalPerformanceShaders/training-a-neural-network-with-metal-performance-shaders",
            framework: "MetalPerformanceShaders",
            description: "Use an MPS neural network graph to train a simple neural network digit classifier.",
            zipFilename: "metalperformanceshaders-training-a-neural-network-with-metal-performance-shaders.zip",
            webURL: "https://developer.apple.com/documentation/MetalPerformanceShaders/training-a-neural-network-with-metal-performance-shaders"
        ),
        SampleCodeEntry(
            title: "Adding custom functions to a shader graph",
            url: "/documentation/MetalPerformanceShadersGraph/adding-custom-functions-to-a-shader-graph",
            framework: "MetalPerformanceShadersGraph",
            description: "Run your own graph functions on the GPU by building the function programmatically.",
            zipFilename: "metalperformanceshadersgraph-adding-custom-functions-to-a-shader-graph.zip",
            webURL: "https://developer.apple.com/documentation/MetalPerformanceShadersGraph/adding-custom-functions-to-a-shader-graph"
        ),
        SampleCodeEntry(
            title: "Filtering images with MPSGraph FFT operations",
            url: "/documentation/MetalPerformanceShadersGraph/filtering-images-with-mpsgraph-fft-operations",
            framework: "MetalPerformanceShadersGraph",
            description: "Filter an image with MPSGraph fast Fourier transforms using the convolutional theorem.",
            zipFilename: "metalperformanceshadersgraph-filtering-images-with-mpsgraph-fft-operations.zip",
            webURL: "https://developer.apple.com/documentation/MetalPerformanceShadersGraph/filtering-images-with-mpsgraph-fft-operations"
        ),
        SampleCodeEntry(
            title: "Training a neural network using MPSGraph",
            url: "/documentation/MetalPerformanceShadersGraph/training-a-neural-network-using-mps-graph",
            framework: "MetalPerformanceShadersGraph",
            description: "Train a simple neural network digit classifier.",
            zipFilename: "metalperformanceshadersgraph-training-a-neural-network-using-mps-graph.zip",
            webURL: "https://developer.apple.com/documentation/MetalPerformanceShadersGraph/training-a-neural-network-using-mps-graph"
        ),
        SampleCodeEntry(
            title: "Finding devices with precision",
            url: "/documentation/NearbyInteraction/finding-devices-with-precision",
            framework: "NearbyInteraction",
            description: "Leverage the spatial awareness of ARKit and Apple Ultra Wideband Chips in your app to guide users to a nearby device.",
            zipFilename: "nearbyinteraction-finding-devices-with-precision.zip",
            webURL: "https://developer.apple.com/documentation/NearbyInteraction/finding-devices-with-precision"
        ),
        SampleCodeEntry(
            title: "Implementing Interactions Between Users in Close Proximity",
            url: "/documentation/NearbyInteraction/implementing-interactions-between-users-in-close-proximity",
            framework: "NearbyInteraction",
            description: "Enable devices to access relative positioning information.",
            zipFilename: "nearbyinteraction-implementing-interactions-between-users-in-close-proximity.zip",
            webURL: "https://developer.apple.com/documentation/NearbyInteraction/implementing-interactions-between-users-in-close-proximity"
        ),
        SampleCodeEntry(
            title: "Implementing proximity-based interactions between a phone and watch",
            url: "/documentation/NearbyInteraction/implementing-proximity-based-interactions-between-a-phone-and-watch",
            framework: "NearbyInteraction",
            description: "Interact with a nearby Apple Watch by measuring its distance to a paired iPhone.",
            zipFilename: "nearbyinteraction-implementing-proximity-based-interactions-between-a-phone-and-watch.zip",
            webURL: "https://developer.apple.com/documentation/NearbyInteraction/implementing-proximity-based-interactions-between-a-phone-and-watch"
        ),
        SampleCodeEntry(
            title: "Implementing spatial interactions with third-party accessories",
            url: "/documentation/NearbyInteraction/implementing-spatial-interactions-with-third-party-accessories",
            framework: "NearbyInteraction",
            description: "Establish a connection with a nearby accessory to receive periodic measurements of its distance from the user.",
            zipFilename: "nearbyinteraction-implementing-spatial-interactions-with-third-party-accessories.zip",
            webURL: "https://developer.apple.com/documentation/NearbyInteraction/implementing-spatial-interactions-with-third-party-accessories"
        ),
        SampleCodeEntry(
            title: "Building a custom peer-to-peer protocol",
            url: "/documentation/Network/building-a-custom-peer-to-peer-protocol",
            framework: "Network",
            description: "Use networking frameworks to create a custom protocol for playing a game across iOS, iPadOS, watchOS, and tvOS devices.",
            zipFilename: "network-building-a-custom-peer-to-peer-protocol.zip",
            webURL: "https://developer.apple.com/documentation/Network/building-a-custom-peer-to-peer-protocol"
        ),
        SampleCodeEntry(
            title: "Collecting Network Connection Metrics",
            url: "/documentation/Network/collecting-network-connection-metrics",
            framework: "Network",
            description: "Use reports to understand how DNS and protocol handshakes impact connection establishment.",
            zipFilename: "network-collecting-network-connection-metrics.zip",
            webURL: "https://developer.apple.com/documentation/Network/collecting-network-connection-metrics"
        ),
        SampleCodeEntry(
            title: "Implementing netcat with Network Framework",
            url: "/documentation/Network/implementing-netcat-with-network-framework",
            framework: "Network",
            description: "Build a simple `netcat` tool that establishes network connections and transfers data.",
            zipFilename: "network-implementing-netcat-with-network-framework.zip",
            webURL: "https://developer.apple.com/documentation/Network/implementing-netcat-with-network-framework"
        ),
        SampleCodeEntry(
            title: "Configuring a Wi-Fi accessory to join a network",
            url: "/documentation/NetworkExtension/configuring-a-wi-fi-accessory-to-join-a-network",
            framework: "NetworkExtension",
            description: "Associate an iOS device with an accessory’s network to deliver network configuration information.",
            zipFilename: "networkextension-configuring-a-wi-fi-accessory-to-join-a-network.zip",
            webURL: "https://developer.apple.com/documentation/NetworkExtension/configuring-a-wi-fi-accessory-to-join-a-network"
        ),
        SampleCodeEntry(
            title: "Filtering Network Traffic",
            url: "/documentation/NetworkExtension/filtering-network-traffic",
            framework: "NetworkExtension",
            description: "Use the Network Extension framework to allow or deny network connections.",
            zipFilename: "networkextension-filtering-network-traffic.zip",
            webURL: "https://developer.apple.com/documentation/NetworkExtension/filtering-network-traffic"
        ),
        SampleCodeEntry(
            title: "Filtering traffic by URL",
            url: "/documentation/NetworkExtension/filtering-traffic-by-url",
            framework: "NetworkExtension",
            description: "Perform fast and robust filtering of full URLs by managing URL filtering configurations.",
            zipFilename: "networkextension-filtering-traffic-by-url.zip",
            webURL: "https://developer.apple.com/documentation/NetworkExtension/filtering-traffic-by-url"
        ),
        SampleCodeEntry(
            title: "Receiving Voice and Text Communications on a Local Network",
            url: "/documentation/NetworkExtension/receiving-voice-and-text-communications-on-a-local-network",
            framework: "NetworkExtension",
            description: "Provide voice and text communication on a local network isolated from Apple Push Notification service by adopting Local Push Connectivity.",
            zipFilename: "networkextension-receiving-voice-and-text-communications-on-a-local-network.zip",
            webURL: "https://developer.apple.com/documentation/NetworkExtension/receiving-voice-and-text-communications-on-a-local-network"
        ),
        SampleCodeEntry(
            title: "Custom Graphics",
            url: "/documentation/PDFKit/custom-graphics",
            framework: "PDFKit",
            description: "Demonstrates adding a watermark to a PDF page.",
            zipFilename: "pdfkit-custom-graphics.zip",
            webURL: "https://developer.apple.com/documentation/PDFKit/custom-graphics"
        ),
        SampleCodeEntry(
            title: "PDF Widgets",
            url: "/documentation/PDFKit/pdf-widgets",
            framework: "PDFKit",
            description: "Demonstrates adding widgets—interactive form elements—to a PDF document.",
            zipFilename: "pdfkit-pdf-widgets.zip",
            webURL: "https://developer.apple.com/documentation/PDFKit/pdf-widgets"
        ),
        SampleCodeEntry(
            title: "Implementing Wallet Extensions",
            url: "/documentation/PassKit/implementing-wallet-extensions",
            framework: "PassKit",
            description: "Support adding an issued card to Apple Pay from directly within Apple Wallet using Wallet Extensions.",
            zipFilename: "passkit-implementing-wallet-extensions.zip",
            webURL: "https://developer.apple.com/documentation/PassKit/implementing-wallet-extensions"
        ),
        SampleCodeEntry(
            title: "Offering Apple Pay in Your App",
            url: "/documentation/PassKit/offering-apple-pay-in-your-app",
            framework: "PassKit",
            description: "Collect payments with iPhone and Apple Watch using Apple Pay.",
            zipFilename: "passkit-offering-apple-pay-in-your-app.zip",
            webURL: "https://developer.apple.com/documentation/PassKit/offering-apple-pay-in-your-app"
        ),
        SampleCodeEntry(
            title: "Configuring the PencilKit tool picker",
            url: "/documentation/PencilKit/configuring-the-pencilkit-tool-picker",
            framework: "PencilKit",
            description: "Incorporate a custom PencilKit tool picker with a variety of system and custom tools into a drawing app.",
            zipFilename: "pencilkit-configuring-the-pencilkit-tool-picker.zip",
            webURL: "https://developer.apple.com/documentation/PencilKit/configuring-the-pencilkit-tool-picker"
        ),
        SampleCodeEntry(
            title: "Customizing Scribble with Interactions",
            url: "/documentation/PencilKit/customizing-scribble-with-interactions",
            framework: "PencilKit",
            description: "Enable writing on a non-text-input view by adding interactions.",
            zipFilename: "pencilkit-customizing-scribble-with-interactions.zip",
            webURL: "https://developer.apple.com/documentation/PencilKit/customizing-scribble-with-interactions"
        ),
        SampleCodeEntry(
            title: "Drawing with PencilKit",
            url: "/documentation/PencilKit/drawing-with-pencilkit",
            framework: "PencilKit",
            description: "Add expressive, low-latency drawing to your app using PencilKit.",
            zipFilename: "pencilkit-drawing-with-pencilkit.zip",
            webURL: "https://developer.apple.com/documentation/PencilKit/drawing-with-pencilkit"
        ),
        SampleCodeEntry(
            title: "Inspecting, Modifying, and Constructing PencilKit Drawings",
            url: "/documentation/PencilKit/inspecting-modifying-and-constructing-pencilkit-drawings",
            framework: "PencilKit",
            description: "Score users’ ability to match PencilKit drawings generated from text, by accessing the strokes and points inside PencilKit drawings.",
            zipFilename: "pencilkit-inspecting-modifying-and-constructing-pencilkit-drawings.zip",
            webURL: "https://developer.apple.com/documentation/PencilKit/inspecting-modifying-and-constructing-pencilkit-drawings"
        ),
        SampleCodeEntry(
            title: "Bringing Photos picker to your SwiftUI app",
            url: "/documentation/PhotoKit/bringing-photos-picker-to-your-swiftui-app",
            framework: "PhotoKit",
            description: "Select media assets by using a Photos picker view that SwiftUI provides.",
            zipFilename: "photokit-bringing-photos-picker-to-your-swiftui-app.zip",
            webURL: "https://developer.apple.com/documentation/PhotoKit/bringing-photos-picker-to-your-swiftui-app"
        ),
        SampleCodeEntry(
            title: "Browsing and Modifying Photo Albums",
            url: "/documentation/PhotoKit/browsing-and-modifying-photo-albums",
            framework: "PhotoKit",
            description: "Help users organize their photos into albums and browse photo collections in a grid-based layout using PhotoKit.",
            zipFilename: "photokit-browsing-and-modifying-photo-albums.zip",
            webURL: "https://developer.apple.com/documentation/PhotoKit/browsing-and-modifying-photo-albums"
        ),
        SampleCodeEntry(
            title: "Creating a Slideshow Project Extension for Photos",
            url: "/documentation/PhotoKit/creating-a-slideshow-project-extension-for-photos",
            framework: "PhotoKit",
            description: "Augment the macOS Photos app with extensions that support project creation.",
            zipFilename: "photokit-creating-a-slideshow-project-extension-for-photos.zip",
            webURL: "https://developer.apple.com/documentation/PhotoKit/creating-a-slideshow-project-extension-for-photos"
        ),
        SampleCodeEntry(
            title: "Implementing an inline Photos picker",
            url: "/documentation/PhotoKit/implementing-an-inline-photos-picker",
            framework: "PhotoKit",
            description: "Embed a system-provided, half-height Photos picker into your app’s view.",
            zipFilename: "photokit-implementing-an-inline-photos-picker.zip",
            webURL: "https://developer.apple.com/documentation/PhotoKit/implementing-an-inline-photos-picker"
        ),
        SampleCodeEntry(
            title: "Selecting Photos and Videos in iOS",
            url: "/documentation/PhotoKit/selecting-photos-and-videos-in-ios",
            framework: "PhotoKit",
            description: "Improve the user experience of finding and selecting assets by using the Photos picker.###",
            zipFilename: "photokit-selecting-photos-and-videos-in-ios.zip",
            webURL: "https://developer.apple.com/documentation/PhotoKit/selecting-photos-and-videos-in-ios"
        ),
        SampleCodeEntry(
            title: "Checking IDs with the Verifier API",
            url: "/documentation/ProximityReader/checking-ids-with-the-verifier-api",
            framework: "ProximityReader",
            description: "Read and verify mobile driver’s license information without any additional hardware.",
            zipFilename: "proximityreader-checking-ids-with-the-verifier-api.zip",
            webURL: "https://developer.apple.com/documentation/ProximityReader/checking-ids-with-the-verifier-api"
        ),
        SampleCodeEntry(
            title: "Loading entities with ShaderGraph materials",
            url: "/documentation/RealityComposerPro/loading-entities-with-shadergraph-materials",
            framework: "RealityComposerPro",
            description: "Bring entities that contain materials created with Reality Composer Pro for use in your visionOS app.",
            zipFilename: "realitycomposerpro-loading-entities-with-shadergraph-materials.zip",
            webURL: "https://developer.apple.com/documentation/RealityComposerPro/loading-entities-with-shadergraph-materials"
        ),
        SampleCodeEntry(
            title: "Animating entity rotation with a system",
            url: "/documentation/RealityKit/animated-rotation-with-a-system",
            framework: "RealityKit",
            description: "Rotate an entity around an axis using a Component and a System.",
            zipFilename: "realitykit-animated-rotation-with-a-system.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/animated-rotation-with-a-system"
        ),
        SampleCodeEntry(
            title: "Bringing your SceneKit projects to RealityKit",
            url: "/documentation/RealityKit/bringing-your-scenekit-projects-to-realitykit",
            framework: "RealityKit",
            description: "Adapt a platformer game for RealityKit’s powerful ECS and modularity.",
            zipFilename: "realitykit-bringing-your-scenekit-projects-to-realitykit.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/bringing-your-scenekit-projects-to-realitykit"
        ),
        SampleCodeEntry(
            title: "Building an immersive experience with RealityKit",
            url: "/documentation/RealityKit/building-an-immersive-experience-with-realitykit",
            framework: "RealityKit",
            description: "Use systems and postprocessing effects to create a realistic underwater scene.",
            zipFilename: "realitykit-building-an-immersive-experience-with-realitykit.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/building-an-immersive-experience-with-realitykit"
        ),
        SampleCodeEntry(
            title: "Building an object reconstruction app",
            url: "/documentation/RealityKit/building-an-object-reconstruction-app",
            framework: "RealityKit",
            description: "Reconstruct objects from user-selected input images by using photogrammetry.",
            zipFilename: "realitykit-building-an-object-reconstruction-app.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/building-an-object-reconstruction-app"
        ),
        SampleCodeEntry(
            title: "Combining 2D and 3D views in an immersive app",
            url: "/documentation/RealityKit/combining-2d-and-3d-views-in-an-immersive-app",
            framework: "RealityKit",
            description: "Use attachments to place 2D content relative to 3D content in your visionOS app.",
            zipFilename: "realitykit-combining-2d-and-3d-views-in-an-immersive-app.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/combining-2d-and-3d-views-in-an-immersive-app"
        ),
        SampleCodeEntry(
            title: "Composing interactive 3D content with RealityKit and Reality Composer Pro",
            url: "/documentation/RealityKit/composing-interactive-3d-content-with-realitykit-and-reality-composer-pro",
            framework: "RealityKit",
            description: "Build an interactive scene using an animation timeline.",
            zipFilename: "realitykit-composing-interactive-3d-content-with-realitykit-and-reality-composer-pro.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/composing-interactive-3d-content-with-realitykit-and-reality-composer-pro"
        ),
        SampleCodeEntry(
            title: "Configuring Collision in RealityKit",
            url: "/documentation/RealityKit/configuring-collision-in-realitykit",
            framework: "RealityKit",
            description: "Use collision groups and collision filters to control which objects collide.",
            zipFilename: "realitykit-configuring-collision-in-realitykit.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/configuring-collision-in-realitykit"
        ),
        SampleCodeEntry(
            title: "Construct an immersive environment for visionOS",
            url: "/documentation/RealityKit/construct-an-immersive-environment-for-visionOS",
            framework: "RealityKit",
            description: "Build efficient custom worlds for your app.",
            zipFilename: "realitykit-construct-an-immersive-environment-for-visionos.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/construct-an-immersive-environment-for-visionOS"
        ),
        SampleCodeEntry(
            title: "Creating a Spaceship game",
            url: "/documentation/RealityKit/creating-a-spaceship-game",
            framework: "RealityKit",
            description: "Build an immersive game using RealityKit audio, simulation, and rendering features.",
            zipFilename: "realitykit-creating-a-spaceship-game.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/creating-a-spaceship-game"
        ),
        SampleCodeEntry(
            title: "Creating a game with scene understanding",
            url: "/documentation/RealityKit/creating-a-game-with-scene-understanding",
            framework: "RealityKit",
            description: "Create AR games and experiences that interact with real-world objects on LiDAR-equipped iOS devices.",
            zipFilename: "realitykit-creating-a-game-with-scene-understanding.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/creating-a-game-with-scene-understanding"
        ),
        SampleCodeEntry(
            title: "Creating a photogrammetry command-line app",
            url: "/documentation/RealityKit/creating-a-photogrammetry-command-line-app",
            framework: "RealityKit",
            description: "Generate 3D objects from images using RealityKit Object Capture.",
            zipFilename: "realitykit-creating-a-photogrammetry-command-line-app.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/creating-a-photogrammetry-command-line-app"
        ),
        SampleCodeEntry(
            title: "Creating a spatial drawing app with RealityKit",
            url: "/documentation/RealityKit/creating-a-spatial-drawing-app-with-realitykit",
            framework: "RealityKit",
            description: "Use low-level mesh and texture APIs to achieve fast updates to a person’s brush strokes by integrating RealityKit with ARKit and SwiftUI.",
            zipFilename: "realitykit-creating-a-spatial-drawing-app-with-realitykit.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/creating-a-spatial-drawing-app-with-realitykit"
        ),
        SampleCodeEntry(
            title: "Creating an App for Face-Painting in AR",
            url: "/documentation/RealityKit/creating-an-app-for-face-painting-in-ar",
            framework: "RealityKit",
            description: "Combine RealityKit’s face detection with PencilKit to implement virtual face-painting.",
            zipFilename: "realitykit-creating-an-app-for-face-painting-in-ar.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/creating-an-app-for-face-painting-in-ar"
        ),
        SampleCodeEntry(
            title: "Docking a video player in an immersive scene",
            url: "/documentation/RealityKit/docking-a-video-player-in-an-immersive-scene",
            framework: "RealityKit",
            description: "Secure a video player in an immersive scene with a docking region you can specify.",
            zipFilename: "realitykit-docking-a-video-player-in-an-immersive-scene.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/docking-a-video-player-in-an-immersive-scene"
        ),
        SampleCodeEntry(
            title: "Generating interactive geometry with RealityKit",
            url: "/documentation/RealityKit/generating-interactive-geometry-with-realitykit",
            framework: "RealityKit",
            description: "Create an interactive mesh with low-level mesh and low-level texture.",
            zipFilename: "realitykit-generating-interactive-geometry-with-realitykit.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/generating-interactive-geometry-with-realitykit"
        ),
        SampleCodeEntry(
            title: "Implementing special rendering effects with RealityKit postprocessing",
            url: "/documentation/RealityKit/implementing-special-rendering-effects-with-realitykit-postprocessing",
            framework: "RealityKit",
            description: "Implement a variety of postprocessing techniques to alter RealityKit rendering.",
            zipFilename: "realitykit-implementing-special-rendering-effects-with-realitykit-postprocessing.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/implementing-special-rendering-effects-with-realitykit-postprocessing"
        ),
        SampleCodeEntry(
            title: "Presenting an artist’s scene",
            url: "/documentation/RealityKit/presenting-an-artists-scene",
            framework: "RealityKit",
            description: "Display a scene from Reality Composer Pro in visionOS.",
            zipFilename: "realitykit-presenting-an-artists-scene.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/presenting-an-artists-scene"
        ),
        SampleCodeEntry(
            title: "Presenting images in RealityKit",
            url: "/documentation/RealityKit/presenting-images-in-realitykit",
            framework: "RealityKit",
            description: "Create and display spatial scenes in RealityKit",
            zipFilename: "realitykit-presenting-images-in-realitykit.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/presenting-images-in-realitykit"
        ),
        SampleCodeEntry(
            title: "Rendering a windowed game in stereo",
            url: "/documentation/RealityKit/rendering-a-windowed-game-in-stereo",
            framework: "RealityKit",
            description: "Bring an iOS or iPadOS game to visionOS and enhance it.",
            zipFilename: "realitykit-rendering-a-windowed-game-in-stereo.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/rendering-a-windowed-game-in-stereo"
        ),
        SampleCodeEntry(
            title: "Rendering stereoscopic video with RealityKit",
            url: "/documentation/RealityKit/rendering-stereoscopic-video-with-realitykit",
            framework: "RealityKit",
            description: "Render stereoscopic video in visionOS with RealityKit.",
            zipFilename: "realitykit-rendering-stereoscopic-video-with-realitykit.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/rendering-stereoscopic-video-with-realitykit"
        ),
        SampleCodeEntry(
            title: "Responding to gestures on an entity",
            url: "/documentation/RealityKit/responding-to-gestures-on-an-entity",
            framework: "RealityKit",
            description: "Respond to gestures performed on RealityKit entities using input target and collision components.",
            zipFilename: "realitykit-responding-to-gestures-on-an-entity.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/responding-to-gestures-on-an-entity"
        ),
        SampleCodeEntry(
            title: "Scanning objects using Object Capture",
            url: "/documentation/RealityKit/scanning-objects-using-object-capture",
            framework: "RealityKit",
            description: "Implement a full scanning workflow for capturing objects on iOS devices.",
            zipFilename: "realitykit-scanning-objects-using-object-capture.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/scanning-objects-using-object-capture"
        ),
        SampleCodeEntry(
            title: "Simulating particles in your visionOS app",
            url: "/documentation/RealityKit/simulating-particles-in-your-visionos-app",
            framework: "RealityKit",
            description: "Add a range of visual effects to a RealityKit view by attaching a particle emitter component to an entity.",
            zipFilename: "realitykit-simulating-particles-in-your-visionos-app.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/simulating-particles-in-your-visionos-app"
        ),
        SampleCodeEntry(
            title: "Simulating physics joints in your RealityKit app",
            url: "/documentation/RealityKit/simulating-physics-joints-in-your-realitykit-app",
            framework: "RealityKit",
            description: "Create realistic, connected motion using physics joints.",
            zipFilename: "realitykit-simulating-physics-joints-in-your-realitykit-app.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/simulating-physics-joints-in-your-realitykit-app"
        ),
        SampleCodeEntry(
            title: "Simulating physics with collisions in your visionOS app",
            url: "/documentation/RealityKit/simulating-physics-with-collisions-in-your-visionos-app",
            framework: "RealityKit",
            description: "Create entities that behave and react like physical objects in a RealityKit view.",
            zipFilename: "realitykit-simulating-physics-with-collisions-in-your-visionos-app.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/simulating-physics-with-collisions-in-your-visionos-app"
        ),
        SampleCodeEntry(
            title: "Tracking a handheld accessory as a virtual sculpting tool",
            url: "/documentation/RealityKit/tracking-a-handheld-accessory-as-a-virtual-sculpting-tool",
            framework: "RealityKit",
            description: "Use a tracked accessory with Apple Vision Pro to create a virtual sculpture.",
            zipFilename: "realitykit-tracking-a-handheld-accessory-as-a-virtual-sculpting-tool.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/tracking-a-handheld-accessory-as-a-virtual-sculpting-tool"
        ),
        SampleCodeEntry(
            title: "Transforming RealityKit entities using gestures",
            url: "/documentation/RealityKit/transforming-realitykit-entities-with-gestures",
            framework: "RealityKit",
            description: "Build a RealityKit component to support standard visionOS gestures on any entity.",
            zipFilename: "realitykit-transforming-realitykit-entities-with-gestures.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/transforming-realitykit-entities-with-gestures"
        ),
        SampleCodeEntry(
            title: "Transforming entities between RealityKit coordinate spaces",
            url: "/documentation/RealityKit/transforming-entities-between-realitykit-coordinate-spaces",
            framework: "RealityKit",
            description: "Move an entity between a volumetric window and an immersive space using coordinate space transformations.",
            zipFilename: "realitykit-transforming-entities-between-realitykit-coordinate-spaces.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/transforming-entities-between-realitykit-coordinate-spaces"
        ),
        SampleCodeEntry(
            title: "Using object capture assets in RealityKit",
            url: "/documentation/RealityKit/using-object-capture-assets-in-realitykit",
            framework: "RealityKit",
            description: "Create a chess game using RealityKit and assets created using Object Capture.",
            zipFilename: "realitykit-using-object-capture-assets-in-realitykit.zip",
            webURL: "https://developer.apple.com/documentation/RealityKit/using-object-capture-assets-in-realitykit"
        ),
        SampleCodeEntry(
            title: "Recording and Streaming Your macOS App",
            url: "/documentation/ReplayKit/recording-and-streaming-your-macos-app",
            framework: "ReplayKit",
            description: "Share screen recordings, or broadcast live audio and video of your app, by adding ReplayKit to your macOS apps and games.",
            zipFilename: "replaykit-recording-and-streaming-your-macos-app.zip",
            webURL: "https://developer.apple.com/documentation/ReplayKit/recording-and-streaming-your-macos-app"
        ),
        SampleCodeEntry(
            title: "Create a 3D model of an interior room by guiding the user through an AR experience",
            url: "/documentation/RoomPlan/create-a-3d-model-of-an-interior-room-by-guiding-the-user-through-an-ar-experience",
            framework: "RoomPlan",
            description: "Highlight physical structures and display text that guides a user to scan the shape of their physical environment using a framework-provided view.",
            zipFilename: "roomplan-create-a-3d-model-of-an-interior-room-by-guiding-the-user-through-an-ar-experience.zip",
            webURL: "https://developer.apple.com/documentation/RoomPlan/create-a-3d-model-of-an-interior-room-by-guiding-the-user-through-an-ar-experience"
        ),
        SampleCodeEntry(
            title: "Merging multiple scans into a single structure",
            url: "/documentation/RoomPlan/merging-multiple-scans-into-a-single-structure",
            framework: "RoomPlan",
            description: "Export a 3D model that consists of multiple rooms captured in the same physical vicinity.",
            zipFilename: "roomplan-merging-multiple-scans-into-a-single-structure.zip",
            webURL: "https://developer.apple.com/documentation/RoomPlan/merging-multiple-scans-into-a-single-structure"
        ),
        SampleCodeEntry(
            title: "Providing custom models for captured rooms and structure exports",
            url: "/documentation/RoomPlan/providing-custom-models-for-captured-rooms-and-structure-exports",
            framework: "RoomPlan",
            description: "Enhance the look of an exported 3D model by substituting object bounding boxes with detailed 3D renditions.",
            zipFilename: "roomplan-providing-custom-models-for-captured-rooms-and-structure-exports.zip",
            webURL: "https://developer.apple.com/documentation/RoomPlan/providing-custom-models-for-captured-rooms-and-structure-exports"
        ),
        SampleCodeEntry(
            title: "Adopting Declarative Content Blocking in Safari Web Extensions",
            url: "/documentation/SafariServices/adopting-declarative-content-blocking-in-safari-web-extensions",
            framework: "SafariServices",
            description: "Block web content with your web extension using the declarative net request API.",
            zipFilename: "safariservices-adopting-declarative-content-blocking-in-safari-web-extensions.zip",
            webURL: "https://developer.apple.com/documentation/SafariServices/adopting-declarative-content-blocking-in-safari-web-extensions"
        ),
        SampleCodeEntry(
            title: "Adopting New Safari Web Extension APIs",
            url: "/documentation/SafariServices/adopting-new-safari-web-extension-apis",
            framework: "SafariServices",
            description: "Improve your web extension in Safari with a non-persistent background page and new tab-override customization.",
            zipFilename: "safariservices-adopting-new-safari-web-extension-apis.zip",
            webURL: "https://developer.apple.com/documentation/SafariServices/adopting-new-safari-web-extension-apis"
        ),
        SampleCodeEntry(
            title: "Creating Safari Web Inspector extensions",
            url: "/documentation/SafariServices/creating-safari-web-inspector-extensions",
            framework: "SafariServices",
            description: "Learn how to make custom Safari Web Inspector extensions.",
            zipFilename: "safariservices-creating-safari-web-inspector-extensions.zip",
            webURL: "https://developer.apple.com/documentation/SafariServices/creating-safari-web-inspector-extensions"
        ),
        SampleCodeEntry(
            title: "Developing a Safari Web Extension",
            url: "/documentation/SafariServices/developing-a-safari-web-extension",
            framework: "SafariServices",
            description: "Customize and enhance web pages by building a Safari web extension.",
            zipFilename: "safariservices-developing-a-safari-web-extension.zip",
            webURL: "https://developer.apple.com/documentation/SafariServices/developing-a-safari-web-extension"
        ),
        SampleCodeEntry(
            title: "Messaging a Web Extension’s Native App",
            url: "/documentation/SafariServices/messaging-a-web-extension-s-native-app",
            framework: "SafariServices",
            description: "Communicate between your Safari web extension and its containing app.",
            zipFilename: "safariservices-messaging-a-web-extension-s-native-app.zip",
            webURL: "https://developer.apple.com/documentation/SafariServices/messaging-a-web-extension-s-native-app"
        ),
        SampleCodeEntry(
            title: "Modernizing Safari Web Extensions",
            url: "/documentation/SafariServices/modernizing-safari-web-extensions",
            framework: "SafariServices",
            description: "Learn about enhancements to Safari Web Extensions.",
            zipFilename: "safariservices-modernizing-safari-web-extensions.zip",
            webURL: "https://developer.apple.com/documentation/SafariServices/modernizing-safari-web-extensions"
        ),
        SampleCodeEntry(
            title: "Previewing Metadata using Open Graph",
            url: "/documentation/SafariServices/previewing-metadata-using-open-graph",
            framework: "SafariServices",
            description: "Build a Safari Extension that displays metadata using Open Graph.",
            zipFilename: "safariservices-previewing-metadata-using-open-graph.zip",
            webURL: "https://developer.apple.com/documentation/SafariServices/previewing-metadata-using-open-graph"
        ),
        SampleCodeEntry(
            title: "Postprocessing a Scene With Custom Symbols",
            url: "/documentation/SceneKit/postprocessing-a-scene-with-custom-symbols",
            framework: "SceneKit",
            description: "Create visual effects in a scene by defining a rendering technique with custom symbols.",
            zipFilename: "scenekit-postprocessing-a-scene-with-custom-symbols.zip",
            webURL: "https://developer.apple.com/documentation/SceneKit/postprocessing-a-scene-with-custom-symbols"
        ),
        SampleCodeEntry(
            title: "Capturing screen content in macOS",
            url: "/documentation/ScreenCaptureKit/capturing-screen-content-in-macos",
            framework: "ScreenCaptureKit",
            description: "Stream desktop content like displays, apps, and windows by adopting screen capture in your app.",
            zipFilename: "screencapturekit-capturing-screen-content-in-macos.zip",
            webURL: "https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos"
        ),
        SampleCodeEntry(
            title: "Constraining a tool’s launch environment",
            url: "/documentation/Security/constraining-a-tool",
            framework: "Security",
            description: "Improve the security of your macOS app by limiting the ways its components can run.",
            zipFilename: "security-constraining-a-tool.zip",
            webURL: "https://developer.apple.com/documentation/Security/constraining-a-tool"
        ),
        SampleCodeEntry(
            title: "Updating your app package installer to use the new Service Management API",
            url: "/documentation/ServiceManagement/updating-your-app-package-installer-to-use-the-new-service-management-api",
            framework: "ServiceManagement",
            description: "Learn about the Service Management API with a GUI-less agent app.",
            zipFilename: "servicemanagement-updating-your-app-package-installer-to-use-the-new-service-management-api.zip",
            webURL: "https://developer.apple.com/documentation/ServiceManagement/updating-your-app-package-installer-to-use-the-new-service-management-api"
        ),
        SampleCodeEntry(
            title: "Building a Custom Catalog and Matching Audio",
            url: "/documentation/ShazamKit/building-a-custom-catalog-and-matching-audio",
            framework: "ShazamKit",
            description: "Display lesson content that’s synchronized to a learning video by matching the audio to a custom reference signature and associated metadata.",
            zipFilename: "shazamkit-building-a-custom-catalog-and-matching-audio.zip",
            webURL: "https://developer.apple.com/documentation/ShazamKit/building-a-custom-catalog-and-matching-audio"
        ),
        SampleCodeEntry(
            title: "ShazamKit Dance Finder with Managed Session",
            url: "/documentation/ShazamKit/shazamkit-dance-finder-with-managed-session",
            framework: "ShazamKit",
            description: "Find a video of dance moves for a specific song by matching the audio to a custom catalog, and show a history of recognized songs.",
            zipFilename: "shazamkit-shazamkit-dance-finder-with-managed-session.zip",
            webURL: "https://developer.apple.com/documentation/ShazamKit/shazamkit-dance-finder-with-managed-session"
        ),
        SampleCodeEntry(
            title: "Adding Shortcuts for Wind Down",
            url: "/documentation/SiriKit/adding-shortcuts-for-wind-down",
            framework: "SiriKit",
            description: "Reveal your app’s shortcuts inside the Health app.",
            zipFilename: "sirikit-adding-shortcuts-for-wind-down.zip",
            webURL: "https://developer.apple.com/documentation/SiriKit/adding-shortcuts-for-wind-down"
        ),
        SampleCodeEntry(
            title: "Booking Rides with SiriKit",
            url: "/documentation/SiriKit/booking-rides-with-sirikit",
            framework: "SiriKit",
            description: "Add Intents extensions to your app to handle requests to book rides using Siri and Maps.",
            zipFilename: "sirikit-booking-rides-with-sirikit.zip",
            webURL: "https://developer.apple.com/documentation/SiriKit/booking-rides-with-sirikit"
        ),
        SampleCodeEntry(
            title: "Handling Payment Requests with SiriKit",
            url: "/documentation/SiriKit/handling-payment-requests-with-sirikit",
            framework: "SiriKit",
            description: "Add an Intent Extension to your app to handle money transfer requests with Siri.",
            zipFilename: "sirikit-handling-payment-requests-with-sirikit.zip",
            webURL: "https://developer.apple.com/documentation/SiriKit/handling-payment-requests-with-sirikit"
        ),
        SampleCodeEntry(
            title: "Handling Workout Requests with SiriKit",
            url: "/documentation/SiriKit/handling-workout-requests-with-sirikit",
            framework: "SiriKit",
            description: "Add an Intent Extension to your app that handles requests to control workouts with Siri.",
            zipFilename: "sirikit-handling-workout-requests-with-sirikit.zip",
            webURL: "https://developer.apple.com/documentation/SiriKit/handling-workout-requests-with-sirikit"
        ),
        SampleCodeEntry(
            title: "Integrating Your App with Siri Event Suggestions",
            url: "/documentation/SiriKit/integrating-your-app-with-siri-event-suggestions",
            framework: "SiriKit",
            description: "Donate reservations and provide quick access to event details throughout the system.",
            zipFilename: "sirikit-integrating-your-app-with-siri-event-suggestions.zip",
            webURL: "https://developer.apple.com/documentation/SiriKit/integrating-your-app-with-siri-event-suggestions"
        ),
        SampleCodeEntry(
            title: "Managing Audio with SiriKit",
            url: "/documentation/SiriKit/managing-audio-with-sirikit",
            framework: "SiriKit",
            description: "Control audio playback and handle requests to add media using SiriKit Media Intents.",
            zipFilename: "sirikit-managing-audio-with-sirikit.zip",
            webURL: "https://developer.apple.com/documentation/SiriKit/managing-audio-with-sirikit"
        ),
        SampleCodeEntry(
            title: "Providing Hands-Free App Control with Intents",
            url: "/documentation/SiriKit/providing-hands-free-app-control-with-intents",
            framework: "SiriKit",
            description: "Resolve, confirm, and handle intents without an extension.",
            zipFilename: "sirikit-providing-hands-free-app-control-with-intents.zip",
            webURL: "https://developer.apple.com/documentation/SiriKit/providing-hands-free-app-control-with-intents"
        ),
        SampleCodeEntry(
            title: "Soup Chef with App Intents: Migrating custom intents",
            url: "/documentation/SiriKit/soup-chef-with-app-intents-migrating-custom-intents",
            framework: "SiriKit",
            description: "Integrating App Intents to provide your appʼs actions to Siri and Shortcuts.###",
            zipFilename: "sirikit-soup-chef-with-app-intents-migrating-custom-intents.zip",
            webURL: "https://developer.apple.com/documentation/SiriKit/soup-chef-with-app-intents-migrating-custom-intents"
        ),
        SampleCodeEntry(
            title: "Soup Chef: Accelerating App Interactions with Shortcuts",
            url: "/documentation/SiriKit/soup-chef-accelerating-app-interactions-with-shortcuts",
            framework: "SiriKit",
            description: "Make it easy for people to use Siri with your app by providing shortcuts to your app’s actions.",
            zipFilename: "sirikit-soup-chef-accelerating-app-interactions-with-shortcuts.zip",
            webURL: "https://developer.apple.com/documentation/SiriKit/soup-chef-accelerating-app-interactions-with-shortcuts"
        ),
        SampleCodeEntry(
            title: "Classifying Live Audio Input with a Built-in Sound Classifier",
            url: "/documentation/SoundAnalysis/classifying-live-audio-input-with-a-built-in-sound-classifier",
            framework: "SoundAnalysis",
            description: "Detect and identify hundreds of sounds by using a trained classifier.",
            zipFilename: "soundanalysis-classifying-live-audio-input-with-a-built-in-sound-classifier.zip",
            webURL: "https://developer.apple.com/documentation/SoundAnalysis/classifying-live-audio-input-with-a-built-in-sound-classifier"
        ),
        SampleCodeEntry(
            title: "Bringing advanced speech-to-text capabilities to your app",
            url: "/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app",
            framework: "Speech",
            description: "Learn how to incorporate live speech-to-text transcription into your app with SpeechAnalyzer.",
            zipFilename: "speech-bringing-advanced-speech-to-text-capabilities-to-your-app.zip",
            webURL: "https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app"
        ),
        SampleCodeEntry(
            title: "Recognizing speech in live audio",
            url: "/documentation/Speech/recognizing-speech-in-live-audio",
            framework: "Speech",
            description: "Perform speech recognition on audio coming from the microphone of an iOS device.",
            zipFilename: "speech-recognizing-speech-in-live-audio.zip",
            webURL: "https://developer.apple.com/documentation/Speech/recognizing-speech-in-live-audio"
        ),
        SampleCodeEntry(
            title: "Determining service entitlement on the server",
            url: "/documentation/StoreKit/determining-service-entitlement-on-the-server",
            framework: "StoreKit",
            description: "Identify a customer’s entitlement to your service, offers, and messaging by analyzing a validated receipt and the state of their subscription.",
            zipFilename: "storekit-determining-service-entitlement-on-the-server.zip",
            webURL: "https://developer.apple.com/documentation/StoreKit/determining-service-entitlement-on-the-server"
        ),
        SampleCodeEntry(
            title: "Generating a Promotional Offer Signature on the Server",
            url: "/documentation/StoreKit/generating-a-promotional-offer-signature-on-the-server",
            framework: "StoreKit",
            description: "Generate a signature using your private key and lightweight cryptography libraries.",
            zipFilename: "storekit-generating-a-promotional-offer-signature-on-the-server.zip",
            webURL: "https://developer.apple.com/documentation/StoreKit/generating-a-promotional-offer-signature-on-the-server"
        ),
        SampleCodeEntry(
            title: "Implementing a store in your app using the StoreKit API",
            url: "/documentation/StoreKit/implementing-a-store-in-your-app-using-the-storekit-api",
            framework: "StoreKit",
            description: "Offer In-App Purchases and manage entitlements using signed transactions and status information.",
            zipFilename: "storekit-implementing-a-store-in-your-app-using-the-storekit-api.zip",
            webURL: "https://developer.apple.com/documentation/StoreKit/implementing-a-store-in-your-app-using-the-storekit-api"
        ),
        SampleCodeEntry(
            title: "Offering media for sale in your app",
            url: "/documentation/StoreKit/offering-media-for-sale-in-your-app",
            framework: "StoreKit",
            description: "Allow users to purchase media in the App Store from within your app.",
            zipFilename: "storekit-offering-media-for-sale-in-your-app.zip",
            webURL: "https://developer.apple.com/documentation/StoreKit/offering-media-for-sale-in-your-app"
        ),
        SampleCodeEntry(
            title: "Offering, completing, and restoring in-app purchases",
            url: "/documentation/StoreKit/offering-completing-and-restoring-in-app-purchases",
            framework: "StoreKit",
            description: "Fetch, display, purchase, validate, and finish transactions in your app.",
            zipFilename: "storekit-offering-completing-and-restoring-in-app-purchases.zip",
            webURL: "https://developer.apple.com/documentation/StoreKit/offering-completing-and-restoring-in-app-purchases"
        ),
        SampleCodeEntry(
            title: "Requesting App Store reviews",
            url: "/documentation/StoreKit/requesting-app-store-reviews",
            framework: "StoreKit",
            description: "Implement best practices for prompting users to review your app in the App Store.",
            zipFilename: "storekit-requesting-app-store-reviews.zip",
            webURL: "https://developer.apple.com/documentation/StoreKit/requesting-app-store-reviews"
        ),
        SampleCodeEntry(
            title: "Understanding StoreKit workflows",
            url: "/documentation/StoreKit/understanding-storekit-workflows",
            framework: "StoreKit",
            description: "Implement an in-app store with several product types, using StoreKit views.###",
            zipFilename: "storekit-understanding-storekit-workflows.zip",
            webURL: "https://developer.apple.com/documentation/StoreKit/understanding-storekit-workflows"
        ),
        SampleCodeEntry(
            title: "Testing and validating ad impression signatures and postbacks for SKAdNetwork",
            url: "/documentation/StoreKitTest/testing-and-validating-ad-impression-signatures-and-postbacks-for-skadnetwork",
            framework: "StoreKitTest",
            description: "Validate your ad impressions and test your postbacks by creating unit tests using the StoreKit Test framework.###",
            zipFilename: "storekittest-testing-and-validating-ad-impression-signatures-and-postbacks-for-skadnetwork.zip",
            webURL: "https://developer.apple.com/documentation/StoreKitTest/testing-and-validating-ad-impression-signatures-and-postbacks-for-skadnetwork"
        ),
        SampleCodeEntry(
            title: "Calling APIs Across Language Boundaries",
            url: "/documentation/Swift/CallingAPIsAcrossLanguageBoundaries",
            framework: "Swift",
            description: "Use a variety of C++ APIs in Swift – and vice-versa – across multiple targets and frameworks in an Xcode project.",
            zipFilename: "swift-callingapisacrosslanguageboundaries.zip",
            webURL: "https://developer.apple.com/documentation/Swift/CallingAPIsAcrossLanguageBoundaries"
        ),
        SampleCodeEntry(
            title: "Code-along: Elevating an app with Swift concurrency",
            url: "/documentation/Swift/code-along-elevating-an-app-with-swift-concurrency",
            framework: "Swift",
            description: "Code along with the WWDC presenter to elevate a SwiftUI app with Swift concurrency.",
            zipFilename: "swift-code-along-elevating-an-app-with-swift-concurrency.zip",
            webURL: "https://developer.apple.com/documentation/Swift/code-along-elevating-an-app-with-swift-concurrency"
        ),
        SampleCodeEntry(
            title: "Mixing Languages in an Xcode project",
            url: "/documentation/Swift/MixingLanguagesInAnXcodeProject",
            framework: "Swift",
            description: "Use C++ APIs in Swift – and Swift APIs in C++ – in a single framework target, and consume the framework’s APIs in a separate app target.",
            zipFilename: "swift-mixinglanguagesinanxcodeproject.zip",
            webURL: "https://developer.apple.com/documentation/Swift/MixingLanguagesInAnXcodeProject"
        ),
        SampleCodeEntry(
            title: "Updating an app to use strict concurrency",
            url: "/documentation/Swift/updating-an-app-to-use-strict-concurrency",
            framework: "Swift",
            description: "Use this code to follow along with a guide to migrating your code to take advantage of the full concurrency protection that the Swift 6 language mode provides.",
            zipFilename: "swift-updating-an-app-to-use-strict-concurrency.zip",
            webURL: "https://developer.apple.com/documentation/Swift/updating-an-app-to-use-strict-concurrency"
        ),
        SampleCodeEntry(
            title: "Adding and editing persistent data in your app",
            url: "/documentation/SwiftData/Adding-and-editing-persistent-data-in-your-app",
            framework: "SwiftData",
            description: "Create a data entry form for collecting and changing data managed by SwiftData.",
            zipFilename: "swiftdata-adding-and-editing-persistent-data-in-your-app.zip",
            webURL: "https://developer.apple.com/documentation/SwiftData/Adding-and-editing-persistent-data-in-your-app"
        ),
        SampleCodeEntry(
            title: "Defining data relationships with enumerations and model classes",
            url: "/documentation/SwiftData/Defining-data-relationships-with-enumerations-and-model-classes",
            framework: "SwiftData",
            description: "Create relationships for static and dynamic data stored in your app.",
            zipFilename: "swiftdata-defining-data-relationships-with-enumerations-and-model-classes.zip",
            webURL: "https://developer.apple.com/documentation/SwiftData/Defining-data-relationships-with-enumerations-and-model-classes"
        ),
        SampleCodeEntry(
            title: "Deleting persistent data from your app",
            url: "/documentation/SwiftData/Deleting-persistent-data-from-your-app",
            framework: "SwiftData",
            description: "Explore different ways to use SwiftData to delete persistent data.",
            zipFilename: "swiftdata-deleting-persistent-data-from-your-app.zip",
            webURL: "https://developer.apple.com/documentation/SwiftData/Deleting-persistent-data-from-your-app"
        ),
        SampleCodeEntry(
            title: "Filtering and sorting persistent data",
            url: "/documentation/SwiftData/Filtering-and-sorting-persistent-data",
            framework: "SwiftData",
            description: "Manage data store presentation using predicates and dynamic queries.",
            zipFilename: "swiftdata-filtering-and-sorting-persistent-data.zip",
            webURL: "https://developer.apple.com/documentation/SwiftData/Filtering-and-sorting-persistent-data"
        ),
        SampleCodeEntry(
            title: "Maintaining a local copy of server data",
            url: "/documentation/SwiftData/Maintaining-a-local-copy-of-server-data",
            framework: "SwiftData",
            description: "Create and update a persistent store to cache read-only network data.",
            zipFilename: "swiftdata-maintaining-a-local-copy-of-server-data.zip",
            webURL: "https://developer.apple.com/documentation/SwiftData/Maintaining-a-local-copy-of-server-data"
        ),
        SampleCodeEntry(
            title: "Add rich graphics to your SwiftUI app",
            url: "/documentation/SwiftUI/add-rich-graphics-to-your-swiftui-app",
            framework: "SwiftUI",
            description: "Make your apps stand out by adding background materials, vibrancy, custom graphics, and animations.",
            zipFilename: "swiftui-add-rich-graphics-to-your-swiftui-app.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/add-rich-graphics-to-your-swiftui-app"
        ),
        SampleCodeEntry(
            title: "Adopting drag and drop using SwiftUI",
            url: "/documentation/SwiftUI/Adopting-drag-and-drop-using-SwiftUI",
            framework: "SwiftUI",
            description: "Enable drag-and-drop interactions in lists, tables and custom views.",
            zipFilename: "swiftui-adopting-drag-and-drop-using-swiftui.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Adopting-drag-and-drop-using-SwiftUI"
        ),
        SampleCodeEntry(
            title: "Backyard Birds: Building an app with SwiftData and widgets",
            url: "/documentation/SwiftUI/Backyard-birds-sample",
            framework: "SwiftUI",
            description: "Create an app with persistent data, interactive widgets, and an all new in-app purchase experience.",
            zipFilename: "swiftui-backyard-birds-sample.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Backyard-birds-sample"
        ),
        SampleCodeEntry(
            title: "Bringing multiple windows to your SwiftUI app",
            url: "/documentation/SwiftUI/bringing-multiple-windows-to-your-swiftui-app",
            framework: "SwiftUI",
            description: "Compose rich views by reacting to state changes and customize your app’s scene presentation and behavior on iPadOS and macOS.",
            zipFilename: "swiftui-bringing-multiple-windows-to-your-swiftui-app.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/bringing-multiple-windows-to-your-swiftui-app"
        ),
        SampleCodeEntry(
            title: "Bringing robust navigation structure to your SwiftUI app",
            url: "/documentation/SwiftUI/Bringing-robust-navigation-structure-to-your-swiftui-app",
            framework: "SwiftUI",
            description: "Use navigation links, stacks, destinations, and paths to provide a streamlined experience for all platforms, as well as behaviors such as deep linking and state restoration.",
            zipFilename: "swiftui-bringing-robust-navigation-structure-to-your-swiftui-app.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Bringing-robust-navigation-structure-to-your-swiftui-app"
        ),
        SampleCodeEntry(
            title: "Building a document-based app using SwiftData",
            url: "/documentation/SwiftUI/Building-a-document-based-app-using-SwiftData",
            framework: "SwiftUI",
            description: "Code along with the WWDC presenter to transform an app with SwiftData.",
            zipFilename: "swiftui-building-a-document-based-app-using-swiftdata.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Building-a-document-based-app-using-SwiftData"
        ),
        SampleCodeEntry(
            title: "Building a great Mac app with SwiftUI",
            url: "/documentation/SwiftUI/building-a-great-mac-app-with-swiftui",
            framework: "SwiftUI",
            description: "Create engaging SwiftUI Mac apps by incorporating side bars, tables, toolbars, and several other popular user interface elements.",
            zipFilename: "swiftui-building-a-great-mac-app-with-swiftui.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/building-a-great-mac-app-with-swiftui"
        ),
        SampleCodeEntry(
            title: "Building rich SwiftUI text experiences",
            url: "/documentation/SwiftUI/building-rich-swiftui-text-experiences",
            framework: "SwiftUI",
            description: "Build an editor for formatted text using SwiftUI text editor views and attributed strings.",
            zipFilename: "swiftui-building-rich-swiftui-text-experiences.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/building-rich-swiftui-text-experiences"
        ),
        SampleCodeEntry(
            title: "Composing custom layouts with SwiftUI",
            url: "/documentation/SwiftUI/composing-custom-layouts-with-swiftui",
            framework: "SwiftUI",
            description: "Arrange views in your app’s interface using layout tools that SwiftUI provides.",
            zipFilename: "swiftui-composing-custom-layouts-with-swiftui.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/composing-custom-layouts-with-swiftui"
        ),
        SampleCodeEntry(
            title: "Controlling the timing and movements of your animations",
            url: "/documentation/SwiftUI/Controlling-the-timing-and-movements-of-your-animations",
            framework: "SwiftUI",
            description: "Build sophisticated animations that you control using phase and keyframe animators.",
            zipFilename: "swiftui-controlling-the-timing-and-movements-of-your-animations.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Controlling-the-timing-and-movements-of-your-animations"
        ),
        SampleCodeEntry(
            title: "Creating a tvOS media catalog app in SwiftUI",
            url: "/documentation/SwiftUI/Creating-a-tvOS-media-catalog-app-in-SwiftUI",
            framework: "SwiftUI",
            description: "Build standard content lockups and rows of content shelves for your tvOS app.",
            zipFilename: "swiftui-creating-a-tvos-media-catalog-app-in-swiftui.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Creating-a-tvOS-media-catalog-app-in-SwiftUI"
        ),
        SampleCodeEntry(
            title: "Creating accessible views",
            url: "/documentation/SwiftUI/creating-accessible-views",
            framework: "SwiftUI",
            description: "Make your app accessible to everyone by applying accessibility modifiers to your SwiftUI views.",
            zipFilename: "swiftui-creating-accessible-views.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/creating-accessible-views"
        ),
        SampleCodeEntry(
            title: "Creating custom container views",
            url: "/documentation/SwiftUI/Creating-custom-container-views",
            framework: "SwiftUI",
            description: "Access individual subviews to compose flexible container views.",
            zipFilename: "swiftui-creating-custom-container-views.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Creating-custom-container-views"
        ),
        SampleCodeEntry(
            title: "Creating visual effects with SwiftUI",
            url: "/documentation/SwiftUI/Creating-visual-effects-with-SwiftUI",
            framework: "SwiftUI",
            description: "Add scroll effects, rich color treatments, custom transitions, and advanced effects using shaders and a text renderer.",
            zipFilename: "swiftui-creating-visual-effects-with-swiftui.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Creating-visual-effects-with-SwiftUI"
        ),
        SampleCodeEntry(
            title: "Customizing window styles and state-restoration behavior in macOS",
            url: "/documentation/SwiftUI/Customizing-window-styles-and-state-restoration-behavior-in-macOS",
            framework: "SwiftUI",
            description: "Configure how your app’s windows look and function in macOS to provide an engaging and more coherent experience.",
            zipFilename: "swiftui-customizing-window-styles-and-state-restoration-behavior-in-macos.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Customizing-window-styles-and-state-restoration-behavior-in-macOS"
        ),
        SampleCodeEntry(
            title: "Enhancing your app’s content with tab navigation",
            url: "/documentation/SwiftUI/Enhancing-your-app-content-with-tab-navigation",
            framework: "SwiftUI",
            description: "Keep your app content front and center while providing quick access to navigation using the tab bar.",
            zipFilename: "swiftui-enhancing-your-app-content-with-tab-navigation.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Enhancing-your-app-content-with-tab-navigation"
        ),
        SampleCodeEntry(
            title: "Focus Cookbook: Supporting and enhancing focus-driven interactions in your SwiftUI app",
            url: "/documentation/SwiftUI/Focus-Cookbook-sample",
            framework: "SwiftUI",
            description: "Create custom focusable views with key-press handlers that accelerate keyboard input and support movement, and control focus programmatically.",
            zipFilename: "swiftui-focus-cookbook-sample.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Focus-Cookbook-sample"
        ),
        SampleCodeEntry(
            title: "Food Truck: Building a SwiftUI multiplatform app",
            url: "/documentation/SwiftUI/food-truck-building-a-swiftui-multiplatform-app",
            framework: "SwiftUI",
            description: "Create a single codebase and app target for Mac, iPad, and iPhone.",
            zipFilename: "swiftui-food-truck-building-a-swiftui-multiplatform-app.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/food-truck-building-a-swiftui-multiplatform-app"
        ),
        SampleCodeEntry(
            title: "Landmarks: Applying a background extension effect",
            url: "/documentation/SwiftUI/Landmarks-Applying-a-background-extension-effect",
            framework: "SwiftUI",
            description: "Configure an image to blur and extend under a sidebar or inspector panel.",
            zipFilename: "swiftui-landmarks-applying-a-background-extension-effect.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Landmarks-Applying-a-background-extension-effect"
        ),
        SampleCodeEntry(
            title: "Landmarks: Building an app with Liquid Glass",
            url: "/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass",
            framework: "SwiftUI",
            description: "Enhance your app experience with system-provided and custom Liquid Glass.",
            zipFilename: "swiftui-landmarks-building-an-app-with-liquid-glass.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass"
        ),
        SampleCodeEntry(
            title: "Landmarks: Displaying custom activity badges",
            url: "/documentation/SwiftUI/Landmarks-Displaying-custom-activity-badges",
            framework: "SwiftUI",
            description: "Provide people with a way to mark their adventures by displaying animated custom activity badges.",
            zipFilename: "swiftui-landmarks-displaying-custom-activity-badges.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Landmarks-Displaying-custom-activity-badges"
        ),
        SampleCodeEntry(
            title: "Landmarks: Extending horizontal scrolling under a sidebar or inspector",
            url: "/documentation/SwiftUI/Landmarks-Extending-horizontal-scrolling-under-a-sidebar-or-inspector",
            framework: "SwiftUI",
            description: "Improve your horizontal scrollbar’s appearance by extending it under a sidebar or inspector.",
            zipFilename: "swiftui-landmarks-extending-horizontal-scrolling-under-a-sidebar-or-inspector.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Landmarks-Extending-horizontal-scrolling-under-a-sidebar-or-inspector"
        ),
        SampleCodeEntry(
            title: "Landmarks: Refining the system provided Liquid Glass effect in toolbars",
            url: "/documentation/SwiftUI/Landmarks-Refining-the-system-provided-glass-effect-in-toolbars",
            framework: "SwiftUI",
            description: "Organize toolbars into related groupings to improve their appearance and utility.",
            zipFilename: "swiftui-landmarks-refining-the-system-provided-glass-effect-in-toolbars.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Landmarks-Refining-the-system-provided-glass-effect-in-toolbars"
        ),
        SampleCodeEntry(
            title: "Loading and displaying a large data feed",
            url: "/documentation/SwiftUI/loading-and-displaying-a-large-data-feed",
            framework: "SwiftUI",
            description: "Consume data in the background, and lower memory use by batching imports and preventing duplicate records.",
            zipFilename: "swiftui-loading-and-displaying-a-large-data-feed.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/loading-and-displaying-a-large-data-feed"
        ),
        SampleCodeEntry(
            title: "Managing model data in your app",
            url: "/documentation/SwiftUI/Managing-model-data-in-your-app",
            framework: "SwiftUI",
            description: "Create connections between your app’s data model and views.",
            zipFilename: "swiftui-managing-model-data-in-your-app.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Managing-model-data-in-your-app"
        ),
        SampleCodeEntry(
            title: "Migrating from the Observable Object protocol to the Observable macro",
            url: "/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro",
            framework: "SwiftUI",
            description: "Update your existing app to leverage the benefits of Observation in Swift.",
            zipFilename: "swiftui-migrating-from-the-observable-object-protocol-to-the-observable-macro.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro"
        ),
        SampleCodeEntry(
            title: "Monitoring data changes in your app",
            url: "/documentation/SwiftUI/Monitoring-model-data-changes-in-your-app",
            framework: "SwiftUI",
            description: "Show changes to data in your app’s user interface by using observable objects.",
            zipFilename: "swiftui-monitoring-model-data-changes-in-your-app.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/Monitoring-model-data-changes-in-your-app"
        ),
        SampleCodeEntry(
            title: "Restoring your app’s state with SwiftUI",
            url: "/documentation/SwiftUI/restoring-your-app-s-state-with-swiftui",
            framework: "SwiftUI",
            description: "Provide app continuity for users by preserving their current activities.###",
            zipFilename: "swiftui-restoring-your-app-s-state-with-swiftui.zip",
            webURL: "https://developer.apple.com/documentation/SwiftUI/restoring-your-app-s-state-with-swiftui"
        ),
        SampleCodeEntry(
            title: "Displaying a Product or Bundle in a Full-Page Template",
            url: "/documentation/TVML/displaying-a-product-or-bundle-in-a-full-page-template",
            framework: "TVML",
            description: "Specify scrollable and fixed regions in a product page.",
            zipFilename: "tvml-displaying-a-product-or-bundle-in-a-full-page-template.zip",
            webURL: "https://developer.apple.com/documentation/TVML/displaying-a-product-or-bundle-in-a-full-page-template"
        ),
        SampleCodeEntry(
            title: "Implementing a Hybrid TV App with TVMLKit",
            url: "/documentation/TVMLKit/implementing-a-hybrid-tv-app-with-tvmlkit",
            framework: "TVMLKit",
            description: "Display content options with document view controllers and fetch and populate content with TVMLKit JS.",
            zipFilename: "tvmlkit-implementing-a-hybrid-tv-app-with-tvmlkit.zip",
            webURL: "https://developer.apple.com/documentation/TVMLKit/implementing-a-hybrid-tv-app-with-tvmlkit"
        ),
        SampleCodeEntry(
            title: "Building a Full Screen Top Shelf Extension",
            url: "/documentation/TVServices/building-a-full-screen-top-shelf-extension",
            framework: "TVServices",
            description: "Highlight content from your Apple TV application by building a full screen Top Shelf extension.",
            zipFilename: "tvservices-building-a-full-screen-top-shelf-extension.zip",
            webURL: "https://developer.apple.com/documentation/TVServices/building-a-full-screen-top-shelf-extension"
        ),
        SampleCodeEntry(
            title: "Mapping Apple TV users to app profiles",
            url: "/documentation/TVServices/mapping-apple-tv-users-to-app-profiles",
            framework: "TVServices",
            description: "Adapt the content of your app for the current viewer by using an entitlement and simplifying sign-in flows.",
            zipFilename: "tvservices-mapping-apple-tv-users-to-app-profiles.zip",
            webURL: "https://developer.apple.com/documentation/TVServices/mapping-apple-tv-users-to-app-profiles"
        ),
        SampleCodeEntry(
            title: "Supporting Multiple Users in Your tvOS App",
            url: "/documentation/TVServices/supporting-multiple-users-in-your-tvos-app",
            framework: "TVServices",
            description: "Store separate data for each user with the new Runs as Current User capability.",
            zipFilename: "tvservices-supporting-multiple-users-in-your-tvos-app.zip",
            webURL: "https://developer.apple.com/documentation/TVServices/supporting-multiple-users-in-your-tvos-app"
        ),
        SampleCodeEntry(
            title: "Creating immersive experiences using a full-screen layout",
            url: "/documentation/TVUIKit/creating-immersive-experiences-using-a-full-screen-layout",
            framework: "TVUIKit",
            description: "Display content with a collection view that maximizes the tvOS experience.",
            zipFilename: "tvuikit-creating-immersive-experiences-using-a-full-screen-layout.zip",
            webURL: "https://developer.apple.com/documentation/TVUIKit/creating-immersive-experiences-using-a-full-screen-layout"
        ),
        SampleCodeEntry(
            title: "Creating tabletop games",
            url: "/documentation/TabletopKit/creating-tabletop-games",
            framework: "TabletopKit",
            description: "Develop a spatial board game where multiple players interact with pieces on a table.",
            zipFilename: "tabletopkit-creating-tabletop-games.zip",
            webURL: "https://developer.apple.com/documentation/TabletopKit/creating-tabletop-games"
        ),
        SampleCodeEntry(
            title: "Implementing playing card overlap and physical characteristics",
            url: "/documentation/TabletopKit/implementing-playing-card-overlap-and-physical-characteristics",
            framework: "TabletopKit",
            description: "Add interactive card game behavior for a pile of playing cards with physically realistic stacking and overlapping.",
            zipFilename: "tabletopkit-implementing-playing-card-overlap-and-physical-characteristics.zip",
            webURL: "https://developer.apple.com/documentation/TabletopKit/implementing-playing-card-overlap-and-physical-characteristics"
        ),
        SampleCodeEntry(
            title: "Simulating dice rolls as a component for your game",
            url: "/documentation/TabletopKit/simulating-dice-rolls-as-a-component-for-your-game",
            framework: "TabletopKit",
            description: "Create a physically realistic dice game by adding interactive rolling and scoring.",
            zipFilename: "tabletopkit-simulating-dice-rolls-as-a-component-for-your-game.zip",
            webURL: "https://developer.apple.com/documentation/TabletopKit/simulating-dice-rolls-as-a-component-for-your-game"
        ),
        SampleCodeEntry(
            title: "Synchronizing group gameplay with TabletopKit",
            url: "/documentation/TabletopKit/synchronizing-group-gameplay-with-tabletopkit",
            framework: "TabletopKit",
            description: "Maintain game state across multiple players in a race to capture all the coins.",
            zipFilename: "tabletopkit-synchronizing-group-gameplay-with-tabletopkit.zip",
            webURL: "https://developer.apple.com/documentation/TabletopKit/synchronizing-group-gameplay-with-tabletopkit"
        ),
        SampleCodeEntry(
            title: "Highlighting app features with TipKit",
            url: "/documentation/TipKit/HighlightingAppFeaturesWithTipKit",
            framework: "TipKit",
            description: "Bring attention to new features in your app by using tips.",
            zipFilename: "tipkit-highlightingappfeatureswithtipkit.zip",
            webURL: "https://developer.apple.com/documentation/TipKit/HighlightingAppFeaturesWithTipKit"
        ),
        SampleCodeEntry(
            title: "Translating text within your app",
            url: "/documentation/Translation/translating-text-within-your-app",
            framework: "Translation",
            description: "Display simple system translations and create custom translation experiences.",
            zipFilename: "translation-translating-text-within-your-app.zip",
            webURL: "https://developer.apple.com/documentation/Translation/translating-text-within-your-app"
        ),
        SampleCodeEntry(
            title: "Add Home Screen quick actions",
            url: "/documentation/UIKit/add-home-screen-quick-actions",
            framework: "UIKit",
            description: "Expose commonly used functionality with static or dynamic 3D Touch Home Screen quick actions.",
            zipFilename: "uikit-add-home-screen-quick-actions.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/add-home-screen-quick-actions"
        ),
        SampleCodeEntry(
            title: "Adding context menus in your app",
            url: "/documentation/UIKit/adding-context-menus-in-your-app",
            framework: "UIKit",
            description: "Provide quick access to useful actions by adding context menus to your iOS app.",
            zipFilename: "uikit-adding-context-menus-in-your-app.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/adding-context-menus-in-your-app"
        ),
        SampleCodeEntry(
            title: "Adding hardware keyboard support to your app",
            url: "/documentation/UIKit/adding-hardware-keyboard-support-to-your-app",
            framework: "UIKit",
            description: "Enhance interactions with your app by handling raw keyboard events, writing custom keyboard shortcuts, and working with gesture recognizers.",
            zipFilename: "uikit-adding-hardware-keyboard-support-to-your-app.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/adding-hardware-keyboard-support-to-your-app"
        ),
        SampleCodeEntry(
            title: "Adding menus and shortcuts to the menu bar and user interface",
            url: "/documentation/UIKit/adding-menus-and-shortcuts-to-the-menu-bar-and-user-interface",
            framework: "UIKit",
            description: "Provide quick access to useful actions by adding menus and keyboard shortcuts to your Mac app built with Mac Catalyst.",
            zipFilename: "uikit-adding-menus-and-shortcuts-to-the-menu-bar-and-user-interface.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/adding-menus-and-shortcuts-to-the-menu-bar-and-user-interface"
        ),
        SampleCodeEntry(
            title: "Adjusting your layout with keyboard layout guide",
            url: "/documentation/UIKit/adjusting-your-layout-with-keyboard-layout-guide",
            framework: "UIKit",
            description: "Respond dynamically to keyboard movement by using the tracking features of the keyboard layout guide.",
            zipFilename: "uikit-adjusting-your-layout-with-keyboard-layout-guide.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/adjusting-your-layout-with-keyboard-layout-guide"
        ),
        SampleCodeEntry(
            title: "Adopting drag and drop in a custom view",
            url: "/documentation/UIKit/adopting-drag-and-drop-in-a-custom-view",
            framework: "UIKit",
            description: "Demonstrates how to enable drag and drop for a `UIImageView` instance.",
            zipFilename: "uikit-adopting-drag-and-drop-in-a-custom-view.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/adopting-drag-and-drop-in-a-custom-view"
        ),
        SampleCodeEntry(
            title: "Adopting drag and drop in a table view",
            url: "/documentation/UIKit/adopting-drag-and-drop-in-a-table-view",
            framework: "UIKit",
            description: "Demonstrates how to enable and implement drag and drop for a table view.",
            zipFilename: "uikit-adopting-drag-and-drop-in-a-table-view.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/adopting-drag-and-drop-in-a-table-view"
        ),
        SampleCodeEntry(
            title: "Adopting hover support for Apple Pencil",
            url: "/documentation/UIKit/adopting-hover-support-for-apple-pencil",
            framework: "UIKit",
            description: "Enhance user feedback for your iPadOS app with a hover preview for Apple Pencil input.",
            zipFilename: "uikit-adopting-hover-support-for-apple-pencil.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/adopting-hover-support-for-apple-pencil"
        ),
        SampleCodeEntry(
            title: "Adopting iOS Dark Mode",
            url: "/documentation/UIKit/adopting-ios-dark-mode",
            framework: "UIKit",
            description: "Adopt Dark Mode in your iOS app by using dynamic colors and visual effects.",
            zipFilename: "uikit-adopting-ios-dark-mode.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/adopting-ios-dark-mode"
        ),
        SampleCodeEntry(
            title: "Adopting menus and UIActions in your user interface",
            url: "/documentation/UIKit/adopting-menus-and-uiactions-in-your-user-interface",
            framework: "UIKit",
            description: "Add menus to your user interface, with built-in button support and bar-button items, and create custom menu experiences.",
            zipFilename: "uikit-adopting-menus-and-uiactions-in-your-user-interface.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/adopting-menus-and-uiactions-in-your-user-interface"
        ),
        SampleCodeEntry(
            title: "Asynchronously loading images into table and collection views",
            url: "/documentation/UIKit/asynchronously-loading-images-into-table-and-collection-views",
            framework: "UIKit",
            description: "Store and fetch images asynchronously to make your app more responsive.",
            zipFilename: "uikit-asynchronously-loading-images-into-table-and-collection-views.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/asynchronously-loading-images-into-table-and-collection-views"
        ),
        SampleCodeEntry(
            title: "Building a document browser app for custom file formats",
            url: "/documentation/UIKit/building-a-document-browser-app-for-custom-file-formats",
            framework: "UIKit",
            description: "Implement a custom document file format to manage user interactions with files on different cloud storage providers.",
            zipFilename: "uikit-building-a-document-browser-app-for-custom-file-formats.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/building-a-document-browser-app-for-custom-file-formats"
        ),
        SampleCodeEntry(
            title: "Building a document browser-based app",
            url: "/documentation/UIKit/building-a-document-browser-based-app",
            framework: "UIKit",
            description: "Use a document browser to provide access to the user’s text files.",
            zipFilename: "uikit-building-a-document-browser-based-app.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/building-a-document-browser-based-app"
        ),
        SampleCodeEntry(
            title: "Building and improving your app with Mac Catalyst",
            url: "/documentation/UIKit/building-and-improving-your-app-with-mac-catalyst",
            framework: "UIKit",
            description: "Improve your iPadOS app with Mac Catalyst by supporting native controls, multiple windows, sharing, printing, menus and keyboard shortcuts.",
            zipFilename: "uikit-building-and-improving-your-app-with-mac-catalyst.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/building-and-improving-your-app-with-mac-catalyst"
        ),
        SampleCodeEntry(
            title: "Building high-performance lists and collection views",
            url: "/documentation/UIKit/building-high-performance-lists-and-collection-views",
            framework: "UIKit",
            description: "Improve the performance of lists and collections in your app with prefetching and image preparation.",
            zipFilename: "uikit-building-high-performance-lists-and-collection-views.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/building-high-performance-lists-and-collection-views"
        ),
        SampleCodeEntry(
            title: "Changing the appearance of selected and highlighted cells",
            url: "/documentation/UIKit/changing-the-appearance-of-selected-and-highlighted-cells",
            framework: "UIKit",
            description: "Provide visual feedback to the user about the state of a cell and the transition between states.",
            zipFilename: "uikit-changing-the-appearance-of-selected-and-highlighted-cells.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/changing-the-appearance-of-selected-and-highlighted-cells"
        ),
        SampleCodeEntry(
            title: "Creating self-sizing table view cells",
            url: "/documentation/UIKit/creating-self-sizing-table-view-cells",
            framework: "UIKit",
            description: "Create table view cells that support Dynamic Type and use system spacing constraints to adjust the spacing surrounding text labels.",
            zipFilename: "uikit-creating-self-sizing-table-view-cells.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/creating-self-sizing-table-view-cells"
        ),
        SampleCodeEntry(
            title: "Customizing an image picker controller",
            url: "/documentation/UIKit/customizing-an-image-picker-controller",
            framework: "UIKit",
            description: "Manage user interactions and present custom information when taking pictures by adding an overlay view to your image picker.",
            zipFilename: "uikit-customizing-an-image-picker-controller.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/customizing-an-image-picker-controller"
        ),
        SampleCodeEntry(
            title: "Customizing and resizing sheets in UIKit",
            url: "/documentation/UIKit/customizing-and-resizing-sheets-in-uikit",
            framework: "UIKit",
            description: "Discover how to create a layered and customized sheet experience in UIKit.",
            zipFilename: "uikit-customizing-and-resizing-sheets-in-uikit.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/customizing-and-resizing-sheets-in-uikit"
        ),
        SampleCodeEntry(
            title: "Customizing collection view layouts",
            url: "/documentation/UIKit/customizing-collection-view-layouts",
            framework: "UIKit",
            description: "Customize a view layout by changing the size of cells in the flow or implementing a mosaic style.",
            zipFilename: "uikit-customizing-collection-view-layouts.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/customizing-collection-view-layouts"
        ),
        SampleCodeEntry(
            title: "Customizing your app’s navigation bar",
            url: "/documentation/UIKit/customizing-your-app-s-navigation-bar",
            framework: "UIKit",
            description: "Create custom titles, prompts, and buttons in your app’s navigation bar.",
            zipFilename: "uikit-customizing-your-app-s-navigation-bar.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/customizing-your-app-s-navigation-bar"
        ),
        SampleCodeEntry(
            title: "Data delivery with drag and drop",
            url: "/documentation/UIKit/data-delivery-with-drag-and-drop",
            framework: "UIKit",
            description: "Share data between iPad apps during a drag and drop operation using an item provider.",
            zipFilename: "uikit-data-delivery-with-drag-and-drop.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/data-delivery-with-drag-and-drop"
        ),
        SampleCodeEntry(
            title: "Detecting changes in the preferences window",
            url: "/documentation/UIKit/detecting-changes-in-the-preferences-window",
            framework: "UIKit",
            description: "Listen for and respond to a user’s preference changes in your Mac app built with Mac Catalyst using Combine.",
            zipFilename: "uikit-detecting-changes-in-the-preferences-window.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/detecting-changes-in-the-preferences-window"
        ),
        SampleCodeEntry(
            title: "Disabling the pull-down gesture for a sheet",
            url: "/documentation/UIKit/disabling-the-pull-down-gesture-for-a-sheet",
            framework: "UIKit",
            description: "Ensure a positive user experience when presenting a view controller as a sheet.",
            zipFilename: "uikit-disabling-the-pull-down-gesture-for-a-sheet.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/disabling-the-pull-down-gesture-for-a-sheet"
        ),
        SampleCodeEntry(
            title: "Display text with a custom layout",
            url: "/documentation/UIKit/display-text-with-a-custom-layout",
            framework: "UIKit",
            description: "Lay out text in a custom-shaped container and apply glyph substitutions.",
            zipFilename: "uikit-display-text-with-a-custom-layout.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/display-text-with-a-custom-layout"
        ),
        SampleCodeEntry(
            title: "Displaying searchable content by using a search controller",
            url: "/documentation/UIKit/displaying-searchable-content-by-using-a-search-controller",
            framework: "UIKit",
            description: "Create a user interface with searchable content in a table view.",
            zipFilename: "uikit-displaying-searchable-content-by-using-a-search-controller.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/displaying-searchable-content-by-using-a-search-controller"
        ),
        SampleCodeEntry(
            title: "Enhancing your iPad app with pointer interactions",
            url: "/documentation/UIKit/enhancing-your-ipad-app-with-pointer-interactions",
            framework: "UIKit",
            description: "Provide a great user experience with pointing devices, by incorporating pointer content effects and shape customizations.",
            zipFilename: "uikit-enhancing-your-ipad-app-with-pointer-interactions.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/enhancing-your-ipad-app-with-pointer-interactions"
        ),
        SampleCodeEntry(
            title: "Enriching your text in text views",
            url: "/documentation/UIKit/enriching-your-text-in-text-views",
            framework: "UIKit",
            description: "Add exclusion paths, text attachments, and text lists to your text, and render it with text views.",
            zipFilename: "uikit-enriching-your-text-in-text-views.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/enriching-your-text-in-text-views"
        ),
        SampleCodeEntry(
            title: "Illustrating the force, altitude, and azimuth properties of touch input",
            url: "/documentation/UIKit/illustrating-the-force-altitude-and-azimuth-properties-of-touch-input",
            framework: "UIKit",
            description: "Capture Apple Pencil and touch input in views.",
            zipFilename: "uikit-illustrating-the-force-altitude-and-azimuth-properties-of-touch-input.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/illustrating-the-force-altitude-and-azimuth-properties-of-touch-input"
        ),
        SampleCodeEntry(
            title: "Implementing Peek and Pop",
            url: "/documentation/UIKit/implementing-peek-and-pop",
            framework: "UIKit",
            description: "Accelerate actions in your app by providing shortcuts to preview content in detail view controllers.",
            zipFilename: "uikit-implementing-peek-and-pop.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/implementing-peek-and-pop"
        ),
        SampleCodeEntry(
            title: "Implementing modern collection views",
            url: "/documentation/UIKit/implementing-modern-collection-views",
            framework: "UIKit",
            description: "Bring compositional layouts to your app and simplify updating your user interface with diffable data sources.",
            zipFilename: "uikit-implementing-modern-collection-views.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/implementing-modern-collection-views"
        ),
        SampleCodeEntry(
            title: "Integrating pointer interactions into your iPad app",
            url: "/documentation/UIKit/integrating-pointer-interactions-into-your-ipad-app",
            framework: "UIKit",
            description: "Support touch interactions in your iPad app by adding pointer interactions to your views.",
            zipFilename: "uikit-integrating-pointer-interactions-into-your-ipad-app.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/integrating-pointer-interactions-into-your-ipad-app"
        ),
        SampleCodeEntry(
            title: "Leveraging touch input for drawing apps",
            url: "/documentation/UIKit/leveraging-touch-input-for-drawing-apps",
            framework: "UIKit",
            description: "Capture touches as a series of strokes and render them efficiently on a drawing canvas.",
            zipFilename: "uikit-leveraging-touch-input-for-drawing-apps.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/leveraging-touch-input-for-drawing-apps"
        ),
        SampleCodeEntry(
            title: "Navigating an app’s user interface using a keyboard",
            url: "/documentation/UIKit/navigating-an-app-s-user-interface-using-a-keyboard",
            framework: "UIKit",
            description: "Navigate between user interface elements using a keyboard and focusable UI elements in iPad apps and apps built with Mac Catalyst.",
            zipFilename: "uikit-navigating-an-app-s-user-interface-using-a-keyboard.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/navigating-an-app-s-user-interface-using-a-keyboard"
        ),
        SampleCodeEntry(
            title: "Prefetching collection view data",
            url: "/documentation/UIKit/prefetching-collection-view-data",
            framework: "UIKit",
            description: "Load data for collection view cells before they display.",
            zipFilename: "uikit-prefetching-collection-view-data.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/prefetching-collection-view-data"
        ),
        SampleCodeEntry(
            title: "Restoring your app’s state",
            url: "/documentation/UIKit/restoring-your-app-s-state",
            framework: "UIKit",
            description: "Provide continuity for the user by preserving current activities.",
            zipFilename: "uikit-restoring-your-app-s-state.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/restoring-your-app-s-state"
        ),
        SampleCodeEntry(
            title: "Selecting multiple items with a two-finger pan gesture",
            url: "/documentation/UIKit/selecting-multiple-items-with-a-two-finger-pan-gesture",
            framework: "UIKit",
            description: "Accelerate user selection of multiple items using the multiselect gesture on table and collection views.",
            zipFilename: "uikit-selecting-multiple-items-with-a-two-finger-pan-gesture.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/selecting-multiple-items-with-a-two-finger-pan-gesture"
        ),
        SampleCodeEntry(
            title: "Showing help tags for views and controls using tooltip interactions",
            url: "/documentation/UIKit/showing-help-tags-for-views-and-controls-using-tooltip-interactions",
            framework: "UIKit",
            description: "Explain the purpose of interface elements by showing a tooltip when a person positions the pointer over the element.",
            zipFilename: "uikit-showing-help-tags-for-views-and-controls-using-tooltip-interactions.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/showing-help-tags-for-views-and-controls-using-tooltip-interactions"
        ),
        SampleCodeEntry(
            title: "Supporting HDR images in your app",
            url: "/documentation/UIKit/supporting-hdr-images-in-your-app",
            framework: "UIKit",
            description: "​ Load, display, edit, and save HDR images using SwiftUI and Core Image. ​",
            zipFilename: "uikit-supporting-hdr-images-in-your-app.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/supporting-hdr-images-in-your-app"
        ),
        SampleCodeEntry(
            title: "Supporting desktop-class features in your iPad app",
            url: "/documentation/UIKit/supporting-desktop-class-features-in-your-ipad-app",
            framework: "UIKit",
            description: "Enhance your iPad app by adding desktop-class features and document support.",
            zipFilename: "uikit-supporting-desktop-class-features-in-your-ipad-app.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/supporting-desktop-class-features-in-your-ipad-app"
        ),
        SampleCodeEntry(
            title: "Supporting gesture interaction in your apps",
            url: "/documentation/UIKit/supporting-gesture-interaction-in-your-apps",
            framework: "UIKit",
            description: "Enrich your app’s user experience by supporting standard and custom gesture interaction.",
            zipFilename: "uikit-supporting-gesture-interaction-in-your-apps.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/supporting-gesture-interaction-in-your-apps"
        ),
        SampleCodeEntry(
            title: "Supporting multiple windows on iPad",
            url: "/documentation/UIKit/supporting-multiple-windows-on-ipad",
            framework: "UIKit",
            description: "Support side-by-side instances of your app’s interface and create new windows.",
            zipFilename: "uikit-supporting-multiple-windows-on-ipad.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/supporting-multiple-windows-on-ipad"
        ),
        SampleCodeEntry(
            title: "Synchronizing documents in the iCloud environment",
            url: "/documentation/UIKit/synchronizing-documents-in-the-icloud-environment",
            framework: "UIKit",
            description: "Manage documents across multiple devices to create a seamless editing and collaboration experience.",
            zipFilename: "uikit-synchronizing-documents-in-the-icloud-environment.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/synchronizing-documents-in-the-icloud-environment"
        ),
        SampleCodeEntry(
            title: "UIKit Catalog: Creating and customizing views and controls",
            url: "/documentation/UIKit/uikit-catalog-creating-and-customizing-views-and-controls",
            framework: "UIKit",
            description: "Customize your app’s user interface with views and controls.",
            zipFilename: "uikit-uikit-catalog-creating-and-customizing-views-and-controls.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/uikit-catalog-creating-and-customizing-views-and-controls"
        ),
        SampleCodeEntry(
            title: "Updating collection views using diffable data sources",
            url: "/documentation/UIKit/updating-collection-views-using-diffable-data-sources",
            framework: "UIKit",
            description: "Streamline the display and update of data in a collection view using a diffable data source that contains identifiers.",
            zipFilename: "uikit-updating-collection-views-using-diffable-data-sources.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/updating-collection-views-using-diffable-data-sources"
        ),
        SampleCodeEntry(
            title: "Using SwiftUI with UIKit",
            url: "/documentation/UIKit/using-swiftui-with-uikit",
            framework: "UIKit",
            description: "Learn how to incorporate SwiftUI views into a UIKit app.",
            zipFilename: "uikit-using-swiftui-with-uikit.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/using-swiftui-with-uikit"
        ),
        SampleCodeEntry(
            title: "Using TextKit 2 to interact with text",
            url: "/documentation/UIKit/using-textkit-2-to-interact-with-text",
            framework: "UIKit",
            description: "Interact with text by managing text selection and inserting custom text elements.###",
            zipFilename: "uikit-using-textkit-2-to-interact-with-text.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/using-textkit-2-to-interact-with-text"
        ),
        SampleCodeEntry(
            title: "Using suggested searches with a search controller",
            url: "/documentation/UIKit/using-suggested-searches-with-a-search-controller",
            framework: "UIKit",
            description: "Create a search interface with a table view of suggested searches.",
            zipFilename: "uikit-using-suggested-searches-with-a-search-controller.zip",
            webURL: "https://developer.apple.com/documentation/UIKit/using-suggested-searches-with-a-search-controller"
        ),
        SampleCodeEntry(
            title: "Schema definitions for third-party DCCs",
            url: "/documentation/USD/schema-definitions-for-third-party-dccs",
            framework: "USD",
            description: "Update your local USD library to add interactive and augmented reality features.",
            zipFilename: "usd-schema-definitions-for-third-party-dccs.zip",
            webURL: "https://developer.apple.com/documentation/USD/schema-definitions-for-third-party-dccs"
        ),
        SampleCodeEntry(
            title: "Handling Communication Notifications and Focus Status Updates",
            url: "/documentation/UserNotifications/handling-communication-notifications-and-focus-status-updates",
            framework: "UserNotifications",
            description: "Create a richer calling and messaging experience in your app by implementing communication notifications and Focus status updates.",
            zipFilename: "usernotifications-handling-communication-notifications-and-focus-status-updates.zip",
            webURL: "https://developer.apple.com/documentation/UserNotifications/handling-communication-notifications-and-focus-status-updates"
        ),
        SampleCodeEntry(
            title: "Implementing Alert Push Notifications",
            url: "/documentation/UserNotifications/implementing-alert-push-notifications",
            framework: "UserNotifications",
            description: "Add visible alert notifications to your app by using the UserNotifications framework.",
            zipFilename: "usernotifications-implementing-alert-push-notifications.zip",
            webURL: "https://developer.apple.com/documentation/UserNotifications/implementing-alert-push-notifications"
        ),
        SampleCodeEntry(
            title: "Implementing Background Push Notifications",
            url: "/documentation/UserNotifications/implementing-background-push-notifications",
            framework: "UserNotifications",
            description: "Add background notifications to your app by using the UserNotifications framework.",
            zipFilename: "usernotifications-implementing-background-push-notifications.zip",
            webURL: "https://developer.apple.com/documentation/UserNotifications/implementing-background-push-notifications"
        ),
        SampleCodeEntry(
            title: "Encoding video for live streaming",
            url: "/documentation/VideoToolbox/encoding-video-for-live-streaming",
            framework: "VideoToolbox",
            description: "Configure a compression session to encode video for live streaming.",
            zipFilename: "videotoolbox-encoding-video-for-live-streaming.zip",
            webURL: "https://developer.apple.com/documentation/VideoToolbox/encoding-video-for-live-streaming"
        ),
        SampleCodeEntry(
            title: "Encoding video for low-latency conferencing",
            url: "/documentation/VideoToolbox/encoding-video-for-low-latency-conferencing",
            framework: "VideoToolbox",
            description: "Configure a compression session to optimize encoding for video-conferencing apps.",
            zipFilename: "videotoolbox-encoding-video-for-low-latency-conferencing.zip",
            webURL: "https://developer.apple.com/documentation/VideoToolbox/encoding-video-for-low-latency-conferencing"
        ),
        SampleCodeEntry(
            title: "Encoding video for offline transcoding",
            url: "/documentation/VideoToolbox/encoding-video-for-offline-transcoding",
            framework: "VideoToolbox",
            description: "Configure a compression session to transcode video in offline workflows.",
            zipFilename: "videotoolbox-encoding-video-for-offline-transcoding.zip",
            webURL: "https://developer.apple.com/documentation/VideoToolbox/encoding-video-for-offline-transcoding"
        ),
        SampleCodeEntry(
            title: "Enhancing your app with machine learning-based video effects",
            url: "/documentation/VideoToolbox/enhancing-your-app-with-machine-learning-based-video-effects",
            framework: "VideoToolbox",
            description: "Add powerful effects to your videos using the VideoToolbox VTFrameProcessor API.",
            zipFilename: "videotoolbox-enhancing-your-app-with-machine-learning-based-video-effects.zip",
            webURL: "https://developer.apple.com/documentation/VideoToolbox/enhancing-your-app-with-machine-learning-based-video-effects"
        ),
        SampleCodeEntry(
            title: "Running GUI Linux in a virtual machine on a Mac",
            url: "/documentation/Virtualization/running-gui-linux-in-a-virtual-machine-on-a-mac",
            framework: "Virtualization",
            description: "Install and run GUI Linux in a virtual machine using the Virtualization framework.",
            zipFilename: "virtualization-running-gui-linux-in-a-virtual-machine-on-a-mac.zip",
            webURL: "https://developer.apple.com/documentation/Virtualization/running-gui-linux-in-a-virtual-machine-on-a-mac"
        ),
        SampleCodeEntry(
            title: "Running Linux in a Virtual Machine",
            url: "/documentation/Virtualization/running-linux-in-a-virtual-machine",
            framework: "Virtualization",
            description: "Run a Linux operating system on your Mac using the Virtualization framework.",
            zipFilename: "virtualization-running-linux-in-a-virtual-machine.zip",
            webURL: "https://developer.apple.com/documentation/Virtualization/running-linux-in-a-virtual-machine"
        ),
        SampleCodeEntry(
            title: "Running macOS in a virtual machine on Apple silicon",
            url: "/documentation/Virtualization/running-macos-in-a-virtual-machine-on-apple-silicon",
            framework: "Virtualization",
            description: "Install and run macOS in a virtual machine using the Virtualization framework.",
            zipFilename: "virtualization-running-macos-in-a-virtual-machine-on-apple-silicon.zip",
            webURL: "https://developer.apple.com/documentation/Virtualization/running-macos-in-a-virtual-machine-on-apple-silicon"
        ),
        SampleCodeEntry(
            title: "Aligning Similar Images",
            url: "/documentation/Vision/aligning-similar-images",
            framework: "Vision",
            description: "Construct a composite image from images that capture the same scene.",
            zipFilename: "vision-aligning-similar-images.zip",
            webURL: "https://developer.apple.com/documentation/Vision/aligning-similar-images"
        ),
        SampleCodeEntry(
            title: "Analyzing Image Similarity with Feature Print",
            url: "/documentation/Vision/analyzing-image-similarity-with-feature-print",
            framework: "Vision",
            description: "Generate a feature print to compute distance between images.",
            zipFilename: "vision-analyzing-image-similarity-with-feature-print.zip",
            webURL: "https://developer.apple.com/documentation/Vision/analyzing-image-similarity-with-feature-print"
        ),
        SampleCodeEntry(
            title: "Analyzing a selfie and visualizing its content",
            url: "/documentation/Vision/analyzing-a-selfie-and-visualizing-its-content",
            framework: "Vision",
            description: "Calculate face-capture quality and visualize facial features for a collection of images using the Vision framework.",
            zipFilename: "vision-analyzing-a-selfie-and-visualizing-its-content.zip",
            webURL: "https://developer.apple.com/documentation/Vision/analyzing-a-selfie-and-visualizing-its-content"
        ),
        SampleCodeEntry(
            title: "Applying Matte Effects to People in Images and Video",
            url: "/documentation/Vision/applying-matte-effects-to-people-in-images-and-video",
            framework: "Vision",
            description: "Generate image masks for people automatically by using semantic person-segmentation.",
            zipFilename: "vision-applying-matte-effects-to-people-in-images-and-video.zip",
            webURL: "https://developer.apple.com/documentation/Vision/applying-matte-effects-to-people-in-images-and-video"
        ),
        SampleCodeEntry(
            title: "Applying visual effects to foreground subjects",
            url: "/documentation/Vision/applying-visual-effects-to-foreground-subjects",
            framework: "Vision",
            description: "Segment the foreground subjects of an image and composite them to a new background with visual effects.",
            zipFilename: "vision-applying-visual-effects-to-foreground-subjects.zip",
            webURL: "https://developer.apple.com/documentation/Vision/applying-visual-effects-to-foreground-subjects"
        ),
        SampleCodeEntry(
            title: "Building a feature-rich app for sports analysis",
            url: "/documentation/Vision/building-a-feature-rich-app-for-sports-analysis",
            framework: "Vision",
            description: "Detect and classify human activity in real time using computer vision and machine learning.",
            zipFilename: "vision-building-a-feature-rich-app-for-sports-analysis.zip",
            webURL: "https://developer.apple.com/documentation/Vision/building-a-feature-rich-app-for-sports-analysis"
        ),
        SampleCodeEntry(
            title: "Classifying images for categorization and search",
            url: "/documentation/Vision/classifying-images-for-categorization-and-search",
            framework: "Vision",
            description: "Analyze and label images using a Vision classification request.",
            zipFilename: "vision-classifying-images-for-categorization-and-search.zip",
            webURL: "https://developer.apple.com/documentation/Vision/classifying-images-for-categorization-and-search"
        ),
        SampleCodeEntry(
            title: "Detecting Hand Poses with Vision",
            url: "/documentation/Vision/detecting-hand-poses-with-vision",
            framework: "Vision",
            description: "Create a virtual drawing app by using Vision’s capability to detect hand poses.",
            zipFilename: "vision-detecting-hand-poses-with-vision.zip",
            webURL: "https://developer.apple.com/documentation/Vision/detecting-hand-poses-with-vision"
        ),
        SampleCodeEntry(
            title: "Detecting Objects in Still Images",
            url: "/documentation/Vision/detecting-objects-in-still-images",
            framework: "Vision",
            description: "Locate and demarcate rectangles, faces, barcodes, and text in images using the Vision framework.",
            zipFilename: "vision-detecting-objects-in-still-images.zip",
            webURL: "https://developer.apple.com/documentation/Vision/detecting-objects-in-still-images"
        ),
        SampleCodeEntry(
            title: "Detecting animal body poses with Vision",
            url: "/documentation/Vision/detecting-animal-body-poses-with-vision",
            framework: "Vision",
            description: "Draw the skeleton of an animal by using Vision’s capability to detect animal body poses.",
            zipFilename: "vision-detecting-animal-body-poses-with-vision.zip",
            webURL: "https://developer.apple.com/documentation/Vision/detecting-animal-body-poses-with-vision"
        ),
        SampleCodeEntry(
            title: "Detecting human body poses in 3D with Vision",
            url: "/documentation/Vision/detecting-human-body-poses-in-3d-with-vision",
            framework: "Vision",
            description: "Render skeletons of 3D body pose points in a scene overlaying the input image.",
            zipFilename: "vision-detecting-human-body-poses-in-3d-with-vision.zip",
            webURL: "https://developer.apple.com/documentation/Vision/detecting-human-body-poses-in-3d-with-vision"
        ),
        SampleCodeEntry(
            title: "Detecting moving objects in a video",
            url: "/documentation/Vision/detecting-moving-objects-in-a-video",
            framework: "Vision",
            description: "Identify the trajectory of a thrown object by using Vision.",
            zipFilename: "vision-detecting-moving-objects-in-a-video.zip",
            webURL: "https://developer.apple.com/documentation/Vision/detecting-moving-objects-in-a-video"
        ),
        SampleCodeEntry(
            title: "Extracting phone numbers from text in images",
            url: "/documentation/Vision/extracting-phone-numbers-from-text-in-images",
            framework: "Vision",
            description: "Analyze and filter phone numbers from text in live capture by using Vision.",
            zipFilename: "vision-extracting-phone-numbers-from-text-in-images.zip",
            webURL: "https://developer.apple.com/documentation/Vision/extracting-phone-numbers-from-text-in-images"
        ),
        SampleCodeEntry(
            title: "Generating high-quality thumbnails from videos",
            url: "/documentation/Vision/generating-thumbnails-from-videos",
            framework: "Vision",
            description: "Identify the most visually pleasing frames in a video by using the image-aesthetics scores request.",
            zipFilename: "vision-generating-thumbnails-from-videos.zip",
            webURL: "https://developer.apple.com/documentation/Vision/generating-thumbnails-from-videos"
        ),
        SampleCodeEntry(
            title: "Highlighting Areas of Interest in an Image Using Saliency",
            url: "/documentation/Vision/highlighting-areas-of-interest-in-an-image-using-saliency",
            framework: "Vision",
            description: "Quantify and visualize where people are likely to look in an image.",
            zipFilename: "vision-highlighting-areas-of-interest-in-an-image-using-saliency.zip",
            webURL: "https://developer.apple.com/documentation/Vision/highlighting-areas-of-interest-in-an-image-using-saliency"
        ),
        SampleCodeEntry(
            title: "Locating and displaying recognized text",
            url: "/documentation/Vision/locating-and-displaying-recognized-text",
            framework: "Vision",
            description: "Perform text recognition on a photo using the Vision framework’s text-recognition request.",
            zipFilename: "vision-locating-and-displaying-recognized-text.zip",
            webURL: "https://developer.apple.com/documentation/Vision/locating-and-displaying-recognized-text"
        ),
        SampleCodeEntry(
            title: "Recognizing Objects in Live Capture",
            url: "/documentation/Vision/recognizing-objects-in-live-capture",
            framework: "Vision",
            description: "Apply Vision algorithms to identify objects in real-time video.",
            zipFilename: "vision-recognizing-objects-in-live-capture.zip",
            webURL: "https://developer.apple.com/documentation/Vision/recognizing-objects-in-live-capture"
        ),
        SampleCodeEntry(
            title: "Recognizing tables within a document",
            url: "/documentation/Vision/recognize-tables-within-a-document",
            framework: "Vision",
            description: "Scan a document containing a contact table and extract the content within the table in a formatted way.",
            zipFilename: "vision-recognize-tables-within-a-document.zip",
            webURL: "https://developer.apple.com/documentation/Vision/recognize-tables-within-a-document"
        ),
        SampleCodeEntry(
            title: "Segmenting and colorizing individuals from a surrounding scene",
            url: "/documentation/Vision/segmenting-and-colorizing-individuals-from-a-surrounding-scene",
            framework: "Vision",
            description: "Use the Vision framework to isolate and apply colors to people in an image.",
            zipFilename: "vision-segmenting-and-colorizing-individuals-from-a-surrounding-scene.zip",
            webURL: "https://developer.apple.com/documentation/Vision/segmenting-and-colorizing-individuals-from-a-surrounding-scene"
        ),
        SampleCodeEntry(
            title: "Selecting a selfie based on capture quality",
            url: "/documentation/Vision/selecting-a-selfie-based-on-capture-quality",
            framework: "Vision",
            description: "Compare face-capture quality in a set of images by using Vision.",
            zipFilename: "vision-selecting-a-selfie-based-on-capture-quality.zip",
            webURL: "https://developer.apple.com/documentation/Vision/selecting-a-selfie-based-on-capture-quality"
        ),
        SampleCodeEntry(
            title: "Tracking Multiple Objects or Rectangles in Video",
            url: "/documentation/Vision/tracking-multiple-objects-or-rectangles-in-video",
            framework: "Vision",
            description: "Apply Vision algorithms to track objects or rectangles throughout a video.",
            zipFilename: "vision-tracking-multiple-objects-or-rectangles-in-video.zip",
            webURL: "https://developer.apple.com/documentation/Vision/tracking-multiple-objects-or-rectangles-in-video"
        ),
        SampleCodeEntry(
            title: "Tracking the User’s Face in Real Time",
            url: "/documentation/Vision/tracking-the-user-s-face-in-real-time",
            framework: "Vision",
            description: "Detect and track faces from the selfie cam feed in real time.",
            zipFilename: "vision-tracking-the-user-s-face-in-real-time.zip",
            webURL: "https://developer.apple.com/documentation/Vision/tracking-the-user-s-face-in-real-time"
        ),
        SampleCodeEntry(
            title: "Training a Create ML Model to Classify Flowers",
            url: "/documentation/Vision/training-a-create-ml-model-to-classify-flowers",
            framework: "Vision",
            description: "Train a flower classifier using Create ML in Swift Playgrounds, and apply the resulting model to real-time image classification using Vision.###",
            zipFilename: "vision-training-a-create-ml-model-to-classify-flowers.zip",
            webURL: "https://developer.apple.com/documentation/Vision/training-a-create-ml-model-to-classify-flowers"
        ),
        SampleCodeEntry(
            title: "Example Order Packages",
            url: "/documentation/WalletOrders/example-order-packages",
            framework: "WalletOrders",
            description: "Edit, build, and add example order packages to Wallet.",
            zipFilename: "walletorders-example-order-packages.zip",
            webURL: "https://developer.apple.com/documentation/WalletOrders/example-order-packages"
        ),
        SampleCodeEntry(
            title: "Transferring data with Watch Connectivity",
            url: "/documentation/WatchConnectivity/transferring-data-with-watch-connectivity",
            framework: "WatchConnectivity",
            description: "Transfer data between a watchOS app and its companion iOS app.",
            zipFilename: "watchconnectivity-transferring-data-with-watch-connectivity.zip",
            webURL: "https://developer.apple.com/documentation/WatchConnectivity/transferring-data-with-watch-connectivity"
        ),
        SampleCodeEntry(
            title: "Interacting with Bluetooth peripherals during background app refresh",
            url: "/documentation/WatchKit/interacting-with-bluetooth-peripherals-during-background-app-refresh",
            framework: "WatchKit",
            description: "Keep your complications up-to-date by reading values from a Bluetooth peripheral while your app is running in the background.",
            zipFilename: "watchkit-interacting-with-bluetooth-peripherals-during-background-app-refresh.zip",
            webURL: "https://developer.apple.com/documentation/WatchKit/interacting-with-bluetooth-peripherals-during-background-app-refresh"
        ),
        SampleCodeEntry(
            title: "Viewing Desktop or Mobile Web Content Using a Web View",
            url: "/documentation/WebKit/viewing-desktop-or-mobile-web-content-using-a-web-view",
            framework: "WebKit",
            description: "Implement a simple iPad web browser that can view either the desktop or mobile version of a website.",
            zipFilename: "webkit-viewing-desktop-or-mobile-web-content-using-a-web-view.zip",
            webURL: "https://developer.apple.com/documentation/WebKit/viewing-desktop-or-mobile-web-content-using-a-web-view"
        ),
        SampleCodeEntry(
            title: "Building peer-to-peer apps",
            url: "/documentation/WiFiAware/Building-peer-to-peer-apps",
            framework: "WiFiAware",
            description: "Communicate with nearby devices over a secure, high-throughput, low-latency connection by using Wi-Fi Aware.",
            zipFilename: "wifiaware-building-peer-to-peer-apps.zip",
            webURL: "https://developer.apple.com/documentation/WiFiAware/Building-peer-to-peer-apps"
        ),
        SampleCodeEntry(
            title: "Emoji Rangers: Supporting Live Activities, interactivity, and animations",
            url: "/documentation/WidgetKit/emoji-rangers-supporting-live-activities-interactivity-and-animations",
            framework: "WidgetKit",
            description: "Offer Live Activities, controls, animate data updates, and add interactivity to widgets.",
            zipFilename: "widgetkit-emoji-rangers-supporting-live-activities-interactivity-and-animations.zip",
            webURL: "https://developer.apple.com/documentation/WidgetKit/emoji-rangers-supporting-live-activities-interactivity-and-animations"
        ),
        SampleCodeEntry(
            title: "Customizing workouts with WorkoutKit",
            url: "/documentation/WorkoutKit/customizing-workouts-with-workoutkit",
            framework: "WorkoutKit",
            description: "Create, preview, and sync workouts for use in the Workout app on Apple Watch.",
            zipFilename: "workoutkit-customizing-workouts-with-workoutkit.zip",
            webURL: "https://developer.apple.com/documentation/WorkoutKit/customizing-workouts-with-workoutkit"
        ),
        SampleCodeEntry(
            title: "Autosizing views for localization in iOS",
            url: "/documentation/Xcode/autosizing-views-for-localization-in-ios",
            framework: "Xcode",
            description: "Add auto layout constraints to your app to achieve localizable views.",
            zipFilename: "xcode-autosizing-views-for-localization-in-ios.zip",
            webURL: "https://developer.apple.com/documentation/Xcode/autosizing-views-for-localization-in-ios"
        ),
        SampleCodeEntry(
            title: "Configuring your app to use alternate app icons",
            url: "/documentation/Xcode/configuring-your-app-to-use-alternate-app-icons",
            framework: "Xcode",
            description: "Add alternate app icons to your app, and let people choose which icon to display.",
            zipFilename: "xcode-configuring-your-app-to-use-alternate-app-icons.zip",
            webURL: "https://developer.apple.com/documentation/Xcode/configuring-your-app-to-use-alternate-app-icons"
        ),
        SampleCodeEntry(
            title: "Creating custom modelers for intelligent instruments",
            url: "/documentation/Xcode/creating-custom-modelers-for-intelligent-instruments",
            framework: "Xcode",
            description: "Create Custom Modelers with the CLIPS language and learn how the embedded rules engine works.",
            zipFilename: "xcode-creating-custom-modelers-for-intelligent-instruments.zip",
            webURL: "https://developer.apple.com/documentation/Xcode/creating-custom-modelers-for-intelligent-instruments"
        ),
        SampleCodeEntry(
            title: "Localization-friendly layouts in macOS",
            url: "/documentation/Xcode/localization-friendly-layouts-in-macos",
            framework: "Xcode",
            description: "This project demonstrates localization-friendly auto layout constraints.",
            zipFilename: "xcode-localization-friendly-layouts-in-macos.zip",
            webURL: "https://developer.apple.com/documentation/Xcode/localization-friendly-layouts-in-macos"
        ),
        SampleCodeEntry(
            title: "Localizing Landmarks",
            url: "/documentation/Xcode/localizing-landmarks",
            framework: "Xcode",
            description: "Add localizations to the Landmarks sample code project.",
            zipFilename: "xcode-localizing-landmarks.zip",
            webURL: "https://developer.apple.com/documentation/Xcode/localizing-landmarks"
        ),
        SampleCodeEntry(
            title: "SlothCreator: Building DocC documentation in Xcode",
            url: "/documentation/Xcode/slothcreator-building-docc-documentation-in-xcode",
            framework: "Xcode",
            description: "Build DocC documentation for a Swift package that contains a DocC Catalog.###",
            zipFilename: "xcode-slothcreator-building-docc-documentation-in-xcode.zip",
            webURL: "https://developer.apple.com/documentation/Xcode/slothcreator-building-docc-documentation-in-xcode"
        ),
        SampleCodeEntry(
            title: "Building local experiences with room tracking",
            url: "/documentation/arkit/building_local_experiences_with_room_tracking",
            framework: "arkit",
            description: "Use room tracking in visionOS to provide custom interactions with physical spaces.",
            zipFilename: "arkit-building_local_experiences_with_room_tracking.zip",
            webURL: "https://developer.apple.com/documentation/arkit/building_local_experiences_with_room_tracking"
        ),
        SampleCodeEntry(
            title: "Storing CryptoKit Keys in the Keychain",
            url: "/documentation/cryptokit/storing_cryptokit_keys_in_the_keychain",
            framework: "cryptokit",
            description: "Convert between strongly typed cryptographic keys and native keychain types.###",
            zipFilename: "cryptokit-storing_cryptokit_keys_in_the_keychain.zip",
            webURL: "https://developer.apple.com/documentation/cryptokit/storing_cryptokit_keys_in_the_keychain"
        ),
        SampleCodeEntry(
            title: "Building a Localized Food-Ordering App",
            url: "/documentation/foundation/building_a_localized_food-ordering_app",
            framework: "foundation",
            description: "Format, style, and localize your app’s text for use in multiple languages with string formatting, attributed strings, and automatic grammar agreement.",
            zipFilename: "foundation-building_a_localized_food-ordering_app.zip",
            webURL: "https://developer.apple.com/documentation/foundation/building_a_localized_food-ordering_app"
        ),
        SampleCodeEntry(
            title: "Displaying Human-Friendly Content",
            url: "/documentation/foundation/displaying_human-friendly_content",
            framework: "foundation",
            description: "Convert data into readable strings or Swift objects using formatters.",
            zipFilename: "foundation-displaying_human-friendly_content.zip",
            webURL: "https://developer.apple.com/documentation/foundation/displaying_human-friendly_content"
        ),
        SampleCodeEntry(
            title: "Increasing App Usage with Suggestions Based on User Activities",
            url: "/documentation/foundation/task_management/increasing_app_usage_with_suggestions_based_on_user_activities",
            framework: "foundation",
            description: "Provide a continuous user experience by capturing information from your app and displaying this information as proactive suggestions across the system.",
            zipFilename: "foundation-task_management-increasing_app_usage_with_suggestions_based_on_user_activities.zip",
            webURL: "https://developer.apple.com/documentation/foundation/task_management/increasing_app_usage_with_suggestions_based_on_user_activities"
        ),
        SampleCodeEntry(
            title: "Synchronizing App Preferences with iCloud",
            url: "/documentation/foundation/icloud/synchronizing_app_preferences_with_icloud",
            framework: "foundation",
            description: "Store app preferences in iCloud and share them among instances of your app running on a user’s connected devices.",
            zipFilename: "foundation-icloud-synchronizing_app_preferences_with_icloud.zip",
            webURL: "https://developer.apple.com/documentation/foundation/icloud/synchronizing_app_preferences_with_icloud"
        ),
        SampleCodeEntry(
            title: "Using JSON with Custom Types",
            url: "/documentation/foundation/archives_and_serialization/using_json_with_custom_types",
            framework: "foundation",
            description: "Encode and decode JSON data, regardless of its structure, using Swift’s JSON support.###",
            zipFilename: "foundation-archives_and_serialization-using_json_with_custom_types.zip",
            webURL: "https://developer.apple.com/documentation/foundation/archives_and_serialization/using_json_with_custom_types"
        ),
        SampleCodeEntry(
            title: "Drawing content in a group session",
            url: "/documentation/groupactivities/drawing_content_in_a_group_session",
            framework: "groupactivities",
            description: "Invite your friends to draw on a shared canvas while on a FaceTime call.",
            zipFilename: "groupactivities-drawing_content_in_a_group_session.zip",
            webURL: "https://developer.apple.com/documentation/groupactivities/drawing_content_in_a_group_session"
        ),
        SampleCodeEntry(
            title: "Communicating with a Modem on a Serial Port",
            url: "/documentation/iokit/communicating_with_a_modem_on_a_serial_port",
            framework: "iokit",
            description: "Find and connect to a modem attached to a serial port using IOKit.",
            zipFilename: "iokit-communicating_with_a_modem_on_a_serial_port.zip",
            webURL: "https://developer.apple.com/documentation/iokit/communicating_with_a_modem_on_a_serial_port"
        ),
        SampleCodeEntry(
            title: "Building a Simple USB Driver",
            url: "/documentation/kernel/hardware_families/usb/building_a_simple_usb_driver",
            framework: "kernel",
            description: "Set up and load a driver that logs output to the Console app.",
            zipFilename: "kernel-hardware_families-usb-building_a_simple_usb_driver.zip",
            webURL: "https://developer.apple.com/documentation/kernel/hardware_families/usb/building_a_simple_usb_driver"
        ),
        SampleCodeEntry(
            title: "Explore a location with a highly detailed map and Look Around",
            url: "/documentation/mapkit/mapkit_for_appkit_and_uikit/explore_a_location_with_a_highly_detailed_map_and_look_around",
            framework: "mapkit",
            description: "Display a richly detailed map, and use Look Around to experience an interactive view of landmarks.",
            zipFilename: "mapkit-mapkit_for_appkit_and_uikit-explore_a_location_with_a_highly_detailed_map_and_look_around.zip",
            webURL: "https://developer.apple.com/documentation/mapkit/mapkit_for_appkit_and_uikit/explore_a_location_with_a_highly_detailed_map_and_look_around"
        ),
        SampleCodeEntry(
            title: "Optimizing Map Views with Filtering and Camera Constraints",
            url: "/documentation/mapkit/mkmapview/optimizing_map_views_with_filtering_and_camera_constraints",
            framework: "mapkit",
            description: "Display a map that is relevant to the user by filtering points of interest and search results, and constraining the visible region.",
            zipFilename: "mapkit-mkmapview-optimizing_map_views_with_filtering_and_camera_constraints.zip",
            webURL: "https://developer.apple.com/documentation/mapkit/mkmapview/optimizing_map_views_with_filtering_and_camera_constraints"
        ),
        SampleCodeEntry(
            title: "Explore more content with MusicKit",
            url: "/documentation/musickit/explore_more_content_with_musickit",
            framework: "musickit",
            description: "Track your outdoor runs with access to the Apple Music catalog, personal recommendations, and your own personal music library.",
            zipFilename: "musickit-explore_more_content_with_musickit.zip",
            webURL: "https://developer.apple.com/documentation/musickit/explore_more_content_with_musickit"
        ),
        SampleCodeEntry(
            title: "Using MusicKit to Integrate with Apple Music",
            url: "/documentation/musickit/using_musickit_to_integrate_with_apple_music",
            framework: "musickit",
            description: "Find an album in Apple Music that corresponds to a CD in a user’s collection, and present the information for the album.",
            zipFilename: "musickit-using_musickit_to_integrate_with_apple_music.zip",
            webURL: "https://developer.apple.com/documentation/musickit/using_musickit_to_integrate_with_apple_music"
        ),
        SampleCodeEntry(
            title: "Connecting a network driver",
            url: "/documentation/pcidriverkit/connecting_a_network_driver",
            framework: "pcidriverkit",
            description: "Create an Ethernet driver that interfaces with the system’s network protocol stack.",
            zipFilename: "pcidriverkit-connecting_a_network_driver.zip",
            webURL: "https://developer.apple.com/documentation/pcidriverkit/connecting_a_network_driver"
        ),
        SampleCodeEntry(
            title: "Altering RealityKit Rendering with Shader Functions",
            url: "/documentation/realitykit/altering_realitykit_rendering_with_shader_functions",
            framework: "realitykit",
            description: "Create rendering effects by writing surface shaders and geometry modifiers.",
            zipFilename: "realitykit-altering_realitykit_rendering_with_shader_functions.zip",
            webURL: "https://developer.apple.com/documentation/realitykit/altering_realitykit_rendering_with_shader_functions"
        ),
        SampleCodeEntry(
            title: "Controlling Entity Collisions in RealityKit",
            url: "/documentation/realitykit/controlling_entity_collisions_in_realitykit",
            framework: "realitykit",
            description: "Create collision filters to control which objects collide.",
            zipFilename: "realitykit-controlling_entity_collisions_in_realitykit.zip",
            webURL: "https://developer.apple.com/documentation/realitykit/controlling_entity_collisions_in_realitykit"
        ),
        SampleCodeEntry(
            title: "WWDC21 Challenge: Framework Freestyle",
            url: "/documentation/realitykit/wwdc21_challenge_framework_freestyle",
            framework: "realitykit",
            description: "An AR experience that randomly selects a programming framework and maps it onto the user’s face.###",
            zipFilename: "realitykit-wwdc21_challenge_framework_freestyle.zip",
            webURL: "https://developer.apple.com/documentation/realitykit/wwdc21_challenge_framework_freestyle"
        ),
        SampleCodeEntry(
            title: "TicTacFish: Implementing a game using distributed actors",
            url: "/documentation/swift/tictacfish_implementing_a_game_using_distributed_actors",
            framework: "swift",
            description: "Use distributed actors to take your Swift concurrency and actor-based apps beyond a single process.",
            zipFilename: "swift-tictacfish_implementing_a_game_using_distributed_actors.zip",
            webURL: "https://developer.apple.com/documentation/swift/tictacfish_implementing_a_game_using_distributed_actors"
        ),
        SampleCodeEntry(
            title: "Updating an App to Use Swift Concurrency",
            url: "/documentation/swift/updating_an_app_to_use_swift_concurrency",
            framework: "swift",
            description: "Improve your app’s performance by refactoring your code to take advantage of asynchronous functions in Swift.###",
            zipFilename: "swift-updating_an_app_to_use_swift_concurrency.zip",
            webURL: "https://developer.apple.com/documentation/swift/updating_an_app_to_use_swift_concurrency"
        ),
        SampleCodeEntry(
            title: "Building custom views in SwiftUI",
            url: "/documentation/swiftui/building_custom_views_in_swiftui",
            framework: "swiftui",
            description: "Create a custom view with data-driven transitions and animations in SwiftUI.",
            zipFilename: "swiftui-building_custom_views_in_swiftui.zip",
            webURL: "https://developer.apple.com/documentation/swiftui/building_custom_views_in_swiftui"
        ),
        SampleCodeEntry(
            title: "Creating Accessible Views",
            url: "/documentation/swiftui/creating_accessible_views",
            framework: "swiftui",
            description: "Make your app accessible to everyone by applying accessibility modifiers to your SwiftUI views.",
            zipFilename: "swiftui-creating_accessible_views.zip",
            webURL: "https://developer.apple.com/documentation/swiftui/creating_accessible_views"
        ),
        SampleCodeEntry(
            title: "Loading and Displaying a Large Data Feed",
            url: "/documentation/swiftui/loading_and_displaying_a_large_data_feed",
            framework: "swiftui",
            description: "Consume data in the background, and lower memory use by batching imports and preventing duplicate records.",
            zipFilename: "swiftui-loading_and_displaying_a_large_data_feed.zip",
            webURL: "https://developer.apple.com/documentation/swiftui/loading_and_displaying_a_large_data_feed"
        ),
        SampleCodeEntry(
            title: "Binding JSON data to TVML documents",
            url: "/documentation/tvmljs/binding_json_data_to_tvml_documents",
            framework: "tvmljs",
            description: "Create full-fledged TVML documents by using data binding and queries on simplified TVML files.",
            zipFilename: "tvmljs-binding_json_data_to_tvml_documents.zip",
            webURL: "https://developer.apple.com/documentation/tvmljs/binding_json_data_to_tvml_documents"
        ),
        SampleCodeEntry(
            title: "Creating a Client-Server TVML App",
            url: "/documentation/tvmljs/creating_a_client-server_tvml_app",
            framework: "tvmljs",
            description: "Display and navigate between TVML documents on Apple TV by retrieving and parsing information from a remote server.",
            zipFilename: "tvmljs-creating_a_client-server_tvml_app.zip",
            webURL: "https://developer.apple.com/documentation/tvmljs/creating_a_client-server_tvml_app"
        ),
        SampleCodeEntry(
            title: "Playing Media in a Client-Server App",
            url: "/documentation/tvmljs/playing_media_in_a_client-server_app",
            framework: "tvmljs",
            description: "Play media items in a client-server app using the built-in media player for TVMLKit JS.",
            zipFilename: "tvmljs-playing_media_in_a_client-server_app.zip",
            webURL: "https://developer.apple.com/documentation/tvmljs/playing_media_in_a_client-server_app"
        ),
        SampleCodeEntry(
            title: "Responding to User Interaction",
            url: "/documentation/tvmljs/responding_to_user_interaction",
            framework: "tvmljs",
            description: "Update onscreen information by adding event listeners to your Apple TV app.",
            zipFilename: "tvmljs-responding_to_user_interaction.zip",
            webURL: "https://developer.apple.com/documentation/tvmljs/responding_to_user_interaction"
        ),
        SampleCodeEntry(
            title: "Accessing the main camera",
            url: "/documentation/visionOS/accessing-the-main-camera",
            framework: "visionOS",
            description: "Add camera-based features to enterprise apps.",
            zipFilename: "visionos-accessing-the-main-camera.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/accessing-the-main-camera"
        ),
        SampleCodeEntry(
            title: "Adding a depth effect to text in visionOS",
            url: "/documentation/visionOS/adding-a-depth-effect-to-text-in-visionOS",
            framework: "visionOS",
            description: "Create text that expands out of a window using stacked SwiftUI text views.",
            zipFilename: "visionos-adding-a-depth-effect-to-text-in-visionos.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/adding-a-depth-effect-to-text-in-visionOS"
        ),
        SampleCodeEntry(
            title: "Applying mesh to real-world surroundings",
            url: "/documentation/visionOS/applying-mesh-to-real-world-surroundings",
            framework: "visionOS",
            description: "Add a layer of mesh to objects in the real world, using scene reconstruction in ARKit.",
            zipFilename: "visionos-applying-mesh-to-real-world-surroundings.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/applying-mesh-to-real-world-surroundings"
        ),
        SampleCodeEntry(
            title: "BOT-anist",
            url: "/documentation/visionOS/BOT-anist",
            framework: "visionOS",
            description: "Build a multiplatform app that uses windows, volumes, and animations to create a robot botanist’s greenhouse.",
            zipFilename: "visionos-bot-anist.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/BOT-anist"
        ),
        SampleCodeEntry(
            title: "Building an immersive media viewing experience",
            url: "/documentation/visionOS/building-an-immersive-media-viewing-experience",
            framework: "visionOS",
            description: "Add a deeper level of immersion to media playback in your app with RealityKit and Reality Composer Pro.",
            zipFilename: "visionos-building-an-immersive-media-viewing-experience.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/building-an-immersive-media-viewing-experience"
        ),
        SampleCodeEntry(
            title: "Building local experiences with room tracking",
            url: "/documentation/visionOS/building-local-experiences-with-room-tracking",
            framework: "visionOS",
            description: "Use room tracking in visionOS to provide custom interactions with physical spaces.",
            zipFilename: "visionos-building-local-experiences-with-room-tracking.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/building-local-experiences-with-room-tracking"
        ),
        SampleCodeEntry(
            title: "Canyon Crosser: Building a volumetric hike-planning app",
            url: "/documentation/visionOS/canyon-crosser-building-a-volumetric-hike-planning-app",
            framework: "visionOS",
            description: "Create a hike planning app using SwiftUI and RealityKit.",
            zipFilename: "visionos-canyon-crosser-building-a-volumetric-hike-planning-app.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/canyon-crosser-building-a-volumetric-hike-planning-app"
        ),
        SampleCodeEntry(
            title: "Creating 2D shapes with SwiftUI",
            url: "/documentation/visionOS/creating-2d-shapes-in-visionos-with-swiftui",
            framework: "visionOS",
            description: "Draw two-dimensional shapes in your visionOS app with SwiftUI shapes or with your custom shapes.",
            zipFilename: "visionos-creating-2d-shapes-in-visionos-with-swiftui.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/creating-2d-shapes-in-visionos-with-swiftui"
        ),
        SampleCodeEntry(
            title: "Creating 3D entities with RealityKit",
            url: "/documentation/visionOS/creating-3d-entities-with-realitykit",
            framework: "visionOS",
            description: "Display a horizontal row of three-dimensional shapes in your visionOS app, using predefined mesh and white material.",
            zipFilename: "visionos-creating-3d-entities-with-realitykit.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/creating-3d-entities-with-realitykit"
        ),
        SampleCodeEntry(
            title: "Creating 3D models as movable windows",
            url: "/documentation/visionOS/creating-a-volumetric-window-in-visionos",
            framework: "visionOS",
            description: "Display 3D content with a volumetric window that people can move.",
            zipFilename: "visionos-creating-a-volumetric-window-in-visionos.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/creating-a-volumetric-window-in-visionos"
        ),
        SampleCodeEntry(
            title: "Creating SwiftUI windows in visionOS",
            url: "/documentation/visionOS/creating-a-new-swiftui-window-in-visionos",
            framework: "visionOS",
            description: "Display and manage multiple SwiftUI windows in your visionOS app.",
            zipFilename: "visionos-creating-a-new-swiftui-window-in-visionos.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/creating-a-new-swiftui-window-in-visionos"
        ),
        SampleCodeEntry(
            title: "Creating a 3D painting space",
            url: "/documentation/visionOS/creating-a-painting-space-in-visionos",
            framework: "visionOS",
            description: "Implement a painting canvas entity, and update its mesh to represent a stroke.",
            zipFilename: "visionos-creating-a-painting-space-in-visionos.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/creating-a-painting-space-in-visionos"
        ),
        SampleCodeEntry(
            title: "Creating an immersive space in visionOS",
            url: "/documentation/visionOS/creating-immersive-spaces-in-visionos-with-swiftui",
            framework: "visionOS",
            description: "Enhance your visionOS app by adding an immersive space using RealityKit.",
            zipFilename: "visionos-creating-immersive-spaces-in-visionos-with-swiftui.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/creating-immersive-spaces-in-visionos-with-swiftui"
        ),
        SampleCodeEntry(
            title: "Creating an interactive 3D model in visionOS",
            url: "/documentation/visionOS/creating-an-interactable-3d-model-in-visionos",
            framework: "visionOS",
            description: "Display an interactive car model using gestures in a reality view.",
            zipFilename: "visionos-creating-an-interactable-3d-model-in-visionos.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/creating-an-interactable-3d-model-in-visionos"
        ),
        SampleCodeEntry(
            title: "Destination Video",
            url: "/documentation/visionOS/destination-video",
            framework: "visionOS",
            description: "Leverage SwiftUI to build an immersive media experience in a multiplatform app.",
            zipFilename: "visionos-destination-video.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/destination-video"
        ),
        SampleCodeEntry(
            title: "Diorama",
            url: "/documentation/visionOS/diorama",
            framework: "visionOS",
            description: "Design scenes for your visionOS app using Reality Composer Pro.",
            zipFilename: "visionos-diorama.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/diorama"
        ),
        SampleCodeEntry(
            title: "Displaying a 3D environment through a portal",
            url: "/documentation/visionOS/displaying-a-3D-environment-through-a-portal",
            framework: "visionOS",
            description: "Implement a portal window that displays a 3D environment and simulates entering a portal by using RealityKit.",
            zipFilename: "visionos-displaying-a-3d-environment-through-a-portal.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/displaying-a-3D-environment-through-a-portal"
        ),
        SampleCodeEntry(
            title: "Displaying a stereoscopic image",
            url: "/documentation/visionOS/displaying-a-stereoscopic-image-in-visionos",
            framework: "visionOS",
            description: "Build a stereoscopic image by applying textures to the left and right eye in a shader graph material.",
            zipFilename: "visionos-displaying-a-stereoscopic-image-in-visionos.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/displaying-a-stereoscopic-image-in-visionos"
        ),
        SampleCodeEntry(
            title: "Displaying an entity that follows a person’s view",
            url: "/documentation/visionOS/displaying-a-3D-object-that-moves-to-stay-in-a-person",
            framework: "visionOS",
            description: "Create an entity that tracks and follows head movement in an immersive scene.",
            zipFilename: "visionos-displaying-a-3d-object-that-moves-to-stay-in-a-person.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/displaying-a-3D-object-that-moves-to-stay-in-a-person"
        ),
        SampleCodeEntry(
            title: "Displaying text in visionOS",
            url: "/documentation/visionOS/displaying-text-in-visionOS",
            framework: "visionOS",
            description: "Create styled text in a window using SwiftUI.",
            zipFilename: "visionos-displaying-text-in-visionos.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/displaying-text-in-visionOS"
        ),
        SampleCodeEntry(
            title: "Displaying video from connected devices",
            url: "/documentation/visionOS/displaying-video-from-connected-devices",
            framework: "visionOS",
            description: "Show video from devices connected with the Developer Strap in your visionOS app.",
            zipFilename: "visionos-displaying-video-from-connected-devices.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/displaying-video-from-connected-devices"
        ),
        SampleCodeEntry(
            title: "Enabling video reflections in an immersive environment",
            url: "/documentation/visionOS/enabling-video-reflections-in-an-immersive-environment",
            framework: "visionOS",
            description: "Create a more immersive experience by adding video reflections in a custom environment.",
            zipFilename: "visionos-enabling-video-reflections-in-an-immersive-environment.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/enabling-video-reflections-in-an-immersive-environment"
        ),
        SampleCodeEntry(
            title: "Exploring object tracking with ARKit",
            url: "/documentation/visionOS/exploring_object_tracking_with_arkit",
            framework: "visionOS",
            description: "Find and track real-world objects in visionOS using reference objects trained with Create ML.",
            zipFilename: "visionos-exploring_object_tracking_with_arkit.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/exploring_object_tracking_with_arkit"
        ),
        SampleCodeEntry(
            title: "Generating procedural textures",
            url: "/documentation/visionOS/generating-procedural-textures-in-visionos",
            framework: "visionOS",
            description: "Display a 3D model that generates procedural textures in a reality view.",
            zipFilename: "visionos-generating-procedural-textures-in-visionos.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/generating-procedural-textures-in-visionos"
        ),
        SampleCodeEntry(
            title: "Happy Beam",
            url: "/documentation/visionOS/happybeam",
            framework: "visionOS",
            description: "Leverage a Full Space to create a fun game using ARKit.",
            zipFilename: "visionos-happybeam.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/happybeam"
        ),
        SampleCodeEntry(
            title: "Hello World",
            url: "/documentation/visionOS/World",
            framework: "visionOS",
            description: "Use windows, volumes, and immersive spaces to teach people about the Earth.",
            zipFilename: "visionos-world.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/World"
        ),
        SampleCodeEntry(
            title: "Implementing adjustable material",
            url: "/documentation/visionOS/implementing-adjustable-material-in-visionos",
            framework: "visionOS",
            description: "Update the adjustable parameters of a 3D model in visionOS.",
            zipFilename: "visionos-implementing-adjustable-material-in-visionos.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/implementing-adjustable-material-in-visionos"
        ),
        SampleCodeEntry(
            title: "Incorporating real-world surroundings in an immersive experience",
            url: "/documentation/visionOS/incorporating-real-world-surroundings-in-an-immersive-experience",
            framework: "visionOS",
            description: "Create an immersive experience by making your app’s content respond to the local shape of the world.",
            zipFilename: "visionos-incorporating-real-world-surroundings-in-an-immersive-experience.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/incorporating-real-world-surroundings-in-an-immersive-experience"
        ),
        SampleCodeEntry(
            title: "Locating and decoding barcodes in 3D space",
            url: "/documentation/visionOS/locating-and-decoding-barcodes-in-3d-space",
            framework: "visionOS",
            description: "Create engaging, hands-free experiences based on barcodes in a person’s surroundings.",
            zipFilename: "visionos-locating-and-decoding-barcodes-in-3d-space.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/locating-and-decoding-barcodes-in-3d-space"
        ),
        SampleCodeEntry(
            title: "Object tracking with Reality Composer Pro experiences",
            url: "/documentation/visionOS/object-tracking-with-reality-composer-pro-experiences",
            framework: "visionOS",
            description: "Use object tracking in visionOS to attach digital content to real objects to create engaging experiences.",
            zipFilename: "visionos-object-tracking-with-reality-composer-pro-experiences.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/object-tracking-with-reality-composer-pro-experiences"
        ),
        SampleCodeEntry(
            title: "Obscuring virtual items in a scene behind real-world items",
            url: "/documentation/visionOS/obscuring-virtual-items-in-a-scene-behind-real-world-items",
            framework: "visionOS",
            description: "Increase the realism of an immersive experience by adding entities with invisible materials real-world objects.",
            zipFilename: "visionos-obscuring-virtual-items-in-a-scene-behind-real-world-items.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/obscuring-virtual-items-in-a-scene-behind-real-world-items"
        ),
        SampleCodeEntry(
            title: "Petite Asteroids: Building a volumetric visionOS game",
            url: "/documentation/visionOS/petite-asteroids-building-a-volumetric-visionos-game",
            framework: "visionOS",
            description: "Use the latest RealityKit APIs to create a beautiful video game for visionOS.",
            zipFilename: "visionos-petite-asteroids-building-a-volumetric-visionos-game.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/petite-asteroids-building-a-volumetric-visionos-game"
        ),
        SampleCodeEntry(
            title: "Placing content on detected planes",
            url: "/documentation/visionOS/placing-content-on-detected-planes",
            framework: "visionOS",
            description: "Detect horizontal surfaces like tables and floors, as well as vertical planes like walls and doors.",
            zipFilename: "visionos-placing-content-on-detected-planes.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/placing-content-on-detected-planes"
        ),
        SampleCodeEntry(
            title: "Placing entities using head and device transform",
            url: "/documentation/visionOS/placing-entities-using-head-and-device-transform",
            framework: "visionOS",
            description: "Query and react to changes in the position and rotation of Apple Vision Pro.",
            zipFilename: "visionos-placing-entities-using-head-and-device-transform.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/placing-entities-using-head-and-device-transform"
        ),
        SampleCodeEntry(
            title: "Playing immersive media with RealityKit",
            url: "/documentation/visionOS/playing-immersive-media-with-realitykit",
            framework: "visionOS",
            description: "Create an immersive video playback experience with RealityKit.",
            zipFilename: "visionos-playing-immersive-media-with-realitykit.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/playing-immersive-media-with-realitykit"
        ),
        SampleCodeEntry(
            title: "Playing spatial audio",
            url: "/documentation/visionOS/playing-spatial-audio-in-visionos",
            framework: "visionOS",
            description: "Create and adjust spatial audio in visionOS with RealityKit.",
            zipFilename: "visionos-playing-spatial-audio-in-visionos.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/playing-spatial-audio-in-visionos"
        ),
        SampleCodeEntry(
            title: "Swift Splash",
            url: "/documentation/visionOS/swift-splash",
            framework: "visionOS",
            description: "Use RealityKit to create an interactive ride in visionOS.",
            zipFilename: "visionos-swift-splash.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/swift-splash"
        ),
        SampleCodeEntry(
            title: "Tracking and visualizing hand movement",
            url: "/documentation/visionOS/tracking-and-visualizing-hand-movement",
            framework: "visionOS",
            description: "Use hand-tracking anchors to display a visual representation of hand transforms in visionOS.",
            zipFilename: "visionos-tracking-and-visualizing-hand-movement.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/tracking-and-visualizing-hand-movement"
        ),
        SampleCodeEntry(
            title: "Tracking specific points in world space",
            url: "/documentation/visionOS/tracking-points-in-world-space",
            framework: "visionOS",
            description: "Retrieve the position and orientation of anchors your app stores in ARKit.###",
            zipFilename: "visionos-tracking-points-in-world-space.zip",
            webURL: "https://developer.apple.com/documentation/visionOS/tracking-points-in-world-space"
        ),
        SampleCodeEntry(
            title: "Structuring Recognized Text on a Document",
            url: "/documentation/visionkit/structuring_recognized_text_on_a_document",
            framework: "visionkit",
            description: "Detect, recognize, and structure text on a business card or receipt using Vision and VisionKit.",
            zipFilename: "visionkit-structuring_recognized_text_on_a_document.zip",
            webURL: "https://developer.apple.com/documentation/visionkit/structuring_recognized_text_on_a_document"
        ),
        SampleCodeEntry(
            title: "Building a productivity app for Apple Watch",
            url: "/documentation/watchOS-Apps/building-a-productivity-app-for-apple-watch",
            framework: "watchOS-Apps",
            description: "Create a watch app to manage and share a task list and visualize the status with a chart.",
            zipFilename: "watchos-apps-building-a-productivity-app-for-apple-watch.zip",
            webURL: "https://developer.apple.com/documentation/watchOS-Apps/building-a-productivity-app-for-apple-watch"
        ),
        SampleCodeEntry(
            title: "Create accessible experiences for watchOS",
            url: "/documentation/watchOS-Apps/create-accessible-experiences-for-watchos",
            framework: "watchOS-Apps",
            description: "Learn how to make your watchOS app more accessible.",
            zipFilename: "watchos-apps-create-accessible-experiences-for-watchos.zip",
            webURL: "https://developer.apple.com/documentation/watchOS-Apps/create-accessible-experiences-for-watchos"
        ),
        SampleCodeEntry(
            title: "Updating your app and widgets for watchOS 10",
            url: "/documentation/watchOS-Apps/updating-your-app-and-widgets-for-watchos-10",
            framework: "watchOS-Apps",
            description: "Integrate SwiftUI elements and watch-specific features, and build widgets for the Smart Stack.###",
            zipFilename: "watchos-apps-updating-your-app-and-widgets-for-watchos-10.zip",
            webURL: "https://developer.apple.com/documentation/watchOS-Apps/updating-your-app-and-widgets-for-watchos-10"
        ),
        SampleCodeEntry(
            title: "Fetching weather forecasts with WeatherKit",
            url: "/documentation/weatherkit/fetching_weather_forecasts_with_weatherkit",
            framework: "weatherkit",
            description: "Request and display weather data for destination airports in a flight-planning app.",
            zipFilename: "weatherkit-fetching_weather_forecasts_with_weatherkit.zip",
            webURL: "https://developer.apple.com/documentation/weatherkit/fetching_weather_forecasts_with_weatherkit"
        ),
        SampleCodeEntry(
            title: "Building Widgets Using WidgetKit and SwiftUI",
            url: "/documentation/widgetkit/building_widgets_using_widgetkit_and_swiftui",
            framework: "widgetkit",
            description: "Create widgets to show your app’s content on the Home screen, with custom intents for user-customizable settings.",
            zipFilename: "widgetkit-building_widgets_using_widgetkit_and_swiftui.zip",
            webURL: "https://developer.apple.com/documentation/widgetkit/building_widgets_using_widgetkit_and_swiftui"
        ),
    ]

    /// Get sample code entry by URL
    public static func entry(forURL url: String) -> SampleCodeEntry? {
        allEntries.first { $0.url == url }
    }

    /// Get all sample codes for a specific framework
    public static func entries(forFramework framework: String) -> [SampleCodeEntry] {
        allEntries.filter { $0.framework.lowercased() == framework.lowercased() }
    }

    /// Search sample codes by keyword
    public static func search(_ keyword: String) -> [SampleCodeEntry] {
        let lowercased = keyword.lowercased()
        return allEntries.filter {
            $0.title.lowercased().contains(lowercased) ||
                $0.description.lowercased().contains(lowercased) ||
                $0.framework.lowercased().contains(lowercased)
        }
    }
}
