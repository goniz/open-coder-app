#!/usr/bin/env python3
"""
iOS App IPA Builder Script with Ad-Hoc Signing

This script builds an iOS app and creates an IPA file using Xcode's command line tools,
configured for ad-hoc distribution (no App Store signing required).
"""

import subprocess
import sys
import os
import argparse
import shutil
from pathlib import Path
import logging
from datetime import datetime


class IPABuilder:
    def __init__(self, project_path=".", scheme="OpenCoder", configuration="Release", 
                 output_dir="./build", team_id=None):
        self.project_path = Path(project_path).resolve()
        self.scheme = scheme
        self.configuration = configuration
        self.output_dir = Path(output_dir).resolve()
        self.team_id = team_id
        
        # Set up logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('build.log'),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger(__name__)
        
        # Paths
        self.xcode_proj_path = self.project_path / "Xcode" / "OpenCoder.xcodeproj"
        self.workspace_path = self.project_path / "Xcode" / "OpenCoder.xcworkspace"
        self.archive_path = self.output_dir / f"{self.scheme}.xcarchive"
        self.ipa_path = self.output_dir / f"{self.scheme}.ipa"
        
    def setup_output_directory(self):
        """Create output directory if it doesn't exist."""
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.logger.info(f"Output directory: {self.output_dir}")
        
    def check_prerequisites(self):
        """Check if required tools and files exist."""
        # Check if xcodebuild is available
        try:
            result = subprocess.run(['xcodebuild', '-version'], 
                                  capture_output=True, text=True, check=True)
            self.logger.info(f"Xcode version: {result.stdout.strip()}")
        except (subprocess.CalledProcessError, FileNotFoundError):
            self.logger.error("xcodebuild not found. Please install Xcode and command line tools.")
            return False
            
        # Check project files
        if self.workspace_path.exists():
            self.build_target = str(self.workspace_path)
            self.build_type = "-workspace"
            self.logger.info(f"Using workspace: {self.workspace_path}")
        elif self.xcode_proj_path.exists():
            self.build_target = str(self.xcode_proj_path)
            self.build_type = "-project"
            self.logger.info(f"Using project: {self.xcode_proj_path}")
        else:
            self.logger.error("Neither .xcworkspace nor .xcodeproj found in expected location")
            return False
            
        return True
        
    def get_provisioning_profiles(self):
        """List available provisioning profiles."""
        try:
            result = subprocess.run([
                'security', 'find-identity', '-v', '-p', 'codesigning'
            ], capture_output=True, text=True, check=True)
            
            self.logger.info("Available code signing identities:")
            self.logger.info(result.stdout)
            
        except subprocess.CalledProcessError as e:
            self.logger.warning(f"Could not list code signing identities: {e}")
            
    def clean_project(self):
        """Clean the project before building."""
        self.logger.info("Cleaning project...")
        
        cmd = [
            'xcodebuild', 'clean',
            self.build_type, self.build_target,
            '-scheme', self.scheme,
            '-configuration', self.configuration
        ]
        
        try:
            subprocess.run(cmd, check=True, cwd=self.project_path)
            self.logger.info("Project cleaned successfully")
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Clean failed: {e}")
            raise
            
    def build_archive(self):
        """Build and archive the project."""
        self.logger.info(f"Building archive for scheme: {self.scheme}")
        
        # Remove existing archive if it exists
        if self.archive_path.exists():
            shutil.rmtree(self.archive_path)
            
        cmd = [
            'xcodebuild', 'archive',
            self.build_type, self.build_target,
            '-scheme', self.scheme,
            '-configuration', self.configuration,
            '-archivePath', str(self.archive_path),
            '-destination', 'generic/platform=iOS',
            'CODE_SIGN_STYLE=Automatic',
            '-allowProvisioningUpdates',
            '-skipMacroValidation',
            'SKIP_MACRO_VALIDATION=YES'
        ]
        
        # Add team ID if provided
        if self.team_id:
            cmd.extend(['DEVELOPMENT_TEAM=' + self.team_id])
        else:
            # Try to auto-detect team ID from signing identity
            try:
                result = subprocess.run(['security', 'find-identity', '-v', '-p', 'codesigning'], 
                                      capture_output=True, text=True, check=True)
                # Extract team ID from the first identity (assuming format includes team ID)
                if 'Apple Development:' in result.stdout:
                    # This is a simplified extraction - might need adjustment based on actual format
                    pass
            except:
                pass
            
        # Add ad-hoc provisioning profile settings
        cmd.extend([
            'PROVISIONING_PROFILE_SPECIFIER=',
            'CODE_SIGN_ENTITLEMENTS=OpenCoder/OpenCoder.entitlements'
        ])
        
        try:
            subprocess.run(cmd, check=True, cwd=self.project_path)
            self.logger.info("Archive built successfully")
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Archive failed: {e}")
            raise
            
    def export_ipa(self):
        """Export IPA from archive using ad-hoc distribution."""
        self.logger.info("Exporting IPA...")
        
        # Create export options plist for ad-hoc distribution
        export_options = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>ad-hoc</string>
    <key>teamID</key>
    <string>{self.team_id or ""}</string>
    <key>compileBitcode</key>
    <false/>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>thinning</key>
    <string>&lt;none&gt;</string>
</dict>
</plist>"""
        
        export_plist_path = self.output_dir / "ExportOptions.plist"
        with open(export_plist_path, 'w') as f:
            f.write(export_options)
            
        export_dir = self.output_dir / "export"
        if export_dir.exists():
            shutil.rmtree(export_dir)
            
        cmd = [
            'xcodebuild', '-exportArchive',
            '-archivePath', str(self.archive_path),
            '-exportPath', str(export_dir),
            '-exportOptionsPlist', str(export_plist_path)
        ]
        
        try:
            subprocess.run(cmd, check=True, cwd=self.project_path)
            
            # Move IPA to final location
            exported_ipa = export_dir / f"{self.scheme}.ipa"
            if exported_ipa.exists():
                if self.ipa_path.exists():
                    self.ipa_path.unlink()
                shutil.move(str(exported_ipa), str(self.ipa_path))
                self.logger.info(f"IPA exported successfully: {self.ipa_path}")
            else:
                self.logger.error("IPA file not found in export directory")
                
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Export failed: {e}")
            raise
            
    def get_ipa_info(self):
        """Get information about the generated IPA."""
        if not self.ipa_path.exists():
            return
            
        file_size = self.ipa_path.stat().st_size
        file_size_mb = file_size / (1024 * 1024)
        
        self.logger.info(f"IPA Details:")
        self.logger.info(f"  Path: {self.ipa_path}")
        self.logger.info(f"  Size: {file_size_mb:.1f} MB")
        self.logger.info(f"  Created: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        
    def build(self):
        """Main build process."""
        try:
            self.logger.info("Starting IPA build process...")
            
            if not self.check_prerequisites():
                return False
                
            self.setup_output_directory()
            self.get_provisioning_profiles()
            self.clean_project()
            self.build_archive()
            self.export_ipa()
            self.get_ipa_info()
            
            self.logger.info("Build completed successfully!")
            return True
            
        except Exception as e:
            self.logger.error(f"Build failed: {e}")
            return False


def main():
    parser = argparse.ArgumentParser(description="Build iOS IPA with ad-hoc signing")
    parser.add_argument("--project-path", default=".", 
                       help="Path to project directory (default: current directory)")
    parser.add_argument("--scheme", default="OpenCoder", 
                       help="Xcode scheme to build (default: OpenCoder)")
    parser.add_argument("--configuration", default="Release", 
                       help="Build configuration (default: Release)")
    parser.add_argument("--output-dir", default="./build", 
                       help="Output directory for IPA (default: ./build)")
    parser.add_argument("--team-id", 
                       help="Development team ID (optional)")
    parser.add_argument("--clean-only", action="store_true",
                       help="Only clean the project, don't build")
    
    args = parser.parse_args()
    
    builder = IPABuilder(
        project_path=args.project_path,
        scheme=args.scheme,
        configuration=args.configuration,
        output_dir=args.output_dir,
        team_id=args.team_id
    )
    
    if args.clean_only:
        try:
            builder.setup_output_directory()
            builder.clean_project()
            print("Project cleaned successfully")
        except Exception as e:
            print(f"Clean failed: {e}")
            sys.exit(1)
    else:
        success = builder.build()
        sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()