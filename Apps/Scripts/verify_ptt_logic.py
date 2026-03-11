
class HeadMotionManager:
    def __init__(self):
        self.isPTTEnabled = True
        self.isPTTPressed = False
        self.hud_shown = False

    def simulate_key_down(self):
        print(f"[Input] Key Down. PTT Enabled: {self.isPTTEnabled}")
        if not self.isPTTPressed:
            if self.isPTTEnabled:
                self.trigger_ptt()
            else:
                print("[Logic] PTT Disabled. Ignoring trigger.")
        else:
            print("[Logic] Key already pressed. Ignoring.")
        self.isPTTPressed = True

    def simulate_key_up(self):
        print("[Input] Key Up.")
        self.isPTTPressed = False
        self.hud_shown = False

    def trigger_ptt(self):
        print("[Action] Show HUD: '🎤 Push to Talk'")
        self.hud_shown = True

# Simulation
manager = HeadMotionManager()

print("--- Test Case 1: PTT Enabled (Default) ---")
manager.simulate_key_down()
assert manager.hud_shown == True, "HUD should show when enabled"
manager.simulate_key_up()

print("\n--- Test Case 2: PTT Disabled ---")
manager.isPTTEnabled = False
manager.simulate_key_down()
assert manager.hud_shown == False, "HUD should NOT show when disabled"
manager.simulate_key_up()

print("\n--- Test Case 3: PTT Re-enabled ---")
manager.isPTTEnabled = True
manager.simulate_key_down()
assert manager.hud_shown == True, "HUD should show when re-enabled"
manager.simulate_key_up()

print("\n✅ Simulation Passed: Logic is sound.")
