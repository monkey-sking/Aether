import os
import re
import uuid

PROJECT_PATH = 'Aether.xcodeproj/project.pbxproj'

def generate_id():
    return uuid.uuid4().hex[:24].upper()

def update_project():
    with open(PROJECT_PATH, 'r') as f:
        content = f.read()

    # Define files to ADD and REMOVE
    files_to_add = [
        'HUDState.swift',
        'HUDView.swift',
        'HUDManager.swift',
        'CaretDetector.swift',
        'InputMethodCaretBridge.swift'
    ]
    files_to_remove = [
        'HotkeyFeedbackHUD.swift'
    ]
    
    # --- REMOVE OLD FILES ---
    for f in files_to_remove:
        print(f"Removing {f}...")
        # 1. Remove PBXBuildFile
        # Format: ID /* f in Sources */ = {isa = PBXBuildFile; fileRef = REFID /* f */; };
        content = re.sub(r'\t+[0-9A-F]{24} /\* ' + re.escape(f) + r' in Sources \*/ = \{.*?\};\n', '', content)
        
        # 2. Remove PBXFileReference
        # Format: REFID /* f */ = {isa = PBXFileReference; ... };
        content = re.sub(r'\t+[0-9A-F]{24} /\* ' + re.escape(f) + r' \*/ = \{.*?\};\n', '', content)
        
        # 3. Remove from PBXSourcesBuildPhase
        # Format: ID /* f in Sources */,
        content = re.sub(r'\t+[0-9A-F]{24} /\* ' + re.escape(f) + r' in Sources \*/,\n', '', content)
        
        # 4. Remove from PBXGroup (Optional/Tricky - search by name in children list)
        # Format: ID /* f */,
        # We might leave it as a dangling reference in Group if regex is hard, Xcode usually cleans up or ignores.
        # But let's try to remove it from children lists.
        content = re.sub(r'\t+[0-9A-F]{24} /\* ' + re.escape(f) + r' \*/,\n', '', content)

    # --- ADD NEW FILES ---
    
    # 1. Generate IDs and File Refs
    file_id_map = {}
    build_id_map = {}
    
    file_refs_content = ""
    for f in files_to_add:
        if f"/* {f} */" in content:
            print(f"Skipping {f}, already in project.")
            continue
            
        fid = generate_id()
        file_id_map[f] = fid
        path = f"Apps/AetherCore/HUD/{f}"
        file_refs_content += f'\t\t{fid} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {path}; sourceTree = "<group>"; }};\n'

    if file_refs_content:
        # Insert before End of PBXFileReference section
        content = re.sub(r'(/\* End PBXFileReference section \*/)', file_refs_content + r'\1', content)

    # 2. Generate Build File entries
    build_files_content = ""
    for f, fid in file_id_map.items():
        bid = generate_id()
        build_id_map[f] = bid
        build_files_content += f'\t\t{bid} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {f} */; }};\n'

    if build_files_content:
        # Insert before End of PBXBuildFile section
        content = re.sub(r'(/\* End PBXBuildFile section \*/)', build_files_content + r'\1', content)

    # 3. Add to Sources Build Phase
    # We look for the main sources build phase.
    # We can search for a known file like 'SpeechManager.swift' in Sources to find the right block.
    # The block starts with `files = (` and ends with `);`
    
    if build_id_map:
        # Find the Sources Build Phase that contains SpeechManager using a simpler regex strategy
        # We find the section that contains "SpeechManager.swift in Sources"
        sources_phase_match = re.search(r'(files = \(\n)([\s\S]*?SpeechManager.swift in Sources[\s\S]*?)(\);)', content)
        
        if sources_phase_match:
            print("Found Sources Build Phase.")
            prefix = sources_phase_match.group(1)
            existing_files = sources_phase_match.group(2)
            suffix = sources_phase_match.group(3)
            
            new_entries = ""
            for f, bid in build_id_map.items():
                new_entries += f'\t\t\t\t{bid} /* {f} in Sources */,\n'
            
            # Replace the block
            content = content.replace(prefix + existing_files + suffix, prefix + existing_files + new_entries + suffix)
        else:
            print("Error: Could not find Sources Build Phase containing SpeechManager.swift")

    # 4. Add to Main Group (Optional but good for UI)
    # We look for `children = (` inside the group that contains `SpeechManager.swift`
    if file_id_map:
        group_match = re.search(r'(children = \(\n)([\s\S]*?SpeechManager.swift[\s\S]*?)(\);)', content)
        if group_match:
             print("Found Main Group.")
             prefix = group_match.group(1)
             existing_children = group_match.group(2)
             suffix = group_match.group(3)
             
             new_children = ""
             for f, fid in file_id_map.items():
                 new_children += f'\t\t\t\t{fid} /* {f} */,\n'
                 
             content = content.replace(prefix + existing_children + suffix, prefix + existing_children + new_children + suffix)

    with open(PROJECT_PATH, 'w') as f:
        f.write(content)
    print("Project file updated successfully.")

if __name__ == '__main__':
    update_project()
