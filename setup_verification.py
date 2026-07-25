#!/usr/bin/env python3
"""
Firebase Setup Verification Script
Checks if your Firebase setup is complete and correct
Run: python setup_verification.py
"""

import os
import sys
import json
from pathlib import Path

# Colors for terminal output
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
RESET = '\033[0m'

def print_header(text):
    print(f"\n{BLUE}{'=' * 60}{RESET}")
    print(f"{BLUE}{text.center(60)}{RESET}")
    print(f"{BLUE}{'=' * 60}{RESET}\n")

def print_check(status, message, details=""):
    symbol = f"{GREEN}✓{RESET}" if status else f"{RED}✗{RESET}"
    print(f"  {symbol} {message}")
    if details:
        print(f"    {YELLOW}{details}{RESET}")

def check_file_exists(path, description):
    """Check if a file exists"""
    if os.path.exists(path):
        size = os.path.getsize(path)
        print_check(True, f"{description}", f"Found ({size} bytes)")
        return True
    else:
        print_check(False, f"{description}", f"Missing at {path}")
        return False

def check_directory_exists(path, description):
    """Check if a directory exists"""
    if os.path.isdir(path):
        print_check(True, f"{description}")
        return True
    else:
        print_check(False, f"{description}", f"Missing at {path}")
        return False

def check_json_valid(path):
    """Check if JSON file is valid"""
    try:
        with open(path, 'r') as f:
            json.load(f)
        return True
    except:
        return False

def check_files_structure():
    """Check if all required files are in place"""
    print_header("CHECKING FILE STRUCTURE")
    
    all_good = True
    
    # Android files
    print(f"{BLUE}Android Files:{RESET}")
    all_good &= check_file_exists(
        "android/app/google-services.json",
        "google-services.json"
    )
    
    # iOS files (optional)
    print(f"\n{BLUE}iOS Files (Optional):{RESET}")
    if os.path.exists("ios/Runner/GoogleService-Info.plist"):
        print_check(True, "GoogleService-Info.plist")
    else:
        print_check(False, "GoogleService-Info.plist (Optional)")
    
    # Flutter files
    print(f"\n{BLUE}Flutter Files:{RESET}")
    all_good &= check_file_exists(
        "lib/firebase_options.dart",
        "firebase_options.dart (auto-generated)"
    )
    all_good &= check_file_exists(
        "lib/main.dart",
        "main.dart"
    )
    all_good &= check_directory_exists(
        "lib/services",
        "services/ directory"
    )
    all_good &= check_file_exists(
        "lib/services/firebase_auth_service.dart",
        "firebase_auth_service.dart"
    )
    
    # Backend files
    print(f"\n{BLUE}Backend Files:{RESET}")
    all_good &= check_file_exists(
        "bus_tracking_backend/serviceAccountKey.json",
        "serviceAccountKey.json"
    )
    all_good &= check_file_exists(
        "bus_tracking_backend/config.py",
        "config.py"
    )
    
    # Pubspec
    print(f"\n{BLUE}Flutter Dependencies:{RESET}")
    all_good &= check_file_exists(
        "pubspec.yaml",
        "pubspec.yaml"
    )
    
    return all_good

def check_pubspec_dependencies():
    """Check if required packages are in pubspec.yaml"""
    print_header("CHECKING PUBSPEC.YAML DEPENDENCIES")
    
    required_packages = {
        'firebase_core': '^3.3.0',
        'firebase_auth': '^5.1.2',
        'google_sign_in': '^6.2.1',
        'geolocator': '^12.0.0',
        'web_socket_channel': '^2.4.0',
        'flutter_local_notifications': '^17.3.0',
        'shared_preferences': '^2.2.2',
        'http': '^1.1.0',
    }
    
    try:
        with open('pubspec.yaml', 'r') as f:
            content = f.read()
        
        all_good = True
        for package, version in required_packages.items():
            if package in content:
                print_check(True, f"{package}", f"Found (version {version} or compatible)")
            else:
                print_check(False, f"{package}", f"Missing from pubspec.yaml")
                all_good = False
        
        return all_good
    except Exception as e:
        print_check(False, "Unable to read pubspec.yaml", str(e))
        return False

def check_firebase_options():
    """Check if firebase_options.dart is properly configured"""
    print_header("CHECKING FIREBASE_OPTIONS.DART")
    
    try:
        with open('lib/firebase_options.dart', 'r') as f:
            content = f.read()
        
        checks = {
            'projectId': 'projectId defined',
            'apiKey': 'apiKey configured',
            'appId': 'appId set',
            'messagingSenderId': 'messagingSenderId configured',
        }
        
        all_good = True
        for key, desc in checks.items():
            if key in content:
                print_check(True, desc)
            else:
                print_check(False, desc, "Missing - run 'flutterfire configure'")
                all_good = False
        
        return all_good
    except Exception as e:
        print_check(False, "Unable to read firebase_options.dart", str(e))
        return False

def check_main_dart():
    """Check if main.dart is properly configured"""
    print_header("CHECKING MAIN.DART FIREBASE INITIALIZATION")
    
    try:
        with open('lib/main.dart', 'r') as f:
            content = f.read()
        
        checks = {
            'Firebase.initializeApp': 'Firebase initialization',
            'DefaultFirebaseOptions': 'Firebase options usage',
            'firebase_core': 'Firebase Core import',
            'firebase_options': 'Firebase options import',
        }
        
        all_good = True
        for check, desc in checks.items():
            if check in content:
                print_check(True, desc)
            else:
                print_check(False, desc, "Missing - add to main.dart")
                all_good = False
        
        return all_good
    except Exception as e:
        print_check(False, "Unable to read main.dart", str(e))
        return False

def check_backend_config():
    """Check if backend config is properly configured"""
    print_header("CHECKING BACKEND CONFIGURATION")
    
    try:
        with open('bus_tracking_backend/config.py', 'r') as f:
            content = f.read()
        
        checks = {
            'firebase_admin': 'Firebase Admin SDK import',
            'credentials.Certificate': 'Service account credentials',
            'initialize_app': 'Firebase app initialization',
        }
        
        all_good = True
        for check, desc in checks.items():
            if check in content:
                print_check(True, desc)
            else:
                print_check(False, desc, "Missing - add to config.py")
                all_good = False
        
        # Check if serviceAccountKey.json is valid
        print()
        if os.path.exists('bus_tracking_backend/serviceAccountKey.json'):
            if check_json_valid('bus_tracking_backend/serviceAccountKey.json'):
                print_check(True, "serviceAccountKey.json is valid JSON")
            else:
                print_check(False, "serviceAccountKey.json is not valid JSON")
                all_good = False
        else:
            print_check(False, "serviceAccountKey.json not found")
            all_good = False
        
        return all_good
    except Exception as e:
        print_check(False, "Unable to read config.py", str(e))
        return False

def check_firebase_auth_service():
    """Check if firebase_auth_service.dart exists and has key methods"""
    print_header("CHECKING FIREBASE AUTH SERVICE")
    
    try:
        with open('lib/services/firebase_auth_service.dart', 'r') as f:
            content = f.read()
        
        methods = {
            'signInWithGoogle': 'Google Sign-In method',
            'sendTokenToBackend': 'Backend token method',
            'getUserInfo': 'Get user info method',
            'signOut': 'Sign out method',
        }
        
        all_good = True
        for method, desc in methods.items():
            if method in content:
                print_check(True, desc)
            else:
                print_check(False, desc, "Missing method")
                all_good = False
        
        return all_good
    except Exception as e:
        print_check(False, "firebase_auth_service.dart", str(e))
        return False

def check_gitignore():
    """Check if .gitignore protects sensitive files"""
    print_header("CHECKING .GITIGNORE SECURITY")
    
    try:
        with open('.gitignore', 'r') as f:
            content = f.read()
        
        sensitive_files = {
            'serviceAccountKey.json': 'Service account key',
            '.env': 'Environment variables',
        }
        
        all_good = True
        for filename, desc in sensitive_files.items():
            if filename in content:
                print_check(True, f"{desc} ({filename}) is ignored")
            else:
                print_check(False, f"{desc} ({filename}) is NOT ignored", 
                           f"⚠️  Add '{filename}' to .gitignore")
                all_good = False
        
        return all_good
    except Exception as e:
        print_check(False, "Unable to read .gitignore", str(e))
        return False

def print_summary(results):
    """Print verification summary"""
    print_header("VERIFICATION SUMMARY")
    
    passed = sum(1 for r in results.values() if r)
    total = len(results)
    percentage = (passed / total) * 100
    
    print(f"Checks passed: {passed}/{total} ({percentage:.0f}%)\n")
    
    for check_name, result in results.items():
        symbol = f"{GREEN}✓{RESET}" if result else f"{RED}✗{RESET}"
        print(f"  {symbol} {check_name}")
    
    print()
    if percentage == 100:
        print(f"{GREEN}✓ All checks passed! Your Firebase setup is complete.{RESET}\n")
        print(f"{BLUE}Next steps:{RESET}")
        print(f"  1. flutter pub get")
        print(f"  2. flutter run -d chrome")
        print(f"  3. Click 'Sign in with Google' button")
        print()
    else:
        print(f"{YELLOW}⚠️  Some checks failed. Follow the instructions above to fix them.{RESET}\n")

def main():
    print(f"\n{BLUE}")
    print(f"  Firebase Setup Verification Tool")
    print(f"  ==================================")
    print(f"{RESET}")
    
    print(f"Checking your Firebase setup...\n")
    
    results = {
        'File Structure': check_files_structure(),
        'Pubspec Dependencies': check_pubspec_dependencies(),
        'Firebase Options': check_firebase_options(),
        'Main.dart Configuration': check_main_dart(),
        'Backend Configuration': check_backend_config(),
        'Firebase Auth Service': check_firebase_auth_service(),
        'Security (.gitignore)': check_gitignore(),
    }
    
    print_summary(results)

if __name__ == "__main__":
    main()
