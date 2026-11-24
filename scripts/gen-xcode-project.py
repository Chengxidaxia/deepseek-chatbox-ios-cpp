#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 ios/ChatboxIOS.xcodeproj/project.pbxproj。
用确定性 ID（基于路径哈希），避免手写 UUID 冲突；改动源文件清单后重跑本脚本即可。
"""
import hashlib
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
IOS = ROOT / 'ios'


def oid(key: str) -> str:
    """从 key 生成稳定的 24 位大写十六进制对象 ID。"""
    return hashlib.sha1(key.encode('utf-8')).hexdigest()[:24].upper()


# ---- 源文件清单（相对仓库根）----
OBJC_SOURCES = [
    'ios/ChatboxIOS/Supporting/main.m',
    'ios/ChatboxIOS/Supporting/AppDelegate.mm',
    'ios/ChatboxIOS/Bridge/DSBoxService.mm',
    'ios/ChatboxIOS/Controllers/DSConversationListController.mm',
    'ios/ChatboxIOS/Controllers/DSChatViewController.mm',
    'ios/ChatboxIOS/Controllers/DSSettingsViewController.mm',
    'ios/ChatboxIOS/Views/DSMessageCell.mm',
]
CPP_SOURCES = [
    'core/src/store.cpp',
    'core/src/api.cpp',
    'tools/src/tools.cpp',
    'tools/src/qr-core.cpp',
]
RESOURCES = [
    'tools/tool_defs.json',
]
HEADERS = [
    'ios/ChatboxIOS/Bridge/DSBoxService.h',
    'ios/ChatboxIOS/Supporting/AppDelegate.h',
    'ios/ChatboxIOS/Controllers/DSConversationListController.h',
    'ios/ChatboxIOS/Controllers/DSChatViewController.h',
    'ios/ChatboxIOS/Controllers/DSSettingsViewController.h',
    'ios/ChatboxIOS/Views/DSMessageCell.h',
]

PROJECT_ID = oid('PROJECT')
MAIN_GROUP = oid('GROUP:main')
PRODUCTS_GROUP = oid('GROUP:products')
TARGET = oid('TARGET:app')
PRODUCT = oid('PRODUCT:app')
MAIN_PHASE = oid('PHASE:sources')
FRAMEWORK_PHASE = oid('PHASE:frameworks')
RESOURCE_PHASE = oid('PHASE:resources')
PROJECT_CONFIG_LIST = oid('CFGLIST:project')
TARGET_CONFIG_LIST = oid('CFGLIST:target')
CONFIG_DEBUG_PROJ = oid('CFG:project:debug')
CONFIG_RELEASE_PROJ = oid('CFG:project:release')
CONFIG_DEBUG_TARGET = oid('CFG:target:debug')
CONFIG_RELEASE_TARGET = oid('CFG:target:release')
GROUP_IOS = oid('GROUP:ios')
GROUP_SUPPORTING = oid('GROUP:supporting')
GROUP_BRIDGE = oid('GROUP:bridge')
GROUP_CONTROLLERS = oid('GROUP:controllers')
GROUP_VIEWS = oid('GROUP:views')
GROUP_CORE = oid('GROUP:core')
GROUP_TOOLS = oid('GROUP:tools')
GROUP_VENDOR = oid('GROUP:vendor')


def file_ref(path):
    return oid('FILE:' + path)


def build_file(path, phase_id):
    return oid('BUILD:' + phase_id + ':' + path)


def group_entries(paths, indent='\t\t\t\t'):
    lines = []
    for p in paths:
        name = pathlib.Path(p).name
        lines.append(f'{indent}{file_ref(p)} /* {name} */,')
    return '\n'.join(lines)


def pb_build_files(paths, phase_id):
    lines = []
    for p in paths:
        fid = file_ref(p)
        bid = build_file(p, phase_id)
        lines.append(f'\t\t{bid} /* {pathlib.Path(p).name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {pathlib.Path(p).name} */; }};')
    return '\n'.join(lines)


def generate():
    all_sources = OBJC_SOURCES + CPP_SOURCES
    src_build = pb_build_files(all_sources, MAIN_PHASE)
    res_build = pb_build_files(RESOURCES, RESOURCE_PHASE)

    # 文件引用：必须覆盖所有在 PBXGroup 中出现的路径，否则 Xcode 报 fileRef 缺失
    cpp_headers = [
        'core/include/api.hpp', 'core/include/crypto.hpp', 'core/include/model.hpp',
        'core/include/store.hpp', 'core/include/util.hpp',
        'tools/include/tools.hpp', 'tools/include/qr-core.hpp', 'tools/include/qr-tables.hpp',
        'vendor/json.hpp',
    ]
    all_refs = all_sources + RESOURCES + HEADERS + cpp_headers + ['ios/ChatboxIOS/Supporting/Info.plist']
    refs = []
    for p in all_refs:
        name = pathlib.Path(p).name
        refs.append(f'\t\t{file_ref(p)} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = '
                    + file_type(p) + f'; path = {name}; sourceTree = "<group>"; }};')
    refs.append(f'\t\t{PRODUCT} /* ChatboxIOS.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ChatboxIOS.app; sourceTree = BUILT_PRODUCTS_DIR; }};')

    out = f'''// !$*UTF8*$!
{{
  archiveVersion = 1;
  classes = {{
  }};
  objectVersion = 56;
  objects = {{

/* Begin PBXBuildFile section */
{src_build}
{res_build}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(refs)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{FRAMEWORK_PHASE} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{MAIN_GROUP} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{GROUP_IOS} /* ChatboxIOS */,
\t\t\t\t{GROUP_CORE} /* core */,
\t\t\t\t{GROUP_TOOLS} /* tools */,
\t\t\t\t{GROUP_VENDOR} /* vendor */,
\t\t\t\t{PRODUCTS_GROUP} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{PRODUCTS_GROUP} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{PRODUCT} /* ChatboxIOS.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{GROUP_IOS} /* ChatboxIOS */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{GROUP_SUPPORTING} /* Supporting */,
\t\t\t\t{GROUP_BRIDGE} /* Bridge */,
\t\t\t\t{GROUP_CONTROLLERS} /* Controllers */,
\t\t\t\t{GROUP_VIEWS} /* Views */,
\t\t\t\t{file_ref('ios/ChatboxIOS/Supporting/Info.plist')} /* Info.plist */,
\t\t\t);
\t\t\tpath = ChatboxIOS;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{GROUP_SUPPORTING} /* Supporting */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{group_entries([p for p in OBJC_SOURCES if 'Supporting' in p] + [p for p in HEADERS if 'Supporting' in p])}
\t\t\t);
\t\t\tpath = Supporting;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{GROUP_BRIDGE} /* Bridge */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{group_entries([p for p in OBJC_SOURCES if 'Bridge' in p] + [p for p in HEADERS if 'Bridge' in p])}
\t\t\t);
\t\t\tpath = Bridge;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{GROUP_CONTROLLERS} /* Controllers */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{group_entries([p for p in OBJC_SOURCES if 'Controllers' in p] + [p for p in HEADERS if 'Controllers' in p])}
\t\t\t);
\t\t\tpath = Controllers;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{GROUP_VIEWS} /* Views */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{group_entries([p for p in OBJC_SOURCES if 'Views' in p] + [p for p in HEADERS if 'Views' in p])}
\t\t\t);
\t\t\tpath = Views;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{GROUP_CORE} /* core */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{group_entries([p for p in CPP_SOURCES if p.startswith('core/')])}
\t\t\t\t{oid('DIR:core/include')} /* include */,
\t\t\t);
\t\t\tpath = core;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{oid('DIR:core/include')} /* include */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{group_entries(['core/include/api.hpp','core/include/crypto.hpp','core/include/model.hpp','core/include/store.hpp','core/include/util.hpp'])}
\t\t\t);
\t\t\tpath = include;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{GROUP_TOOLS} /* tools */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{group_entries([p for p in CPP_SOURCES if p.startswith('tools/src/')] + RESOURCES)}
\t\t\t\t{oid('DIR:tools/include')} /* include */,
\t\t\t);
\t\t\tpath = tools;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{oid('DIR:tools/include')} /* include */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{group_entries(['tools/include/tools.hpp','tools/include/qr-core.hpp','tools/include/qr-tables.hpp'])}
\t\t\t);
\t\t\tpath = include;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{GROUP_VENDOR} /* vendor */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{file_ref('vendor/json.hpp')} /* json.hpp */,
\t\t\t);
\t\t\tpath = vendor;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{TARGET} /* ChatboxIOS */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {TARGET_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "ChatboxIOS" */;
\t\t\tbuildPhases = (
\t\t\t\t{MAIN_PHASE} /* Sources */,
\t\t\t\t{FRAMEWORK_PHASE} /* Frameworks */,
\t\t\t\t{RESOURCE_PHASE} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = ChatboxIOS;
\t\t\tproductName = ChatboxIOS;
\t\t\tproductReference = {PRODUCT} /* ChatboxIOS.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{PROJECT_ID} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{TARGET} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {PROJECT_CONFIG_LIST} /* Build configuration list for PBXProject "ChatboxIOS" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = zh_CN;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t\tzh_CN,
\t\t\t);
\t\t\tmainGroup = {MAIN_GROUP};
\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{TARGET} /* ChatboxIOS */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{RESOURCE_PHASE} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(f'\t\t\t\t{build_file(p, RESOURCE_PHASE)} /* {pathlib.Path(p).name} in Resources */,' for p in RESOURCES)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{MAIN_PHASE} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(f'\t\t\t\t{build_file(p, MAIN_PHASE)} /* {pathlib.Path(p).name} in Sources */,' for p in all_sources)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{CONFIG_DEBUG_PROJ} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "c++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = c11;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{CONFIG_RELEASE_PROJ} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "c++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = c11;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{CONFIG_DEBUG_TARGET} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 87;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tHEADER_SEARCH_PATHS = (
\t\t\t\t\t"$(SRCROOT)/../core/include",
\t\t\t\t\t"$(SRCROOT)/../tools/include",
\t\t\t\t\t"$(SRCROOT)/../vendor",
\t\t\t\t\t"$(SRCROOT)/../ios/ChatboxIOS/Bridge",
\t\t\t\t\t"$(SRCROOT)/../ios/ChatboxIOS/Controllers",
\t\t\t\t\t"$(SRCROOT)/../ios/ChatboxIOS/Views",
\t\t\t\t\t"$(SRCROOT)/../ios/ChatboxIOS/Supporting",
\t\t\t\t\t"$(VCPKG_INSTALLED)/include",
\t\t\t\t);
\t\t\t\tINFOPLIST_FILE = ChatboxIOS/Supporting/Info.plist;
\t\t\t\tLIBRARY_SEARCH_PATHS = (
\t\t\t\t\t"$(VCPKG_INSTALLED)/lib",
\t\t\t\t);
\t\t\t\tOTHER_LDFLAGS = (
\t\t\t\t\t"-lcurl",
\t\t\t\t\t"-lssl",
\t\t\t\t\t"-lcrypto",
\t\t\t\t\t"-lz",
\t\t\t\t\t"-lsqlite3",
\t\t\t\t);
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.12.4;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.dsbox.chatbox;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{CONFIG_RELEASE_TARGET} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 87;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tHEADER_SEARCH_PATHS = (
\t\t\t\t\t"$(SRCROOT)/../core/include",
\t\t\t\t\t"$(SRCROOT)/../tools/include",
\t\t\t\t\t"$(SRCROOT)/../vendor",
\t\t\t\t\t"$(SRCROOT)/../ios/ChatboxIOS/Bridge",
\t\t\t\t\t"$(SRCROOT)/../ios/ChatboxIOS/Controllers",
\t\t\t\t\t"$(SRCROOT)/../ios/ChatboxIOS/Views",
\t\t\t\t\t"$(SRCROOT)/../ios/ChatboxIOS/Supporting",
\t\t\t\t\t"$(VCPKG_INSTALLED)/include",
\t\t\t\t);
\t\t\t\tINFOPLIST_FILE = ChatboxIOS/Supporting/Info.plist;
\t\t\t\tLIBRARY_SEARCH_PATHS = (
\t\t\t\t\t"$(VCPKG_INSTALLED)/lib",
\t\t\t\t);
\t\t\t\tOTHER_LDFLAGS = (
\t\t\t\t\t"-lcurl",
\t\t\t\t\t"-lssl",
\t\t\t\t\t"-lcrypto",
\t\t\t\t\t"-lz",
\t\t\t\t\t"-lsqlite3",
\t\t\t\t);
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.12.4;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.dsbox.chatbox;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{PROJECT_CONFIG_LIST} /* Build configuration list for PBXProject "ChatboxIOS" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{CONFIG_DEBUG_PROJ} /* Debug */,
\t\t\t\t{CONFIG_RELEASE_PROJ} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{TARGET_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "ChatboxIOS" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{CONFIG_DEBUG_TARGET} /* Debug */,
\t\t\t\t{CONFIG_RELEASE_TARGET} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {PROJECT_ID} /* Project object */;
}}
'''
    return out


def file_type(path):
    ext = pathlib.Path(path).suffix
    return {
        '.m': 'sourcecode.c.objc',
        '.mm': 'sourcecode.cpp.objcpp',
        '.cpp': 'sourcecode.cpp.cpp',
        '.h': 'sourcecode.c.h',
        '.hpp': 'sourcecode.cpp.h',
        '.json': 'text.json',
        '.plist': 'text.plist.xml',
    }.get(ext, 'text')


if __name__ == '__main__':
    pbx = IOS / 'ChatboxIOS.xcodeproj' / 'project.pbxproj'
    pbx.parent.mkdir(parents=True, exist_ok=True)
    pbx.write_text(generate(), encoding='utf-8')
    print('generated', pbx, len(pbx.read_text(encoding='utf-8')), 'chars')
