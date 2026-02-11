import re

file_path = 'Aether.xcodeproj/project.pbxproj'

with open(file_path, 'r') as f:
    content = f.read()

# Configuration for Aether Core
# Bundle ID: com.7fei.Aether
# Profile Name: Aether Development
# Profile UUID: 8a7bc5e4-ebc2-49c5-a72c-f4c5e12168cd

# Configuration for Aether Driver
# Bundle ID: com.7fei.Aether.AetherDriver
# Profile Name: AetherDriver Development
# Profile UUID: 7c053baa-49a3-4fb9-8d9d-856ab3461abc

def update_build_settings(content, bundle_id, profile_name, profile_uuid):
    # This regex looks for a buildSettings dict containing the specific bundle ID
    # It captures the content of the buildSettings to be replaced
    pattern = re.compile(
        r'(buildSettings\s*=\s*{[^}]*PRODUCT_BUNDLE_IDENTIFIER\s*=\s*' + re.escape(bundle_id) + r';[^}]*};)', 
        re.DOTALL
    )
    
    def replacer(match):
        block = match.group(1)
        
        # 1. Change Automatic to Manual
        if 'CODE_SIGN_STYLE = Automatic;' in block:
            block = block.replace('CODE_SIGN_STYLE = Automatic;', 'CODE_SIGN_STYLE = Manual;')
        
        # 2. Set Provisioning Profile Specifier
        if 'PROVISIONING_PROFILE_SPECIFIER' in block:
            block = re.sub(r'PROVISIONING_PROFILE_SPECIFIER\s*=\s*"[^"]*";', f'PROVISIONING_PROFILE_SPECIFIER = "{profile_name}";', block)
            block = re.sub(r'PROVISIONING_PROFILE_SPECIFIER\s*=\s*[^;]*;', f'PROVISIONING_PROFILE_SPECIFIER = "{profile_name}";', block)
        else:
            # Insert if not exists (before closing brace)
            block = block[:-2] + f'\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{profile_name}";\n\t\t\t}};'

        # 3. Set Provisioning Profile UUID (Optional but good for fallback)
        if 'PROVISIONING_PROFILE =' in block:
            block = re.sub(r'PROVISIONING_PROFILE\s*=\s*"[^"]*";', f'PROVISIONING_PROFILE = "{profile_uuid}";', block)
            block = re.sub(r'PROVISIONING_PROFILE\s*=\s*[^;]*;', f'PROVISIONING_PROFILE = "{profile_uuid}";', block)
        else:
             # Insert if not exists
             block = block[:-2] + f'\t\t\t\tPROVISIONING_PROFILE = "{profile_uuid}";\n\t\t\t}};'

        # 4. Ensure CODE_SIGN_IDENTITY is set (Development) based on previous context, usually it is "Apple Development"
        # We leave it as is if it exists.
        
        return block

    return pattern.sub(replacer, content)

# Update Aether Core
content = update_build_settings(content, "com.7fei.Aether", "Aether DevelopmentAether Development", "8a7bc5e4-ebc2-49c5-a72c-f4c5e12168cd")

# Update Aether Driver
content = update_build_settings(content, "com.7fei.Aether.AetherDriver", "AetherDriver Development", "7c053baa-49a3-4fb9-8d9d-856ab3461abc")

with open(file_path, 'w') as f:
    f.write(content)

print("Successfully updated project.pbxproj")
