import {readFile,writeFile,access} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
const run=(script,args=[])=>{const r=spawnSync(process.execPath,[script,...args],{stdio:'inherit'});if(r.status!==0)throw Error('Native preparation failed: '+script);};
run('build.mjs');
for(const platform of ['android','ios']){
 try{await access(platform);}catch{run('node_modules/@capacitor/cli/bin/capacitor',['add',platform]);}
}
const manifestPath='android/app/src/main/AndroidManifest.xml';
let manifest=await readFile(manifestPath,'utf8');
manifest=manifest.replace('android:allowBackup="true"','android:allowBackup="false"');
if(!manifest.includes('android:usesCleartextTraffic='))manifest=manifest.replace('android:allowBackup="false"','android:allowBackup="false"\n        android:usesCleartextTraffic="false"');
if(!manifest.includes('android:allowBackup="false"')||!manifest.includes('android:usesCleartextTraffic="false"'))throw Error('Review Android backup and TLS settings before building');
await writeFile(manifestPath,manifest);
const privacy=`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>NSPrivacyAccessedAPITypes</key><array><dict><key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryFileTimestamp</string><key>NSPrivacyAccessedAPITypeReasons</key><array><string>C617.1</string></array></dict></array></dict></plist>`;
await writeFile('ios/App/App/PrivacyInfo.xcprivacy',privacy);
const path='ios/App/App.xcodeproj/project.pbxproj';let s=await readFile(path,'utf8');
if(!s.includes('AABBCCDD0011223344556601')){
 s=s.replace('/* Begin PBXBuildFile section */','/* Begin PBXBuildFile section */\n\t\tAABBCCDD0011223344556601 /* PrivacyInfo.xcprivacy in Resources */ = {isa = PBXBuildFile; fileRef = AABBCCDD0011223344556602 /* PrivacyInfo.xcprivacy */; };');
 s=s.replace('/* Begin PBXFileReference section */','/* Begin PBXFileReference section */\n\t\tAABBCCDD0011223344556602 /* PrivacyInfo.xcprivacy */ = {isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; };');
 const at=s.indexOf('\t\t\tpath = App;'),before=s.lastIndexOf('children = (',at);
 if(at<0||before<0)throw Error('Review generated iOS app group');
 s=s.slice(0,before)+s.slice(before).replace('children = (','children = (\n\t\t\t\tAABBCCDD0011223344556602 /* PrivacyInfo.xcprivacy */,');
 const start=s.indexOf('/* Begin PBXResourcesBuildPhase section */');if(start<0)throw Error('Review generated iOS resources');
 s=s.slice(0,start)+s.slice(start).replace('files = (','files = (\n\t\t\t\tAABBCCDD0011223344556601 /* PrivacyInfo.xcprivacy in Resources */,');
 await writeFile(path,s);
}
if(!s.includes('TARGETED_DEVICE_FAMILY = "1,2"'))throw Error('iPhone/iPad universal target is required');
console.log('Android and universal iPhone/iPad projects generated with private storage and file API privacy declaration.');
