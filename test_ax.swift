import Cocoa
import ApplicationServices

func typeTextWithAX(_ text: String) {
    let systemWide = AXUIElementCreateSystemWide()
    var focusedElement: AnyObject?
    let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
    if result == .success, let element = focusedElement as? AXUIElement {
        let textCF = text as CFTypeRef
        let setRes = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, textCF)
        print("Set attribute result: \(setRes.rawValue)")
    } else {
        print("No focused element: \(result.rawValue)")
    }
}
typeTextWithAX("Hello Background World")
