import re
import os

PROJECT_PATH = 'Aether.xcodeproj/project.pbxproj'

def update_pbxproj():
    if not os.path.exists(PROJECT_PATH):
        print(f"Error: {PROJECT_PATH} not found.")
        return

    with open(PROJECT_PATH, 'r') as f:
        content = f.read()

    # Define the settings for each target
    config_settings = {
        # AetherCore (App) target configurations
        'B9C56A112F2BA1FF00EEEB9E': {
            'CODE_SIGN_ENTITLEMENTS': 'Apps/AetherCore/AetherCore.entitlements',
            'SWIFT_OBJC_BRIDGING_HEADER': 'Apps/AetherCore/AetherCore-Bridging-Header.h'
        },
        'B9C56A122F2BA1FF00EEEB9E': {
            'CODE_SIGN_ENTITLEMENTS': 'Apps/AetherCore/AetherCore.entitlements',
            'SWIFT_OBJC_BRIDGING_HEADER': 'Apps/AetherCore/AetherCore-Bridging-Header.h'
        },
        # AetherDriver (Driver) target configurations
        'B9B3B9632F2C58AC00B03934': {
            'CODE_SIGN_ENTITLEMENTS': 'Drivers/AetherDriver/AetherDriver.entitlements'
        },
        'B9B3B9642F2C58AC00B03934': {
            'CODE_SIGN_ENTITLEMENTS': 'Drivers/AetherDriver/AetherDriver.entitlements'
        }
    }

    new_content = content
    for config_id, settings_to_add in config_settings.items():
        # Find the buildSettings block for this config_id
        pattern = r'(' + config_id + r' /\* .*? \*/ = \{[\s\S]*?buildSettings = \{)([\s\S]*?)(\};)'
        
        def replace_settings(match):
            prefix = match.group(1)
            settings = match.group(2)
            suffix = match.group(3)
            
            for key, value in settings_to_add.items():
                if key not in settings:
                    # Insert after the opening bracket
                    settings = f'\n\t\t\t\t{key} = {value};' + settings
                else:
                    # Update existing
                    settings = re.sub(r'(' + key + r'\s*=\s*)(.*?)(;)', r'\1' + value + r'\3', settings)
            
            return prefix + settings + suffix

        new_content = re.sub(pattern, replace_settings, new_content)

    if new_content != content:
        with open(PROJECT_PATH, 'w') as f:
            f.write(new_content)
        print("Successfully updated App and Driver build settings.")
    else:
        print("No changes made. Check if IDs were properly detected.")

if __name__ == '__main__':
    update_pbxproj()
