import os
import uuid

def generate_id():
    return uuid.uuid4().hex[:24].upper()

PROJECT_PATH = 'Aether.xcodeproj/project.pbxproj'

def rebuild():
    PROJECT_OBJ_ID = 'B9C569FD2F2BA1FE00EEEB9E'
    APP_TARGET_ID = 'B9C56A042F2BA1FE00EEEB9E'
    APP_PRODUCT_ID = 'B9C56A052F2BA1FE00EEEB9E'
    
    SOURCES_PHASE_ID = generate_id()
    FRAMEWORKS_PHASE_ID = generate_id()
    RESOURCES_PHASE_ID = generate_id()
    
    DEBUG_CONFIG_ID = generate_id()
    RELEASE_CONFIG_ID = generate_id()
    CONFIG_LIST_ID = generate_id()
    PROJECT_CONFIG_LIST_ID = generate_id()
    
    sources = ['AetherApp.swift', 'ContentView.swift', 'HeadMotionManager.swift', 'SystemExtensionManager.swift']
    resources = ['Assets.xcassets']
    
    file_refs = []
    build_files_sources = []
    build_files_resources = []
    
    for f in sources:
        fid = generate_id()
        bid = generate_id()
        file_refs.append(f'\t\t{fid} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Apps/AetherCore/{f}; sourceTree = "<group>"; }};')
        build_files_sources.append(f'\t\t{bid} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {f} */; }};')
        
    for f in resources:
        fid = generate_id()
        bid = generate_id()
        file_refs.append(f'\t\t{fid} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Apps/AetherCore/{f}; sourceTree = "<group>"; }};')
        build_files_resources.append(f'\t\t{bid} /* {f} in Resources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {f} */; }};')

    file_refs_str = "\n".join(file_refs)
    bf_sources_str = "\n".join(build_files_sources)
    bf_resources_str = "\n".join(build_files_resources)
    bf_sources_list = "\n".join([f"\t\t\t\t{bid.split()[0]}," for bid in build_files_sources])
    bf_resources_list = "\n".join([f"\t\t\t\t{bid.split()[0]}," for bid in build_files_resources])

    template = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
{bf_sources_str}
{bf_resources_str}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		{APP_PRODUCT_ID} /* Aether.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Aether.app; sourceTree = BUILT_PRODUCTS_DIR; }};
{file_refs_str}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{FRAMEWORKS_PHASE_ID} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		B9C569FC2F2BA1FE00EEEB9E /* Project Root */ = {{
			isa = PBXGroup;
			children = (
				B9C56A062F2BA1FE00EEEB9E /* Products */,
			);
			sourceTree = "<group>";
		}};
		B9C56A062F2BA1FE00EEEB9E /* Products */ = {{
			isa = PBXGroup;
			children = (
				{APP_PRODUCT_ID} /* Aether.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{APP_TARGET_ID} /* Aether */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {CONFIG_LIST_ID} /* Build configuration list for PBXNativeTarget "Aether" */;
			buildPhases = (
				{SOURCES_PHASE_ID} /* Sources */,
				{FRAMEWORKS_PHASE_ID} /* Frameworks */,
				{RESOURCES_PHASE_ID} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = Aether;
			productName = Aether;
			productReference = {APP_PRODUCT_ID} /* Aether.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{PROJECT_OBJ_ID} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2620;
				LastUpgradeCheck = 2620;
				TargetAttributes = {{
					{APP_TARGET_ID} = {{
						CreatedOnToolsVersion = 26.2;
					}};
				}};
			}};
			buildConfigurationList = {PROJECT_CONFIG_LIST_ID} /* Build configuration list for PBXProject "Aether" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = B9C569FC2F2BA1FE00EEEB9E;
			productRefGroup = B9C56A062F2BA1FE00EEEB9E /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{APP_TARGET_ID} /* Aether */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{RESOURCES_PHASE_ID} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{bf_resources_list}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{SOURCES_PHASE_ID} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{bf_sources_list}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{DEBUG_CONFIG_ID} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_STYLE = Manual;
				CODE_SIGN_IDENTITY = "-";
				AD_HOC_CODE_SIGNING_ALLOWED = YES;
				CODE_SIGNING_REQUIRED = NO;
				MACOSX_DEPLOYMENT_TARGET = 15.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.7fei.Aether;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
				GENERATE_INFOPLIST_FILE = YES;
				SDKROOT = macosx;
				ENABLE_HARDENED_RUNTIME = NO;
				SWIFT_OBJC_BRIDGING_HEADER = "Apps/AetherCore/AetherCore-Bridging-Header.h";
			}};
			name = Debug;
		}};
		{RELEASE_CONFIG_ID} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_STYLE = Manual;
				CODE_SIGN_IDENTITY = "-";
				MACOSX_DEPLOYMENT_TARGET = 15.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.7fei.Aether;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
				GENERATE_INFOPLIST_FILE = YES;
				SDKROOT = macosx;
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{CONFIG_LIST_ID} /* Build configuration list for PBXNativeTarget "Aether" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{DEBUG_CONFIG_ID} /* Debug */,
				{RELEASE_CONFIG_ID} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{PROJECT_CONFIG_LIST_ID} /* Build configuration list for PBXProject "Aether" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{DEBUG_CONFIG_ID} /* Debug */,
				{RELEASE_CONFIG_ID} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {PROJECT_OBJ_ID} /* Project object */;
}}
"""
    with open(PROJECT_PATH, 'w') as f:
        f.write(template)
    print("Project rebuilt with correct syntax.")

if __name__ == '__main__':
    rebuild()
