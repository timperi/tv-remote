#!/usr/bin/env python3
"""Write RoomRemote.xcodeproj. Run from the repository root."""

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = [
    "FrameCodec.swift",
    "PairingMachine.swift",
    "PairingMessages.swift",
    "PairingSecret.swift",
    "Protobuf.swift",
    "RSAPublicKey.swift",
    "RemoteMessages.swift",
    "RemoteSession.swift",
    "RemoteTyping.swift",
    "SHA256.swift",
    "X509Certificate.swift",
]
APP = [
    "ATVSocket.swift",
    "DeviceStore.swift",
    "DevicesView.swift",
    "IdentityStore.swift",
    "KeyboardView.swift",
    "PairingView.swift",
    "RemoteView.swift",
    "RoomRemoteApp.swift",
    "TVBrowser.swift",
    "TVSession.swift",
    "Theme.swift",
]


def oid(name: str) -> str:
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def main() -> None:
    objects = []

    def add(key: str, body: str) -> str:
        identifier = oid(key)
        objects.append(f"\t\t{identifier} /* {key} */ = {body};")
        return identifier

    swift_build_files = []
    app_children = []
    core_children = []

    for name in APP:
        ref = add(f"ref App/{name}", """{
			isa = PBXFileReference;
			lastKnownFileType = sourcecode.swift;
			path = %s;
			sourceTree = "<group>";
		}""" % name)
        build = add(f"build {name}", """{
			isa = PBXBuildFile;
			fileRef = %s /* %s */;
		}""" % (ref, name))
        swift_build_files.append(build)
        app_children.append(ref)

    assets = add("ref Assets.xcassets", """{
			isa = PBXFileReference;
			lastKnownFileType = folder.assetcatalog;
			path = Assets.xcassets;
			sourceTree = "<group>";
		}""")
    assets_build = add("build Assets", """{
			isa = PBXBuildFile;
			fileRef = %s /* Assets.xcassets */;
		}""" % assets)
    privacy = add("ref PrivacyInfo.xcprivacy", """{
			isa = PBXFileReference;
			lastKnownFileType = text.plist.xml;
			path = PrivacyInfo.xcprivacy;
			sourceTree = "<group>";
		}""")
    privacy_build = add("build Privacy", """{
			isa = PBXBuildFile;
			fileRef = %s /* PrivacyInfo.xcprivacy */;
		}""" % privacy)
    info = add("ref Info.plist", """{
			isa = PBXFileReference;
			lastKnownFileType = text.plist.xml;
			path = Info.plist;
			sourceTree = "<group>";
		}""")
    app_children.extend([assets, privacy, info])

    for name in CORE:
        ref = add(f"ref core/{name}", """{
			isa = PBXFileReference;
			lastKnownFileType = sourcecode.swift;
			path = %s;
			sourceTree = "<group>";
		}""" % name)
        build = add(f"build core {name}", """{
			isa = PBXBuildFile;
			fileRef = %s /* %s */;
		}""" % (ref, name))
        swift_build_files.append(build)
        core_children.append(ref)

    product = add("product RoomRemote.app", """{
			isa = PBXFileReference;
			explicitFileType = wrapper.application;
			includeInIndex = 0;
			path = RoomRemote.app;
			sourceTree = BUILT_PRODUCTS_DIR;
		}""")

    sources_phase = add("sources", """{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
%s
			);
			runOnlyForDeploymentPostprocessing = 0;
		}""" % "\n".join(f"\t\t\t\t{item} /* {item} */," for item in swift_build_files))
    frameworks_phase = add("frameworks", """{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}""")
    resources_phase = add("resources", """{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				%s /* Assets.xcassets */,
				%s /* PrivacyInfo.xcprivacy */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}""" % (assets_build, privacy_build))

    core_group = add("group ATVRemoteCore", """{
			isa = PBXGroup;
			children = (
%s
			);
			path = ATVRemoteCore;
			sourceTree = "<group>";
		}""" % "\n".join(f"\t\t\t\t{item} /* {item} */," for item in core_children))
    sources_group = add("group Sources", """{
			isa = PBXGroup;
			children = (
				%s /* ATVRemoteCore */,
			);
			path = Sources;
			sourceTree = "<group>";
		}""" % core_group)
    app_group = add("group App", """{
			isa = PBXGroup;
			children = (
%s
			);
			path = App;
			sourceTree = "<group>";
		}""" % "\n".join(f"\t\t\t\t{item} /* {item} */," for item in app_children))
    products_group = add("group Products", """{
			isa = PBXGroup;
			children = (
				%s /* RoomRemote.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}""" % product)
    main_group = add("group main", """{
			isa = PBXGroup;
			children = (
				%s /* App */,
				%s /* Sources */,
				%s /* Products */,
			);
			sourceTree = "<group>";
		}""" % (app_group, sources_group, products_group))

    target_debug = add("config target Debug", target_config("Debug"))
    target_release = add("config target Release", target_config("Release"))
    target_list = add("config list target", """{
			isa = XCConfigurationList;
			buildConfigurations = (
				%s /* Debug */,
				%s /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}""" % (target_debug, target_release))

    target = add("target RoomRemote", """{
			isa = PBXNativeTarget;
			buildConfigurationList = %s /* target configs */;
			buildPhases = (
				%s /* Sources */,
				%s /* Frameworks */,
				%s /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = RoomRemote;
			productName = RoomRemote;
			productReference = %s /* RoomRemote.app */;
			productType = "com.apple.product-type.application";
		}""" % (target_list, sources_phase, frameworks_phase, resources_phase, product))

    project_debug = add("config project Debug", project_config("Debug"))
    project_release = add("config project Release", project_config("Release"))
    project_list = add("config list project", """{
			isa = XCConfigurationList;
			buildConfigurations = (
				%s /* Debug */,
				%s /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}""" % (project_debug, project_release))

    project = add("project", """{
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				ORGANIZATIONNAME = Personal;
				TargetAttributes = {
					%s = {
						CreatedOnToolsVersion = 15.0;
					};
				};
			};
			buildConfigurationList = %s /* project configs */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = %s /* main */;
			productRefGroup = %s /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				%s /* RoomRemote */,
			);
		}""" % (target, project_list, main_group, products_group, target))

    text = """// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

%s
	};
	rootObject = %s /* project */;
}
""" % ("\n".join(objects), project)
    destination = ROOT / "RoomRemote.xcodeproj" / "project.pbxproj"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text)
    print(destination)


def target_config(name: str) -> str:
    debug = name == "Debug"
    swift_opt = "-Onone" if debug else "-O"
    conditions = "DEBUG" if debug else ""
    return """{
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = App/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = "Room Remote";
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = personal.roomremote;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_STRICT_CONCURRENCY = minimal;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
				%s
			};
			name = %s;
		}""" % (
        f"SWIFT_ACTIVE_COMPILATION_CONDITIONS = {conditions};\n\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"{swift_opt}\";"
        if debug
        else f"SWIFT_COMPILATION_MODE = wholemodule;\n\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"{swift_opt}\";",
        name,
    )


def project_config(name: str) -> str:
    debug = name == "Debug"
    return """{
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = %s;
				DEBUG_INFORMATION_FORMAT = %s;
				ENABLE_NS_ASSERTIONS = %s;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = %s;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MTL_ENABLE_DEBUG_INFO = %s;
				ONLY_ACTIVE_ARCH = %s;
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.0;
				VALIDATE_PRODUCT = %s;
			};
			name = %s;
		}""" % (
        "NO" if debug else "NO",
        "dwarf" if debug else "dwarf-with-dsym",
        "YES" if debug else "NO",
        "0" if debug else "s",
        "INCLUDE_SOURCE" if debug else "NO",
        "YES" if debug else "NO",
        "NO" if debug else "YES",
        name,
    )


if __name__ == "__main__":
    main()
