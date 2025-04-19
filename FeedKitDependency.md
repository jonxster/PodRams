# FeedKit Dependency

FeedKit has been added to this project as a dependency.

To add FeedKit to your Xcode project:

1. Open Xcode and open your project at /Users/tombjornebark/Desktop/PodRams/PodRams/PodRams.xcodeproj
2. Select File -> Add Packages...
3. Enter the following URL: https://github.com/nmdias/FeedKit.git
4. Select 'Up to Next Major Version' with '9.1.2' as the minimum version
5. Add the package to your main PodRams target

Alternatively, you can use the FeedKit package we've already cloned:
1. In Xcode, select File -> Add Packages...
2. Click 'Add Local...' at the bottom
3. Navigate to: /Users/tombjornebark/Desktop/PodRams/Dependencies/FeedKit
4. Select the FeedKit package and add it to your main PodRams target

## Manual Integration

If the above method doesn't work, you can manually add FeedKit to your project:

1. Copy the FeedKit source files to your project:
   ```
   cp -r ${DEPENDENCIES_DIR}/FeedKit/Sources/FeedKit ${PODRAMSAPP_DIR}/FeedKit
   ```

2. Add the FeedKit directory to your Xcode project
