import CoreAudio
import Foundation

// Helper to get default input device ID
var defaultInputDeviceID = AudioObjectID(kAudioObjectUnknown)
var propertyAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)

let status = AudioObjectGetPropertyData(
    AudioObjectID(kAudioObjectSystemObject),
    &propertyAddress,
    0,
    nil,
    &propertySize,
    &defaultInputDeviceID
)

if status == noErr {
    print("Default Input Device ID: \(defaultInputDeviceID)")
    
    // Get Device Name
    var nameSize = UInt32(MemoryLayout<CFString>.size)
    var deviceName: CFString = "" as CFString
    var nameAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceNameCFString,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectGetPropertyData(defaultInputDeviceID, &nameAddr, 0, nil, &nameSize, &deviceName)
    print("Device Name: \(deviceName)")
    
    // Get Data Source (often used for multiple mics like Front/Back, maybe Left/Right?)
    var dataSource: UInt32 = 0
    var dataSourceSize = UInt32(MemoryLayout<UInt32>.size)
    var dataSourceAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDataSource,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    
    let dsStatus = AudioObjectGetPropertyData(defaultInputDeviceID, &dataSourceAddr, 0, nil, &dataSourceSize, &dataSource)
    if dsStatus == noErr {
        print("Current Data Source ID: \(dataSource)")
        
        // Get Data Source Name
        var dsName: CFString = "" as CFString
        var value: UInt32 = dataSource
        var translationAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSourceNameForIDCFString,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        // We need to pass the ID as input to get the name? No, usually it's a translation selector
        // Actually, AudioObjectGetPropertyData with 'kAudioDevicePropertyDataSourceNameForIDCFString' interprets the inQualifierData as the ID.
        
        var dsNameSize = UInt32(MemoryLayout<CFString>.size)
        let nameStatus = AudioObjectGetPropertyData(defaultInputDeviceID, &translationAddr, UInt32(MemoryLayout<UInt32>.size), &dataSource, &dsNameSize, &dsName)
        
        if nameStatus == noErr {
            print("Current Data Source Name: \(dsName)")
        } else {
            print("Failed to get Data Source Name. Err: \(nameStatus)")
        }
        
    } else {
        print("No Data Source Property found (Err: \(dsStatus)). This device might not support source switching.")
    }
    
    // Check Channels
    var channelAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var channelSize: UInt32 = 0
    AudioObjectGetPropertyDataSize(defaultInputDeviceID, &channelAddr, 0, nil, &channelSize)
    let streamCount = channelSize / UInt32(MemoryLayout<AudioObjectID>.size)
    print("Input Streams: \(streamCount)")

} else {
    print("Error getting default input device.")
}
