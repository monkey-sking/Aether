import re
import os

PROJECT_PATH = 'Aether.xcodeproj/project.pbxproj'

def switch_to_local_sign():
    if not os.path.exists(PROJECT_PATH):
        print(f"Error: {PROJECT_PATH} not found.")
        return

    with open(PROJECT_PATH, 'r') as f:
        content = f.read()

    # Driver target configuration IDs ONLY
    # App targets are excluded so user can use Personal Team for stable TCC permissions.
    driver_configs = [
        'B9B3B9632F2C58AC00B03934', 'B9B3B9642F2C58AC00B03934' # Driver
    ]
    
    # Settings for "Sign to Run Locally"
    local_sign_settings = {
        'CODE_SIGN_IDENTITY': '"-"',
        'CODE_SIGN_STYLE': 'Manual',
        'DEVELOPMENT_TEAM': '""',
        'AD_HOC_CODE_SIGNING_ALLOWED': 'YES',
        'CODE_SIGNING_REQUIRED': 'NO',
        'CODE_SIGNING_ALLOWED': 'YES',
    }
    
    # Keys to completely remove
    keys_to_remove = [
        'PROVISIONING_PROFILE_SPECIFIER',
        'PROVISIONING_PROFILE',
        'DEVELOPMENT_TEAM'
    ]

    new_content = content
    for config_id in driver_configs:
        pattern = r'(' + config_id + r' /\* .*? \*/ = \{[\s\S]*?buildSettings = \{)([\s\S]*?)(\};)'
        
        def replace_settings(match):
            prefix = match.group(1)
            settings = match.group(2)
            suffix = match.group(3)
            
            # Remove forbidden keys
            for key in keys_to_remove:
                settings = re.sub(r'^\s*' + key + r'\s*=\s*.*?;', '', settings, flags=re.MULTILINE)
            
            # Add/Update local sign settings
            for key, value in local_sign_settings.items():
                if key not in settings:
                    settings = f'\n\t\t\t\t{key} = {value};' + settings
                else:
                    settings = re.sub(r'(' + key + r'\s*=\s*)(.*?)(;)', r'\1' + value + r'\3', settings)
            
            return prefix + settings + suffix

        new_content = re.sub(pattern, replace_settings, new_content)

    if new_content != content:
        with open(PROJECT_PATH, 'w') as f:
            f.write(new_content)
        print("Successfully switched Driver to Local Signing (App signing preserved).")
    else:
        print("No changes needed or Driver IDs not found.")

if __name__ == '__main__':
    switch_to_local_sign()
