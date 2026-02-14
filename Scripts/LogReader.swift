import Foundation
import OSLog

if #available(macOS 10.15, *) {
    do {
        let store = try OSLogStore(scope: .currentProcessIdentifier) 
        // Note: .currentProcessIdentifier only gets logs from THIS process. 
        // We need .system to get logs from bluetoothd, but that usually requires admin/root.
        // Let's try .system and see if it throws or returns empty.
    } catch {
        print("Initial check failed: \(error)")
    }
    
    // Attempting to read system logs
    do {
        // Limitation: Non-privileged apps usually can't read other processes' logs in recent macOS
        // unless they are streaming via 'log stream' command which pipes output.
        // But 'OSLogStore.init(scope: .system)' exists.
        
        print("Attempting to open System Log Store...")
        // This might fail or require special entitlements
        // For a cli tool run by user, it might work?
        // But 'log show' works in terminal without sudo? Yes.
        // So maybe it works.
        
        let store = try OSLogStore(scope: .currentProcessIdentifier) // Placeholder, real test below
    } catch {}
}

// Actual CLI wrapper test
// Since writing Swift OSLog code is complex to compile/entitle quickly, 
// I will trust the 'log show' CLI works (step 8723 worked).
// The plan is to wrap 'log show' in a Process.

print("Simulating Log Parsing from previous output...")
let sampleLog = "2026-02-14 ... DvF ... Plcm P InEar S InCase M Enabled, Prim Right, ..."
if sampleLog.contains("Prim Right") {
    print("Parsing success: Primary is Right")
}
