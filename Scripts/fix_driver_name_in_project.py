
import sys

project_path = "/Volumes/SSD/Projects/Aether/Aether.xcodeproj/project.pbxproj"
old_name = "AetherDriver.dext"
new_name = "com.7fei.Aether.AetherDriver.dext"

try:
    with open(project_path, 'r') as f:
        content = f.read()
    
    # We only want to replace it in the shell script part mostly, but let's see.
    # The shell script is escaped in the file.
    # We should search for specific patterns to avoid replacing file references that we might have missed?
    # Actually, I should probably replace ALL occurrences of "AetherDriver.dext" with "com.7fei.Aether.AetherDriver.dext"
    # EXCEPT maybe the PBXFileReference if I didn't update the file name in the file system... 
    # Wait, the build output name change (PRODUCT_NAME) implies the file reference in Xcode project navigator 
    # usually needs to point to the new name if it tracks the product.
    # But this is a "wrapper.driver-extension" type.
    
    # Let's verify if the usage inside shellScript uses escaped quotes.
    # In pbxproj, quotes are escaped as \" 
    
    # The script line: DRIVER_DEXT_1=\"$BUILD_DIR/${CONFIGURATION}-driverkit/AetherDriver.dext\"
    
    # So valid replacement target: AetherDriver.dext
    
    new_content = content.replace(old_name, new_name)
    
    if old_name not in content:
        print(f"Warning: {old_name} not found in file.")
    else:
        print(f"Replaced {content.count(old_name)} occurrences.")

    with open(project_path, 'w') as f:
        f.write(new_content)
        
    print("Successfully updated project.pbxproj")

except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
