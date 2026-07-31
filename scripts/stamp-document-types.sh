#!/usr/bin/env bash
set -euo pipefail

PLIST="${1:?usage: stamp-document-types.sh /path/to/Info.plist}"

plist() {
  /usr/libexec/PlistBuddy -c "$1" "$PLIST" >/dev/null
}

add_document_type() {
  local index="$1"
  local name="$2"
  local icon="$3"
  local extension="$4"
  local uti="$5"

  plist "Add :CFBundleDocumentTypes:$index dict"
  plist "Add :CFBundleDocumentTypes:$index:CFBundleTypeName string $name"
  plist "Add :CFBundleDocumentTypes:$index:CFBundleTypeRole string Editor"
  plist "Add :CFBundleDocumentTypes:$index:CFBundleTypeIconFile string $icon"
  plist "Add :CFBundleDocumentTypes:$index:CFBundleTypeExtensions array"
  plist "Add :CFBundleDocumentTypes:$index:CFBundleTypeExtensions:0 string $extension"
  plist "Add :CFBundleDocumentTypes:$index:LSItemContentTypes array"
  plist "Add :CFBundleDocumentTypes:$index:LSItemContentTypes:0 string $uti"
}

add_exported_type() {
  local index="$1"
  local description="$2"
  local extension="$3"
  local uti="$4"

  plist "Add :UTExportedTypeDeclarations:$index dict"
  plist "Add :UTExportedTypeDeclarations:$index:UTTypeIdentifier string $uti"
  plist "Add :UTExportedTypeDeclarations:$index:UTTypeDescription string $description"
  plist "Add :UTExportedTypeDeclarations:$index:UTTypeConformsTo array"
  plist "Add :UTExportedTypeDeclarations:$index:UTTypeConformsTo:0 string public.data"
  plist "Add :UTExportedTypeDeclarations:$index:UTTypeTagSpecification dict"
  plist "Add :UTExportedTypeDeclarations:$index:UTTypeTagSpecification:public.filename-extension array"
  plist "Add :UTExportedTypeDeclarations:$index:UTTypeTagSpecification:public.filename-extension:0 string $extension"
}

plist "Delete :CFBundleDocumentTypes" 2>/dev/null || true
plist "Add :CFBundleDocumentTypes array"
add_document_type 0 "Forest FB-01 Single Voice" "SingleVoiceDocumentIcon.icns" "fbv" "com.gadzikowski.fb01.single-voice"
add_document_type 1 "Forest FB-01 Single Configuration" "SingleConfigurationDocumentIcon.icns" "fbc" "com.gadzikowski.fb01.single-configuration"
add_document_type 2 "Forest FB-01 Voice Bank" "VoiceBankDocumentIcon.icns" "fbvb" "com.gadzikowski.fb01.voice-bank"
add_document_type 3 "Forest FB-01 Configuration Bank" "ConfigurationBankDocumentIcon.icns" "fbcb" "com.gadzikowski.fb01.configuration-bank"
add_document_type 4 "Yamaha FB-01 SysEx" "AppIcon.icns" "fbx" "com.gadzikowski.fb01.sysex"

plist "Delete :UTExportedTypeDeclarations" 2>/dev/null || true
plist "Add :UTExportedTypeDeclarations array"
add_exported_type 0 "Forest FB-01 Single Voice" "fbv" "com.gadzikowski.fb01.single-voice"
add_exported_type 1 "Forest FB-01 Single Configuration" "fbc" "com.gadzikowski.fb01.single-configuration"
add_exported_type 2 "Forest FB-01 Voice Bank" "fbvb" "com.gadzikowski.fb01.voice-bank"
add_exported_type 3 "Forest FB-01 Configuration Bank" "fbcb" "com.gadzikowski.fb01.configuration-bank"
add_exported_type 4 "Yamaha FB-01 SysEx" "fbx" "com.gadzikowski.fb01.sysex"
