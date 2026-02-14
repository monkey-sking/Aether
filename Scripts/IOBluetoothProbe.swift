import IOBluetooth
import Foundation

guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
    print("No paired devices found.")
    exit(0)
}

print("Searching for AirPods via KVC...")

for device in devices {
    if device.isConnected() {
        print("\nFound Connected Device: \(device.nameOrAddress ?? "Unknown")")
        
        let keys = [
            "batteryPercentLeft", 
            "batteryPercentRight", 
            "batteryPercentSingle", 
            "batteryPercentCombined"
        ]
        
        for key in keys {
            // Swift's value(forKey:) can throw or trap if not ObjC compliant, but IOBluetoothDevice is ObjC.
            // We'll wrap in a safe block if possible, or just try.
            // In a script, a crash is fine, it tells us it failed.
            
            // To be safe in Swift script:
            do {
                if let val = device.value(forKey: key) {
                    print("  [\(key)]: \(val)")
                } else {
                    print("  [\(key)]: nil")
                }
            } catch {
                print("  [\(key)]: Error/Exception")
            }
        }
    }
}
