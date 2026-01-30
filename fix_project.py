import os
import re
import uuid

def generate_id():
    return uuid.uuid4().hex[:24].upper()

PROJECT_PATH = 'Aether.xcodeproj/project.pbxproj'

def fix_project():
    with open(PROJECT_PATH, 'r') as f:
        content = f.read()

    # Files to add
    sources = [
        'AetherApp.swift',
        'ContentView.swift',
        'HeadMotionManager.swift',
        'SystemExtensionManager.swift'
    ]
    resources = ['Assets.xcassets']
    
    # 1. Add PBXFileReference if missing
    file_refs_content = ""
    file_id_map = {}
    for f in sources + resources:
        if f not in content:
            fid = generate_id()
            file_id_map[f] = fid
            path = f"Apps/AetherCore/{f}"
            if f.endswith('.swift'):
                file_refs_content += f'\t\t{fid} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {path}; sourceTree = "<group>"; }};\n'
            else:
                file_refs_content += f'\t\t{fid} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = {path}; sourceTree = "<group>"; }};\n'
        else:
            # Extract existing ID
            match = re.search(r'([0-9A-F]{24}) /\* ' + re.escape(f) + r' \*/', content)
            if match:
                file_id_map[f] = match.group(1)

    if file_refs_content:
        content = re.sub(r'(/\* Begin PBXFileReference section \*/\n)', r'\1' + file_refs_content, content)

    # 2. Add PBXBuildFile if missing
    build_files_content = ""
    build_id_map = {}
    for f, fid in file_id_map.items():
        search_pattern = fid + r' /\* ' + re.escape(f) + r' in '
        if search_pattern not in content:
            bid = generate_id()
            build_id_map[f] = bid
            if f.endswith('.swift'):
                build_files_content += f'\t\t{bid} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {f} */; }};\n'
            else:
                build_files_content += f'\t\t{bid} /* {f} in Resources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {f} */; }};\n'
        else:
            match = re.search(r'([0-9A-F]{24}) /\* ' + re.escape(f) + r' in ', content)
            if match:
                build_id_map[f] = match.group(1)

    if build_files_content:
        content = re.sub(r'(/\* Begin PBXBuildFile section \*/\n)', r'\1' + build_files_content, content)

    # 3. Add to Build Phases
    # Sources phase for Aether (B9C56A012F2BA1FE00EEEB9E)
    sources_phase_pattern = r'(B9C56A012F2BA1FE00EEEB9E /\* Sources \*/ = \{[\s\S]*?files = \()([\s\S]*?)(\);)'
    def add_to_sources(match):
        prefix = match.group(1)
        current_files = match.group(2)
        suffix = match.group(3)
        new_files = current_files
        for f in sources:
            bid = build_id_map.get(f)
            if bid and bid not in current_files:
                new_files += f'\t\t\t\t{bid} /* {f} in Sources */,\n'
        return prefix + new_files + suffix

    content = re.sub(sources_phase_pattern, add_to_sources, content)

    # Resources phase for Aether (B9C56A032F2BA1FE00EEEB9E)
    resources_phase_pattern = r'(B9C56A032F2BA1FE00EEEB9E /\* Resources \*/ = \{[\s\S]*?files = \()([\s\S]*?)(\);)'
    def add_to_resources(match):
        prefix = match.group(1)
        current_files = match.group(2)
        suffix = match.group(3)
        new_files = current_files
        for f in resources:
            bid = build_id_map.get(f)
            if bid and bid not in current_files:
                new_files += f'\t\t\t\t{bid} /* {f} in Resources */,\n'
        return prefix + new_files + suffix

    content = re.sub(resources_phase_pattern, add_to_resources, content)

    with open(PROJECT_PATH, 'w') as f:
        f.write(content)
    print("Project file fixed with missing source references.")

if __name__ == '__main__':
    fix_project()
