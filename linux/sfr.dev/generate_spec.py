import sys

def validate_and_print_params(distribution, package_type, architecture, version_no, patch_no, build_no):
    # Check that mandatory parameters are provided
    mandatory_params = {
        "distribution": distribution,
        "package_type": package_type,
        "architecture": architecture,
        "version_no": version_no,
        "build_no": build_no
    }

    missing_params = [name for name, value in mandatory_params.items() if not value]

    if missing_params:
        print(f"Error: Missing required parameters: {', '.join(missing_params)}")
        sys.exit(1)

    # Print all parameters and their values
    print("Parameters received:")
    print(f"distribution = {distribution}")
    print(f"package_type = {package_type}")
    print(f"architecture = {architecture}")
    print(f"version_no = {version_no}")
    print(f"patch_no = {patch_no}")  # patch_no can be None
    print(f"build_no = {build_no}")

if __name__ == "__main__":
    if len(sys.argv) != 7:
        print("Usage: script.py <distribution> <package_type> <architecture> <version_no> <patch_no> <build_no>")
        sys.exit(1)

    # Unpack arguments
    _, distribution, package_type, architecture, version_no, patch_no, build_no = sys.argv

    # Call function
    validate_and_print_params(distribution, package_type, architecture, version_no, patch_no, build_no)
