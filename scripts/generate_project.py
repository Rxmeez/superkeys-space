"""Generates Superkeys.xcodeproj. Edit this instead of the .pbxproj, then run
`python3 scripts/generate_project.py` from the repository root."""
import hashlib
def uid(s): return hashlib.md5(s.encode()).hexdigest()[:24].upper()
swift=["SuperkeysApp","Updater","WhatsNew","Onboarding","AppState","HyperEventTap","CapsLock","KeyCodes","WindowManager","WindowArranger","AXWindow","SpaceManager","SkyLightBridge","AppLauncher","BindingsStore","Permissions","SettingsRootView","ShortcutsView","Components","SettingsWindowController","CheatSheet","ConfigFile","MenuBarContent"]
# Unit tests, hosted in the app (which skips its startup under XCTest).
tests=["ConfigFileTests","KeystrokeTests","KeyHandlingTests","KeyGroupsTests"]
fw=["AppKit","SwiftUI","ApplicationServices","ServiceManagement","UniformTypeIdentifiers","Combine","Carbon","CoreGraphics"]
L=[]
a=L.append
a("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n")
a("/* Begin PBXBuildFile section */")
for n in swift: a(f"\t\t{uid('bf'+n)} /* {n}.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {uid('fr'+n)} /* {n}.swift */; }};")
a(f"\t\t{uid('bfassets')} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {uid('frassets')} /* Assets.xcassets */; }};")
for f in fw: a(f"\t\t{uid('bffw'+f)} /* {f}.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {uid('frfw'+f)} /* {f}.framework */; }};")
a(f"\t\t{uid('bfsparkle')} /* Sparkle in Frameworks */ = {{isa = PBXBuildFile; productRef = {uid('sparkleprod')} /* Sparkle */; }};")
for n in tests: a(f"\t\t{uid('tbf'+n)} /* {n}.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {uid('tfr'+n)} /* {n}.swift */; }};")
a("/* End PBXBuildFile section */\n")
a(f"""/* Begin PBXContainerItemProxy section */
\t\t{uid('tproxy')} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {uid('project')} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {uid('target')};
\t\t\tremoteInfo = Superkeys;
\t\t}};
/* End PBXContainerItemProxy section */
""")
a("/* Begin PBXFileReference section */")
a(f"\t\t{uid('product')} /* Superkeys.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Superkeys.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
for n in swift: a(f"\t\t{uid('fr'+n)} /* {n}.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {n}.swift; sourceTree = \"<group>\"; }};")
a(f"\t\t{uid('frassets')} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};")
a(f"\t\t{uid('frplist')} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
a(f"\t\t{uid('frxcconfig')} /* Signing.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Signing.xcconfig; sourceTree = \"<group>\"; }};")
a(f"\t\t{uid('frent')} /* Superkeys.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Superkeys.entitlements; sourceTree = \"<group>\"; }};")
for f in fw: a(f"\t\t{uid('frfw'+f)} /* {f}.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = {f}.framework; path = System/Library/Frameworks/{f}.framework; sourceTree = SDKROOT; }};")
a(f"\t\t{uid('testproduct')} /* SuperkeysTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SuperkeysTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
for n in tests: a(f"\t\t{uid('tfr'+n)} /* {n}.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {n}.swift; sourceTree = \"<group>\"; }};")
a("/* End PBXFileReference section */\n")
a("/* Begin PBXFrameworksBuildPhase section */")
a(f"\t\t{uid('fwphase')} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (")
for f in fw: a(f"\t\t\t\t{uid('bffw'+f)} /* {f}.framework in Frameworks */,")
a(f"\t\t\t\t{uid('bfsparkle')} /* Sparkle in Frameworks */,")
a("\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};")
a(f"\t\t{uid('tfwphase')} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
a("/* End PBXFrameworksBuildPhase section */\n")
a("/* Begin PBXGroup section */")
a(f"\t\t{uid('gmain')} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{uid('frxcconfig')} /* Signing.xcconfig */,\n\t\t\t\t{uid('gsrc')} /* Superkeys */,\n\t\t\t\t{uid('gtests')} /* SuperkeysTests */,\n\t\t\t\t{uid('gfw')} /* Frameworks */,\n\t\t\t\t{uid('gprod')} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
a(f"\t\t{uid('gsrc')} /* Superkeys */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (")
for n in swift: a(f"\t\t\t\t{uid('fr'+n)} /* {n}.swift */,")
a(f"\t\t\t\t{uid('frassets')} /* Assets.xcassets */,\n\t\t\t\t{uid('frplist')} /* Info.plist */,\n\t\t\t\t{uid('frent')} /* Superkeys.entitlements */,\n\t\t\t);\n\t\t\tpath = Superkeys;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
a(f"\t\t{uid('gtests')} /* SuperkeysTests */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (")
for n in tests: a(f"\t\t\t\t{uid('tfr'+n)} /* {n}.swift */,")
a("\t\t\t);\n\t\t\tpath = SuperkeysTests;\n\t\t\tsourceTree = \"<group>\";\n\t\t};")
a(f"\t\t{uid('gfw')} /* Frameworks */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (")
for f in fw: a(f"\t\t\t\t{uid('frfw'+f)} /* {f}.framework */,")
a("\t\t\t);\n\t\t\tname = Frameworks;\n\t\t\tsourceTree = \"<group>\";\n\t\t};")
a(f"\t\t{uid('gprod')} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{uid('product')} /* Superkeys.app */,\n\t\t\t\t{uid('testproduct')} /* SuperkeysTests.xctest */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
a("/* End PBXGroup section */\n")
a("/* Begin PBXNativeTarget section */")
a(f"""\t\t{uid('target')} /* Superkeys */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {uid('cltarget')} /* Build configuration list for PBXNativeTarget "Superkeys" */;
\t\t\tbuildPhases = (
\t\t\t\t{uid('srcphase')} /* Sources */,
\t\t\t\t{uid('fwphase')} /* Frameworks */,
\t\t\t\t{uid('respase')} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = Superkeys;
\t\t\tpackageProductDependencies = (
\t\t\t\t{uid('sparkleprod')} /* Sparkle */,
\t\t\t);
\t\t\tproductName = Superkeys;
\t\t\tproductReference = {uid('product')} /* Superkeys.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{uid('ttarget')} /* SuperkeysTests */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {uid('cltests')} /* Build configuration list for PBXNativeTarget "SuperkeysTests" */;
\t\t\tbuildPhases = (
\t\t\t\t{uid('tsrcphase')} /* Sources */,
\t\t\t\t{uid('tfwphase')} /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{uid('tdep')} /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = SuperkeysTests;
\t\t\tproductName = SuperkeysTests;
\t\t\tproductReference = {uid('testproduct')} /* SuperkeysTests.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
\t\t}};""")
a("/* End PBXNativeTarget section */\n")
a(f"""/* Begin PBXProject section */
\t\t{uid('project')} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t}};
\t\t\tbuildConfigurationList = {uid('clproject')} /* Build configuration list for PBXProject "Superkeys" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {uid('gmain')};
\t\t\tpackageReferences = (
\t\t\t\t{uid('sparklepkg')} /* XCRemoteSwiftPackageReference "Sparkle" */,
\t\t\t);
\t\t\tproductRefGroup = {uid('gprod')} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{uid('target')} /* Superkeys */,
\t\t\t\t{uid('ttarget')} /* SuperkeysTests */,
\t\t\t);
\t\t}};
/* End PBXProject section */
""")
a(f"/* Begin PBXResourcesBuildPhase section */\n\t\t{uid('respase')} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t{uid('bfassets')} /* Assets.xcassets in Resources */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n/* End PBXResourcesBuildPhase section */\n")
a(f"/* Begin PBXSourcesBuildPhase section */\n\t\t{uid('srcphase')} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (")
for n in swift: a(f"\t\t\t\t{uid('bf'+n)} /* {n}.swift in Sources */,")
a("\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};")
a(f"\t\t{uid('tsrcphase')} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (")
for n in tests: a(f"\t\t\t\t{uid('tbf'+n)} /* {n}.swift in Sources */,")
a("\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n/* End PBXSourcesBuildPhase section */\n")
a(f"/* Begin PBXTargetDependency section */\n\t\t{uid('tdep')} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {uid('target')} /* Superkeys */;\n\t\t\ttargetProxy = {uid('tproxy')} /* PBXContainerItemProxy */;\n\t\t}};\n/* End PBXTargetDependency section */\n")

common="""\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_VERSION = 5.0;"""
a("/* Begin XCBuildConfiguration section */")
a(f"""\t\t{uid('pdebug')} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{common}
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{uid('prelease')} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{common}
\t\t\t\tCOPY_PHASE_STRIP = YES;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t}};
\t\t\tname = Release;
\t\t}};""")
t="""\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Superkeys/Superkeys.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Manual;
\t\t\t\tCURRENT_PROJECT_VERSION = 9;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_APP_SANDBOX = NO;
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = Superkeys/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "@executable_path/../Frameworks";
\t\t\t\tMARKETING_VERSION = 0.2.5;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = space.superkeys;
\t\t\t\tPRODUCT_NAME = Superkeys;
\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "";"""
# Development builds get their own identity, so macOS never mixes them up with
# an installed release: separate Accessibility entry, preferences and name.
dev=t.replace("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;","ASSETCATALOG_COMPILER_APPICON_NAME = AppIconDev;").replace("PRODUCT_BUNDLE_IDENTIFIER = space.superkeys;","PRODUCT_BUNDLE_IDENTIFIER = space.superkeys.dev;").replace("PRODUCT_NAME = Superkeys;",'PRODUCT_NAME = "Superkeys Dev";')
assert dev != t
for cfg,k,settings in (("Debug","tdebug",dev),("Release","trelease",t)):
    a(f"\t\t{uid(k)} /* {cfg} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbaseConfigurationReference = {uid('frxcconfig')} /* Signing.xcconfig */;\n\t\t\tbuildSettings = {{\n{settings}\n\t\t\t}};\n\t\t\tname = {cfg};\n\t\t}};")
for cfg,k,host in (("Debug","ttdebug","Superkeys Dev.app/Contents/MacOS/Superkeys Dev"),("Release","ttrelease","Superkeys.app/Contents/MacOS/Superkeys")):
    a(f"""\t\t{uid(k)} /* {cfg} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tCODE_SIGN_IDENTITY = "-";
\t\t\t\tCODE_SIGN_STYLE = Manual;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = space.superkeys.tests;
\t\t\t\tPRODUCT_NAME = SuperkeysTests;
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/{host}";
\t\t\t}};
\t\t\tname = {cfg};
\t\t}};""")
a("/* End XCBuildConfiguration section */\n")
a(f"""/* Begin XCConfigurationList section */
\t\t{uid('clproject')} /* Build configuration list for PBXProject "Superkeys" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{uid('pdebug')} /* Debug */,
\t\t\t\t{uid('prelease')} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{uid('cltarget')} /* Build configuration list for PBXNativeTarget "Superkeys" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{uid('tdebug')} /* Debug */,
\t\t\t\t{uid('trelease')} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{uid('cltests')} /* Build configuration list for PBXNativeTarget "SuperkeysTests" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{uid('ttdebug')} /* Debug */,
\t\t\t\t{uid('ttrelease')} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

/* Begin XCRemoteSwiftPackageReference section */
\t\t{uid('sparklepkg')} /* XCRemoteSwiftPackageReference "Sparkle" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "https://github.com/sparkle-project/Sparkle";
\t\t\trequirement = {{
\t\t\t\tkind = upToNextMajorVersion;
\t\t\t\tminimumVersion = 2.10.0;
\t\t\t}};
\t\t}};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t{uid('sparkleprod')} /* Sparkle */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {uid('sparklepkg')} /* XCRemoteSwiftPackageReference "Sparkle" */;
\t\t\tproductName = Sparkle;
\t\t}};
/* End XCSwiftPackageProductDependency section */
\t}};
\trootObject = {uid('project')} /* Project object */;
}}""")
open("Superkeys.xcodeproj/project.pbxproj","w").write("\n".join(L)+"\n")
T=uid('target')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{T}" BuildableName = "Superkeys.app" BlueprintName = "Superkeys" ReferencedContainer = "container:Superkeys.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{uid('ttarget')}" BuildableName = "SuperkeysTests.xctest" BlueprintName = "SuperkeysTests" ReferencedContainer = "container:Superkeys.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{T}" BuildableName = "Superkeys.app" BlueprintName = "Superkeys" ReferencedContainer = "container:Superkeys.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
open("Superkeys.xcodeproj/xcshareddata/xcschemes/Superkeys.xcscheme","w").write(scheme)
