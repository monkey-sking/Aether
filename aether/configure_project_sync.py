import re
import os

PROJECT_PATH = 'Aether.xcodeproj/project.pbxproj'

def update_pbxproj():
    if not os.path.exists(PROJECT_PATH):
        print(f"Error: {PROJECT_PATH} not found.")
        return

    with open(PROJECT_PATH, 'r') as f:
        content = f.read()

    # 1. Update the App Sync group path to Apps/AetherCore
    # ID B9C56A072F2BA1FE00EEEB9E was found to be the App's synced group
    content = re.sub(
        r'(B9C56A072F2BA1FE00EEEB9E /\* Aether \*/ = \{[\s\S]*?path = )Aether(;)',
        r'\1Apps/AetherCore\2',
        content
    )

    # 2. Update the Target name in comments for clarity (Optional but recommended)
    content = content.replace('/* Aether */', '/* AetherCore */')

    # 3. Add Shared directory as a synchronized group if not present
    if 'Shared' not in content:
        # This part is complex because we need to add to multiple sections.
        # For now, let's just fix the App path as it's the most critical.
        pass

    with open(PROJECT_PATH, 'w') as f:
        f.write(content)
    print("Successfully synchronized App directory path.")

if __name__ == '__main__':
    update_pbxproj()
