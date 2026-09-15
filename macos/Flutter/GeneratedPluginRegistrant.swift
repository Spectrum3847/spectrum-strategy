import FlutterMacOS
import Foundation

import apple_ai
import apple_web_auth
import cloud_firestore
import cloud_functions
import device_info_plus
import file_picker_darwin
import file_selector_macos
import firebase_auth
import firebase_core
import flutter_image_compress_macos
import google_sign_in_ios
import liquid_glass
import mobile_scanner
import package_info_plus
import screen_retriever_macos
import share_plus
import shared_preferences_foundation
import tray_manager
import url_launcher_macos
import webview_flutter_wkwebview
import window_manager

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  AppleAiPlugin.register(with: registry.registrar(forPlugin: "AppleAiPlugin"))
  AppleWebAuthPlugin.register(with: registry.registrar(forPlugin: "AppleWebAuthPlugin"))
  FLTFirebaseFirestorePlugin.register(with: registry.registrar(forPlugin: "FLTFirebaseFirestorePlugin"))
  FirebaseFunctionsPlugin.register(with: registry.registrar(forPlugin: "FirebaseFunctionsPlugin"))
  DeviceInfoPlusMacosPlugin.register(with: registry.registrar(forPlugin: "DeviceInfoPlusMacosPlugin"))
  FilePickerPlugin.register(with: registry.registrar(forPlugin: "FilePickerPlugin"))
  FileSelectorPlugin.register(with: registry.registrar(forPlugin: "FileSelectorPlugin"))
  FLTFirebaseAuthPlugin.register(with: registry.registrar(forPlugin: "FLTFirebaseAuthPlugin"))
  FLTFirebaseCorePlugin.register(with: registry.registrar(forPlugin: "FLTFirebaseCorePlugin"))
  FlutterImageCompressMacosPlugin.register(with: registry.registrar(forPlugin: "FlutterImageCompressMacosPlugin"))
  FLTGoogleSignInPlugin.register(with: registry.registrar(forPlugin: "FLTGoogleSignInPlugin"))
  LiquidGlassPlugin.register(with: registry.registrar(forPlugin: "LiquidGlassPlugin"))
  MobileScannerPlugin.register(with: registry.registrar(forPlugin: "MobileScannerPlugin"))
  FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
  ScreenRetrieverMacosPlugin.register(with: registry.registrar(forPlugin: "ScreenRetrieverMacosPlugin"))
  SharePlusMacosPlugin.register(with: registry.registrar(forPlugin: "SharePlusMacosPlugin"))
  SharedPreferencesPlugin.register(with: registry.registrar(forPlugin: "SharedPreferencesPlugin"))
  TrayManagerPlugin.register(with: registry.registrar(forPlugin: "TrayManagerPlugin"))
  UrlLauncherPlugin.register(with: registry.registrar(forPlugin: "UrlLauncherPlugin"))
  WebViewFlutterPlugin.register(with: registry.registrar(forPlugin: "WebViewFlutterPlugin"))
  WindowManagerPlugin.register(with: registry.registrar(forPlugin: "WindowManagerPlugin"))
}
