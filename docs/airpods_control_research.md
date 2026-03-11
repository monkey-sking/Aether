# macOS/iOS AirPods Control Research

This document summarizes the available control methods for AirPods on macOS/iOS, distinguishing between system-reserved gestures and developer-accessible inputs. This is intended to guide future feature development for Aether.

## 1. Physical Controls (Button/Stem/Touch)

Most physical interactions specifically on the AirPods hardware are preempted by the system for media control, call management, and system settings.

### System Reserved (Developer Inaccessible)
*   **Long Press**: Reserved for **Noise Control** (ANC/Transparency) or **Siri**.
    *   *Status*: **Completely Blocked**. Developers cannot intercept this event.
*   **Swipe (AirPods Pro 2)**: Reserved for **Volume Control**.
    *   *Status*: **Completely Blocked**. No API access.
*   **Automatic Ear Detection**: Used for auto-pause/play.
    *   *Status*: System managed.

### Developer Accessible (with Caveats)
*   **Click / Double-Click / Triple-Click**: 
    *   *Default Behavior*: Play / Pause / Next Track / Previous Track.
    *   *Developer Access*: **Indirect via `MPRemoteCommandCenter`**.
    *   *Mechanism*: The App must register as the "Now Playing" application (usually requires playing silent audio in the background).
    *   *Trade-off*: This "hijacks" the media controls. If the user wants to control Apple Music or Spotify while using Aether, this will conflict.
    *   *Event Handling*:
        ```swift
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { ... }
        commandCenter.nextTrackCommand.addTarget { ... }
        ```

## 2. Motion Data (Head Tracking)

This is the most "open" input surface available to developers. While Apple uses it for Spatial Audio and specifically for "Call Accept/Decline" gestures (iOS 17+), the raw data is generally available for custom interpretation.

### System Usage
*   **Spatial Audio**: Uses head tracking to orient sound field.
*   **Siri Interactions (iOS 17/macOS 14)**:
    *   **Nod**: Accept Call / Reply to Message.
    *   **Shake**: Decline Call / Dismiss Message.
    *   *Note*: These only trigger during specific system events (incoming call/message announcement).

### Developer Access (Raw Data)
*   **API**: `CMHeadphoneMotionManager` (Core Motion).
*   **Data Types**:
    *   **Attitude (Quaternion/Euler)**: Real-time Pitch (Head Up/Down), Yaw (Turn Left/Right), Roll (Tilt Left/Right).
    *   **Rotation Rate**: How fast the head is turning.
    *   **User Acceleration**: Sudden movements (jerks).
*   **Potential Custom Gestures**:
    Since the system does not claim these motions outside of calls, we can implement custom recognizers for:
    *   **Quick Nod (Double Nod)**: Confirm/Tap.
    *   **Quick Shake**: Cancel/Escape.
    *   **Upward Tilt**: Scroll Up / Exposé.
    *   **Downward Tilt**: Scroll Down.
    *   **Lateral Tilt (Ear to Shoulder)**: Switch Desktop / Switch Tab.
    *   **Jaw Clench**: (Detect via accelerometer vibration signatures - experimental/advanced).

## Conclusion
*   **Buttons**: Highly restricted. Good for "push-to-talk" but requires audio session hacks (`Now Playing`).
*   **Head Motion**: High potential. The "wild west" for custom interaction design. System interference is minimal during normal usage.

**Recommendation**: Focus heavily on **Head Motion (`CMHeadphoneMotionManager`)** for rich, interference-free control. Use **Buttons (`MPRemoteCommandCenter`)** sparingly, perhaps only as a toggle for the head tracking itself.
